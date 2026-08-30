//! Sıkıştırılmış (STORE olmayan) RAR setlerinin oynatılması.
//!
//! RAR sıkıştırması rastgele erişimi desteklemez: çözülmüş akışın ortasına
//! atlamanın tek yolu baştan çözmektir. Bu modül bunu dürüstçe uygular:
//!
//! 1. Ciltler NNTP'den sırayla geçici bir dizine kopyalanır (sıkıştırılmış
//!    veri; yalnızca oynatma süresince yaşar, kapanışta silinir).
//! 2. libunrar (resmî unrar'ın Rust bağları) hedef video üyeyi büyüyen bir
//!    çıktı dosyasına arka planda çözer.
//! 3. Oynatıcı çıktı dosyasını Range istekleriyle okur: çözülmüş öneki
//!    anında servis edilir (gerçek seek), henüz çözülmemiş kuyruk decode
//!    hızına kadar bekletir (player bunu buffering olarak görür).
//!
//! Parolalı/solid arşivler libunrar tarafından yerel olarak ele alınır.

use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::ops::Range;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use thiserror::Error;
use tokio::io::{AsyncWrite, AsyncWriteExt};
use tokio::sync::watch;

use super::archive::{cancellation_requested, validate_range, VolumeSpoolReader};
use super::nntp::{NntpPool, TlsNntpConnector};
use super::nzb::NzbFile;
use super::rar::probe_compressed_plan;
use super::server::{content_type_for, RangeSource};

/// Spool/decode döngüsünde tek parçada taşınan bayt sayısı.
const COPY_CHUNK: u64 = 4 * 1024 * 1024;
/// Çözülmemiş kuyruğu bekleyen okuyucunun yoklama aralığı.
const WAIT_POLL: Duration = Duration::from_millis(150);

const STATUS_SPOOLING: u8 = 0;
const STATUS_DECODING: u8 = 1;
const STATUS_DONE: u8 = 2;
const STATUS_FAILED: u8 = 3;
const STATUS_CANCELLED: u8 = 4;

#[derive(Debug, Error)]
pub(crate) enum CompressedRarError {
    #[error("could not prepare compressed RAR set: {0}")]
    Io(#[from] io::Error),
    #[error("{0}")]
    Rar(#[from] super::rar::RarError),
}

/// Decode arka plan görevinin paylaşılan durumu.
struct DecodeShared {
    status: AtomicU8,
    error: Mutex<Option<String>>,
    cancellation: watch::Receiver<bool>,
}

impl DecodeShared {
    fn status(&self) -> u8 {
        self.status.load(Ordering::Acquire)
    }

    fn set_failed(&self, message: String) {
        *self.error.lock().unwrap_or_else(|e| e.into_inner()) = Some(message);
        self.status.store(STATUS_FAILED, Ordering::Release);
    }
}

/// Oynatıcıya doğrudan medya dosyası gibi görünen sıkıştırılmış RAR içeriği.
pub(crate) struct CompressedRarEntrySource {
    filename: String,
    content_type: &'static str,
    total_len: u64,
    segment_count: usize,
    output_path: PathBuf,
    temp_dir: PathBuf,
    shared: Arc<DecodeShared>,
}

impl CompressedRarEntrySource {
    pub async fn new_cancellable(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        files: Vec<NzbFile>,
        password: Option<String>,
        cancellation: watch::Receiver<bool>,
    ) -> Result<Self, CompressedRarError> {
        let Some((plan, archive)) =
            probe_compressed_plan(pool, files, password.clone(), cancellation.clone()).await?
        else {
            // STORE set: çağıran normal RAR yolunu kullanmalı.
            return Err(CompressedRarError::Rar(
                super::rar::RarError::InvalidLayout(
                    "probe reported STORE set on the compressed path".into(),
                ),
            ));
        };

        let temp_dir = std::env::temp_dir().join(format!(
            "zanzibarr-rar-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis())
                .unwrap_or(0)
        ));
        fs::create_dir_all(&temp_dir)?;
        let output_path = temp_dir.join("video.out");

        let segment_count = archive.segment_count();
        let shared = Arc::new(DecodeShared {
            status: AtomicU8::new(STATUS_SPOOLING),
            error: Mutex::new(None),
            cancellation: cancellation.clone(),
        });

        // Arka plan: spool (NNTP → disk) → decode (libunrar → büyüyen çıktı).
        let task_shared = Arc::clone(&shared);
        let task_temp_dir = temp_dir.clone();
        let task_output = output_path.clone();
        let target_name = plan.filename.clone();
        tokio::spawn(async move {
            let result = spool_and_decode(
                archive.as_ref(),
                &task_temp_dir,
                &task_output,
                &target_name,
                password.as_deref(),
                task_shared.clone(),
            )
            .await;
            let _ = result;
        });

        Ok(Self {
            content_type: content_type_for(&plan.filename),
            filename: plan.filename,
            total_len: plan.unpacked_size,
            segment_count,
            output_path,
            temp_dir,
            shared,
        })
    }

    pub fn filename(&self) -> &str {
        &self.filename
    }

    pub fn segment_count(&self) -> usize {
        self.segment_count
    }

    /// Çözülmüş çıktının şu anki uzunluğu; dosya henüz yoksa 0.
    fn decoded_len(&self) -> u64 {
        fs::metadata(&self.output_path).map(|m| m.len()).unwrap_or(0)
    }

    /// `position`'ın okunabilir olana dek bekler. Döndürülen değer o anki
    /// çözülmüş uzunluk (> position). Bitti/başarısız/iptal durumlarında
    /// yalnızca hedefe hiç ulaşılamayacaksa hata verir.
    async fn wait_until_available(&self, position: u64) -> io::Result<u64> {
        loop {
            let len = self.decoded_len();
            if len > position {
                return Ok(len);
            }
            match self.shared.status() {
                STATUS_DONE => {
                    return Err(io::Error::new(
                        io::ErrorKind::UnexpectedEof,
                        format!(
                            "compressed RAR decode ended at {len} bytes, expected {}",
                            self.total_len
                        ),
                    ));
                }
                STATUS_FAILED => {
                    let message = self
                        .shared
                        .error
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .clone()
                        .unwrap_or_else(|| "compressed RAR decode failed".into());
                    return Err(io::Error::new(io::ErrorKind::InvalidData, message));
                }
                STATUS_CANCELLED => {
                    return Err(io::Error::new(
                        io::ErrorKind::Interrupted,
                        "compressed RAR decode cancelled",
                    ));
                }
                _ => {}
            }
            if cancellation_requested(&self.shared.cancellation) {
                return Err(io::Error::new(
                    io::ErrorKind::Interrupted,
                    "compressed RAR read cancelled",
                ));
            }
            tokio::time::sleep(WAIT_POLL).await;
        }
    }
}

impl Drop for CompressedRarEntrySource {
    fn drop(&mut self) {
        // Geçici dizin en iyi çabayla silinir; arka plan görevi hâlâ
        // çalışıyorsa yazımları eksik dosyalara çarpıp hata ile sonlanır.
        let _ = fs::remove_dir_all(&self.temp_dir);
    }
}

impl RangeSource for CompressedRarEntrySource {
    fn total_len(&self) -> u64 {
        self.total_len
    }

    fn content_type(&self) -> &str {
        self.content_type
    }

    async fn write_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        validate_range(range.clone(), self.total_len)?;
        let mut position = range.start;
        while position < range.end {
            let available = self.wait_until_available(position).await?;
            let take = (range.end.min(available) - position).min(COPY_CHUNK);
            let path = self.output_path.clone();
            let bytes = tokio::task::spawn_blocking(move || {
                let mut file = File::open(&path)?;
                file.seek(SeekFrom::Start(position))?;
                let mut buffer = vec![0u8; take as usize];
                file.read_exact(&mut buffer)?;
                Ok::<Vec<u8>, io::Error>(buffer)
            })
            .await
            .map_err(|error| io::Error::other(format!("read task failed: {error}")))??;
            out.write_all(&bytes).await?;
            position += take;
        }
        out.flush().await
    }
}

/// Ciltleri sırayla diske kopyalar (NNTP → temp dir), ardından libunrar ile
/// hedef üyeyi çıktı dosyasına çözer. Hata metni okunaklı tutulur.
async fn spool_and_decode(
    archive: &dyn VolumeSpoolReader,
    temp_dir: &Path,
    output_path: &Path,
    target_name: &str,
    password: Option<&str>,
    shared: Arc<DecodeShared>,
) -> Result<(), String> {
    fs::create_dir_all(temp_dir).map_err(|e| e.to_string())?;
    let first_name = spool_volumes(archive, temp_dir, &shared)
        .await
        .map_err(|e| e.to_string())?;

    if cancellation_requested(&shared.cancellation) {
        return Err("cancelled".into());
    }
    shared.status.store(STATUS_DECODING, Ordering::Release);

    let first_volume = temp_dir.join(first_name);
    let output = output_path.to_path_buf();
    let target = target_name.to_string();
    let password = password.map(|p| p.to_string());
    let result = tokio::task::spawn_blocking(move || {
        decode_member(&first_volume, &target, &output, password.as_deref())
    })
    .await
    .map_err(|e| format!("decode task panicked: {e}"))?;
    match result {
        Ok(()) => {
            shared.status.store(STATUS_DONE, Ordering::Release);
            Ok(())
        }
        Err(message) => {
            shared.set_failed(message.clone());
            Err(message)
        }
    }
}

/// Ciltleri NZB sırasıyla temp dizine yazar; cilt adları libunrar'ın
/// çok-cilt keşfinin beklediği özgün adlardır. Dönen değer ilk cildin
/// dosya adıdır (decode başlangıcı).
async fn spool_volumes(
    archive: &dyn VolumeSpoolReader,
    temp_dir: &Path,
    shared: &Arc<DecodeShared>,
) -> io::Result<String> {
    let mut first_name = String::new();
    for index in 0..archive.volume_count() {
        if cancellation_requested(&shared.cancellation) {
            return Err(io::Error::new(io::ErrorKind::Interrupted, "spool cancelled"));
        }
        let name = sanitize_volume_name(&archive.volume_name(index), index);
        if index == 0 {
            first_name = name.clone();
        }
        let path = temp_dir.join(name);
        let mut file = fs::File::create(&path)?;
        let mut cursor = 0u64;
        let volume_len = archive.volume_len(index);
        let volume_start = archive.volume_start(index);
        while cursor < volume_len {
            if cancellation_requested(&shared.cancellation) {
                return Err(io::Error::new(io::ErrorKind::Interrupted, "spool cancelled"));
            }
            let take = (volume_len - cursor).min(COPY_CHUNK);
            let bytes = archive
                .read_range_bytes(volume_start + cursor..volume_start + cursor + take)
                .await?;
            if bytes.is_empty() {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    format!("volume {index} ended early at {cursor}/{volume_len}"),
                ));
            }
            file.write_all(&bytes)?;
            cursor += bytes.len() as u64;
        }
        file.sync_all().ok();
    }
    Ok(first_name)
}

/// libunrar ile hedef üyeyi (ilk cilt yolu verilir; kardeş ciltler aynı
/// dizinde ad dizgesinden otomatik keşfedilir) çıktı dosyasına çözer.
fn decode_member(
    first_volume: &Path,
    target_name: &str,
    output_path: &Path,
    password: Option<&str>,
) -> Result<(), String> {
    let list: Vec<(String, u64, bool)> = {
        // Başlık-şifreli (-hp) arşivlerde listeleme de parola ister.
        let archive = match password {
            Some(pw) => unrar::Archive::with_password(first_volume, pw)
                .open_for_listing()
                .map_err(|e| format!("could not open RAR for listing: {e}"))?,
            None => unrar::Archive::new(first_volume)
                .open_for_listing()
                .map_err(|e| format!("could not open RAR for listing: {e}"))?,
        };
        let mut entries = Vec::new();
        for item in archive {
            let header = item.map_err(|e| format!("could not read RAR header: {e}"))?;
            if header.is_file() {
                entries.push((
                    header.filename.to_string_lossy().into_owned(),
                    header.unpacked_size,
                    header.is_encrypted(),
                ));
            }
        }
        entries
    };
    if list.is_empty() {
        return Err("no file entry in the RAR archive".into());
    }
    let target_encrypted = list
        .iter()
        .find(|(name, _, _)| name == target_name)
        .map(|(_, _, encrypted)| *encrypted);
    if target_encrypted == Some(true) && password.is_none() {
        return Err("RAR archive is password-protected and the NZB carries no password".into());
    }

    let mut archive = match password {
        Some(pw) => unrar::Archive::with_password(first_volume, pw)
            .open_for_processing()
            .map_err(|e| format!("could not open RAR for decoding: {e}"))?,
        None => unrar::Archive::new(first_volume)
            .open_for_processing()
            .map_err(|e| format!("could not open RAR for decoding: {e}"))?,
    };

    while let Some(header) = archive
        .read_header()
        .map_err(|e| format!("could not read RAR entry: {e}"))?
    {
        let name = header.entry().filename.to_string_lossy().into_owned();
        let is_file = header.entry().is_file();
        if is_file && name == target_name {
            header
                .extract_to(output_path)
                .map_err(|e| format!("could not decode `{target_name}`: {e}"))?;
            return Ok(());
        }
        archive = header
            .skip()
            .map_err(|e| format!("could not skip RAR entry `{name}`: {e}"))?;
    }
    Err(format!("entry `{target_name}` not found during decode"))
}

/// Cilt adını güvenli bir dosya adına indirger (yol bileşenleri atılır).
fn sanitize_volume_name(name: &str, index: usize) -> String {
    let base = name
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(name)
        .trim();
    if base.is_empty() {
        format!("volume{index:05}.rar")
    } else {
        base.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::future::Future;

    /// Bellek içi cilt kümesi: spool döngüsünü NNTP olmadan sınar.
    struct MemoryVolumes {
        volumes: Vec<(String, Vec<u8>)>,
    }

    impl VolumeSpoolReader for MemoryVolumes {
        fn volume_count(&self) -> usize {
            self.volumes.len()
        }

        fn volume_start(&self, index: usize) -> u64 {
            self.volumes[..index].iter().map(|v| v.1.len() as u64).sum()
        }

        fn volume_len(&self, index: usize) -> u64 {
            self.volumes[index].1.len() as u64
        }

        fn volume_name(&self, index: usize) -> String {
            self.volumes[index].0.clone()
        }

        fn read_range_bytes(
            &self,
            range: Range<u64>,
        ) -> std::pin::Pin<Box<dyn Future<Output = io::Result<Vec<u8>>> + Send + '_>> {
            // Testlerde tek cilt kullanılır; aralık sanal set uzayındadır.
            let mut out = Vec::new();
            let mut cursor = 0u64;
            for (_, data) in &self.volumes {
                let start = cursor;
                let end = cursor + data.len() as u64;
                let from = range.start.max(start);
                let to = range.end.min(end);
                if from < to {
                    out.extend_from_slice(&data[(from - start) as usize..(to - start) as usize]);
                }
                cursor = end;
            }
            Box::pin(async move { Ok(out) })
        }
    }

    impl MemoryVolumes {
        fn single(name: &str, data: Vec<u8>) -> Self {
            Self {
                volumes: vec![(name.to_string(), data)],
            }
        }
    }

    fn shared_running() -> (watch::Sender<bool>, Arc<DecodeShared>) {
        let (sender, receiver) = watch::channel(false);
        let shared = Arc::new(DecodeShared {
            status: AtomicU8::new(STATUS_SPOOLING),
            error: Mutex::new(None),
            cancellation: receiver,
        });
        (sender, shared)
    }

    #[test]
    fn volume_names_sanitized() {
        assert_eq!(sanitize_volume_name("a/b\\c.mkv", 0), "c.mkv");
        assert_eq!(sanitize_volume_name("  ", 3), "volume00003.rar");
        assert_eq!(sanitize_volume_name("movie.part01.rar", 1), "movie.part01.rar");
    }

    #[tokio::test]
    async fn spool_writes_volumes_in_order() {
        let (_sender, shared) = shared_running();
        let volumes = MemoryVolumes {
            volumes: vec![
                ("set.part01.rar".into(), vec![1u8; 10]),
                ("set.part02.rar".into(), vec![2u8; 10]),
            ],
        };
        let dir = std::env::temp_dir().join(format!("zanzibarr-spool-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();

        let first = spool_volumes(&volumes, &dir, &shared).await.unwrap();

        assert_eq!(first, "set.part01.rar");
        assert_eq!(fs::read(dir.join("set.part01.rar")).unwrap(), vec![1u8; 10]);
        assert_eq!(fs::read(dir.join("set.part02.rar")).unwrap(), vec![2u8; 10]);
        fs::remove_dir_all(&dir).ok();
    }

    const MOVIE_SHA256: &str =
        "06a59b464664418ec2748852dc01bbd5ee9a614624305ab99ab7fc0d3a7852b5";

    fn sha256_hex(data: &[u8]) -> String {
        use sha2::Digest;
        let digest = sha2::Sha256::digest(data);
        digest.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn fixture_path(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    #[test]
    fn decode_extracts_compressed_fixture() {
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/compressed-movie.rar");
        if !fixture.exists() {
            eprintln!("fixture yok, test atlanıyor: {}", fixture.display());
            return;
        }
        let out = std::env::temp_dir().join(format!("zanzibarr-decode-test-{}.mkv", std::process::id()));
        decode_member(&fixture, "movie.mkv", &out, None).unwrap();
        let data = fs::read(&out).unwrap();
        assert_eq!(sha256_hex(&data), MOVIE_SHA256);
        fs::remove_file(&out).ok();
    }

    #[test]
    fn decode_handles_multipart_compressed_set() {
        let out = std::env::temp_dir()
            .join(format!("zanzibarr-split-test-{}.mkv", std::process::id()));
        let first = fixture_path("compressed-split.part01.rar");
        decode_member(&first, "movie.mkv", &out, None).unwrap();
        let data = fs::read(&out).unwrap();
        assert_eq!(sha256_hex(&data), MOVIE_SHA256);
        fs::remove_file(&out).ok();
    }

    #[test]
    fn decode_extracts_hp_encrypted_with_password() {
        let out = std::env::temp_dir()
            .join(format!("zanzibarr-enc-test-{}.mkv", std::process::id()));
        let first = fixture_path("encrypted-movie.rar");
        decode_member(&first, "movie.mkv", &out, Some("TESTPASS123")).unwrap();
        let data = fs::read(&out).unwrap();
        assert_eq!(sha256_hex(&data), MOVIE_SHA256);
        fs::remove_file(&out).ok();
    }

    #[test]
    fn decode_rejects_wrong_password() {
        let out = std::env::temp_dir()
            .join(format!("zanzibarr-encw-test-{}.mkv", std::process::id()));
        let first = fixture_path("encrypted-movie.rar");
        let result = decode_member(&first, "movie.mkv", &out, Some("YANLIS"));
        assert!(result.is_err(), "yanlış parola kabul edilmemeli");
        fs::remove_file(&out).ok();
    }

    #[tokio::test]
    async fn spool_and_decode_end_to_end() {
        let (_sender, shared) = shared_running();
        let fixture = fs::read(fixture_path("compressed-movie.rar")).unwrap();
        let volumes = MemoryVolumes::single("film.rar", fixture);
        let dir = std::env::temp_dir()
            .join(format!("zanzibarr-e2e-test-{}", std::process::id()));
        let output = dir.join("video.out");

        spool_and_decode(&volumes, &dir, &output, "movie.mkv", None, shared.clone())
            .await
            .unwrap();

        let data = fs::read(&output).unwrap();
        assert_eq!(sha256_hex(&data), MOVIE_SHA256);
        assert_eq!(shared.status(), STATUS_DONE);
        fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn write_range_waits_for_growing_output() {
        // Çözülmüş çıktıyı taklit eden, yavaş büyüyen bir dosya: okuyucu
        // henüz yazılmamış aralığı beklemeli, sonra servis etmeli.
        let dir = std::env::temp_dir()
            .join(format!("zanzibarr-grow-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let output = dir.join("video.out");
        let expected: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();

        let (_sender, shared) = shared_running();
        let writer_data = expected.clone();
        let writer_path = output.clone();
        let writer_shared = shared.clone();
        tokio::spawn(async move {
            let mut file = fs::File::create(&writer_path).unwrap();
            for chunk in writer_data.chunks(20_000) {
                file.write_all(chunk).unwrap();
                file.sync_all().ok();
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            writer_shared.status.store(STATUS_DONE, Ordering::Release);
        });

        let source = CompressedRarEntrySource {
            filename: "movie.mkv".into(),
            content_type: "video/x-matroska",
            total_len: expected.len() as u64,
            segment_count: 1,
            output_path: output.clone(),
            temp_dir: dir.clone(),
            shared,
        };

        // Baştan, ortadan (henüz yazılmamış olabilir) ve sondan oku.
        let mut buf = Vec::new();
        source
            .write_range(0..expected.len() as u64, &mut buf)
            .await
            .unwrap();
        assert_eq!(buf, expected);
        fs::remove_dir_all(&dir).ok();
    }
}
