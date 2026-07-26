//! PAR2 onarım düzenlemesi: hasarlı dilimleri keşfet, Reed-Solomon ile onar
//! ve yerel katmana (overlay) yaz.
//!
//! Tasarım sınırları (PAR2'nin doğası): onarım, recovery set'in TÜM sağlam
//! dilimlerini bir kez okumayı gerektirir — tek bozuk segment bile global
//! RS matrisine bağlıdır. Bu yüzden akış iki tam turdan ibarettir:
//!
//! 1. **Doğrulama turu:** her dosyanın her dilimi okunur, IFSC (MD5+CRC32)
//!    ile karşılaştırılır; bozuk/eksik dilimler toplanır. Oynatma sırasında
//!    yakalanan hasar burada da zaten yakalanır — ayrı bir taramaya gerek yok.
//! 2. **Onarım turu:** [`par2::plan_repair`] ile matris çözülür, sağlam
//!    dilimler ikinci kez okunarak yalnız eksik dilimlerin akümülatörleri
//!    beslenir (bellekte tüm set tutulmaz). Tur sırasında "sağlam" sanılan
//!    bir dilim de bozuk çıkarsa plan genişletilip yeniden çözülür.
//!
//! Onarılan dilimler diske katman olarak yazılır; sonraki oynatmalarda
//! [`crate::engine::nntp_source::NntpByteSource`] hasarlı bölgeyi ağa
//! hiç çıkmadan katmandan servis eder. Katman dizini yalnızca NZB yolunun
//! özetiyle adlandırılır; içerik sırrı taşımaz.

use std::collections::{BTreeMap, HashMap};
use std::io;
use std::ops::Range;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use sha2::Digest;
use thiserror::Error;
use tokio::sync::watch;

use super::archive::{cancellation_requested, wait_for_cancellation};
use super::par2::{self, FileDesc, Par2Error, Par2Set, SliceHealth};

/// Doğrulama/onarım turlarında eşzamanlı dilim okuma sayısı.
const SLICE_CONCURRENCY: usize = 16;
/// Onarım turunda yeni hasar keşfedince yeniden çözüm sınırı.
const MAX_RESOLVE: usize = 2;

#[derive(Debug, Error)]
pub enum RepairError {
    #[error("onarım okuması başarısız: {0}")]
    Io(#[from] io::Error),
    #[error("{0}")]
    Par2(#[from] Par2Error),
    #[error("NZB'de ana PAR2 dizin dosyası yok")]
    NoPar2Index,
    #[error("onarım iptal edildi")]
    Cancelled,
}

// ---------------------------------------------------------------------------
// Fetch soyutlaması
// ---------------------------------------------------------------------------

/// Onarımın ihtiyaç duyduğu minimal okuma yüzeyi. Gerçek hali NZB+NNTP'dir;
/// testlerde bellek içi sahte.
pub trait RepairFetcher: Send + Sync {
    /// Dosya NZB'de mevcut mu? (Hiç yoksa tüm dilimleri Missing sayılır.)
    fn has_file(&self, name: &str) -> bool;
    /// Dosyanın bayt aralığını okur; hasarlı bölge hatayla dönebilir.
    fn read_range<'a>(
        &'a self,
        name: &'a str,
        range: Range<u64>,
    ) -> impl std::future::Future<Output = io::Result<Vec<u8>>> + Send + 'a;
    /// Küçük .par2 dosyasının tamamını okur.
    fn read_par2<'a>(
        &'a self,
        name: &'a str,
    ) -> impl std::future::Future<Output = io::Result<Vec<u8>>> + Send + 'a;
}

// ---------------------------------------------------------------------------
// İlerleme
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RepairPhase {
    LoadingPar2,
    Verifying,
    Solving,
    Repairing,
    Writing,
    Done,
}

#[derive(Debug, Clone)]
pub struct RepairProgress {
    pub phase: RepairPhase,
    /// Faz içinde tamamlanan bayt (doğrulama/onarım turlarında anlamlı).
    pub completed_bytes: u64,
    /// Faz toplamı; 0 ise belirsiz.
    pub total_bytes: u64,
    pub detail: String,
}

pub type RepairProgressFn = dyn Fn(RepairProgress) + Send + Sync;

#[derive(Debug)]
pub struct RepairReport {
    pub verified_files: u32,
    pub damaged_slices: u32,
    pub repaired_slices: u32,
    /// Hasarsız sette overlay yazılmaz ve None döner.
    pub overlay_dir: Option<PathBuf>,
}

// ---------------------------------------------------------------------------
// Katman (overlay)
// ---------------------------------------------------------------------------

/// Tek dosyanın onarılmış dilimleri. Dilimler PAR2 dilim boyutunda ve son
/// dilim sıfır dolguludur.
#[derive(Debug, Clone)]
pub struct FileOverlay {
    pub file_len: u64,
    pub slice_size: u64,
    pub slices: BTreeMap<u64, Arc<Vec<u8>>>,
}

impl FileOverlay {
    /// `offset`'i kapsayan onarılmış dilimi (dilim indeksiyle) döndürür.
    pub fn slice_covering(&self, offset: u64) -> Option<(u64, &Arc<Vec<u8>>)> {
        let index = offset / self.slice_size;
        self.slices.get(&index).map(|data| (index, data))
    }

    /// `cursor`'dan sonraki ilk onarılmış dilimin başlangıcı; yoksa dosya sonu.
    pub fn next_slice_start(&self, cursor: u64) -> u64 {
        self.slices
            .range((cursor / self.slice_size + 1)..)
            .next()
            .map(|(index, _)| index * self.slice_size)
            .unwrap_or(self.file_len)
            .min(self.file_len)
    }
}

/// Bir NZB'nin tüm onarılmış dosyaları. Anahtar: küçük harf dosya adı.
#[derive(Debug, Default)]
pub struct RepairOverlay {
    files: HashMap<String, FileOverlay>,
}

impl RepairOverlay {
    pub fn for_file(&self, name: &str) -> Option<&FileOverlay> {
        self.files.get(&name.to_ascii_lowercase())
    }

    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }

    fn insert(&mut self, name: &str, overlay: FileOverlay) {
        self.files.insert(name.to_ascii_lowercase(), overlay);
    }

    /// NZB yolu için katman dizini: temp/zanzibarr-repair/<özet>.
    pub fn dir_for_nzb(nzb_path: &Path) -> PathBuf {
        let key = sha2::Sha256::digest(nzb_path.to_string_lossy().as_bytes());
        let short: String = key[..8].iter().map(|b| format!("{b:02x}")).collect();
        std::env::temp_dir().join("zanzibarr-repair").join(short)
    }

    /// Katmanı diske yazar. Dizin yapısı: manifest.tsv + <özet>/<dilim>.bin.
    pub fn save(&self, dir: &Path) -> io::Result<()> {
        std::fs::create_dir_all(dir)?;
        let mut manifest = String::new();
        for (name, overlay) in &self.files {
            let bucket = name_bucket(name);
            let file_dir = dir.join(&bucket);
            std::fs::create_dir_all(&file_dir)?;
            manifest.push_str(&format!(
                "{bucket}\t{}\t{}\n",
                overlay.file_len, overlay.slice_size
            ));
            for (index, data) in &overlay.slices {
                std::fs::write(file_dir.join(format!("{index}.bin")), data.as_slice())?;
            }
            // Dosya adı eşlemesi manifestte değil bucket adında değil —
            // adı kaybetmemek için ayrı bir name dosyası yazılır.
            std::fs::write(file_dir.join("name.txt"), name)?;
        }
        std::fs::write(dir.join("manifest.tsv"), manifest)?;
        Ok(())
    }

    /// Diskten katmanı yükler; dizin yoksa None.
    pub fn load(dir: &Path) -> io::Result<Option<RepairOverlay>> {
        let manifest_path = dir.join("manifest.tsv");
        if !manifest_path.is_file() {
            return Ok(None);
        }
        let manifest = std::fs::read_to_string(&manifest_path)?;
        let mut overlay = RepairOverlay::default();
        for line in manifest.lines() {
            let mut fields = line.split('\t');
            let (Some(bucket), Some(file_len), Some(slice_size)) =
                (fields.next(), fields.next(), fields.next())
            else {
                continue;
            };
            let file_dir = dir.join(bucket);
            let name = std::fs::read_to_string(file_dir.join("name.txt"))?;
            let mut slices = BTreeMap::new();
            for entry in std::fs::read_dir(&file_dir)? {
                let entry = entry?;
                let Some(index) = entry
                    .file_name()
                    .to_str()
                    .and_then(|n| n.strip_suffix(".bin"))
                    .and_then(|n| n.parse::<u64>().ok())
                else {
                    continue;
                };
                slices.insert(index, Arc::new(std::fs::read(entry.path())?));
            }
            if slices.is_empty() {
                continue;
            }
            overlay.insert(
                &name,
                FileOverlay {
                    file_len: file_len.parse().map_err(|_| {
                        io::Error::new(io::ErrorKind::InvalidData, "bozuk manifest")
                    })?,
                    slice_size: slice_size.parse().map_err(|_| {
                        io::Error::new(io::ErrorKind::InvalidData, "bozuk manifest")
                    })?,
                    slices,
                },
            );
        }
        Ok((!overlay.is_empty()).then_some(overlay))
    }
}

fn name_bucket(name: &str) -> String {
    let hash = sha2::Sha256::digest(name.as_bytes());
    hash[..8].iter().map(|b| format!("{b:02x}")).collect()
}

// ---------------------------------------------------------------------------
// Düzenleme
// ---------------------------------------------------------------------------

/// Recovery set'i onarır. `par2_names`, NZB'deki tüm `.par2` dosyalarıdır;
/// `.vol` içermeyen ilk dosya ana dizin sayılır. İlerleme `progress` ile
/// akar; iptal watch'ı tur sınırlarında ve okumalarda etkilidir.
pub async fn repair_release<F: RepairFetcher + 'static>(
    fetcher: &Arc<F>,
    par2_names: &[String],
    overlay_dir: &Path,
    progress: &RepairProgressFn,
    cancellation: Option<watch::Receiver<bool>>,
) -> Result<RepairReport, RepairError> {
    ensure_active(&cancellation)?;
    // 1. Ana dizini ve (gerektikçe) vol dosyalarını yükle.
    emit(progress, RepairPhase::LoadingPar2, 0, 0, "PAR2 dizini okunuyor");
    let index_name = par2_names
        .iter()
        .find(|name| !name.to_ascii_lowercase().contains(".vol"))
        .ok_or(RepairError::NoPar2Index)?;
    let index_bytes = fetcher.read_par2(index_name).await?;
    let mut set = Par2Set::from_parts(&[index_bytes.as_slice()])?;
    let total_bytes: u64 = set.files.iter().map(|f| f.length).sum();
    let done_bytes = AtomicU64::new(0);

    // 2. Doğrulama turu: tüm dilimler IFSC ile karşılaştırılır.
    emit(progress, RepairPhase::Verifying, 0, total_bytes, "dilimler doğrulanıyor");
    let mut damaged: Vec<u64> = Vec::new();
    let mut verified_files = 0u32;
    for file in &set.files {
        ensure_active(&cancellation)?;
        let health = verify_file(
            fetcher,
            &set,
            file,
            progress,
            total_bytes,
            &done_bytes,
            &cancellation,
        )
        .await?;
        let map_first: u64 = set
            .global_slice_map()
            .iter()
            .find(|(index, _, _)| set.files[*index].id == file.id)
            .map(|(_, first, _)| *first)
            .expect("dosya haritada var");
        for (index, state) in health.iter().enumerate() {
            if *state != SliceHealth::Ok {
                damaged.push(map_first + index as u64);
            }
        }
        verified_files += 1;
    }

    if damaged.is_empty() {
        emit(progress, RepairPhase::Done, total_bytes, total_bytes, "set temiz");
        return Ok(RepairReport {
            verified_files,
            damaged_slices: 0,
            repaired_slices: 0,
            overlay_dir: None,
        });
    }

    // 3. Vol dosyalarını yeterli kurtarma dilimi birikene dek oku.
    let vol_names: Vec<&String> = par2_names
        .iter()
        .filter(|name| name.to_ascii_lowercase().contains(".vol"))
        .collect();
    let mut parts: Vec<Vec<u8>> = vec![index_bytes];
    for vol in vol_names {
        if set.recovery.len() >= damaged.len() {
            break;
        }
        emit(progress, RepairPhase::LoadingPar2, 0, 0, "kurtarma verisi okunuyor");
        parts.push(fetcher.read_par2(vol).await?);
        let refs: Vec<&[u8]> = parts.iter().map(Vec::as_slice).collect();
        set = Par2Set::from_parts(&refs)?;
    }

    // 4. Çöz + onar (yeni hasar keşfiyle sınırlı yeniden denemeyle).
    let mut attempt = 0usize;
    let repaired = loop {
        ensure_active(&cancellation)?;
        emit(progress, RepairPhase::Solving, 0, 0, "matris çözülüyor");
        let plan = par2::plan_repair(&set, &damaged)?;
        match run_repair_pass(
            fetcher,
            &set,
            &plan,
            progress,
            &done_bytes,
            total_bytes,
            &cancellation,
        )
        .await
        {
            Ok(repaired) => break repaired,
            Err(RepairPassFailure::NewDamage(newly)) => {
                attempt += 1;
                if attempt > MAX_RESOLVE {
                    return Err(RepairError::Par2(Par2Error::RepairMismatch(
                        u64::MAX,
                    )));
                }
                for index in newly {
                    if !damaged.contains(&index) {
                        damaged.push(index);
                    }
                }
            }
            Err(RepairPassFailure::Cancelled) => return Err(RepairError::Cancelled),
            Err(RepairPassFailure::Io(error)) => return Err(RepairError::Io(error)),
        }
    };

    // 5. Katmanı yaz.
    emit(progress, RepairPhase::Writing, 0, 0, "katman yazılıyor");
    let mut overlay = RepairOverlay::default();
    let map = set.global_slice_map();
    let mut per_file: HashMap<usize, FileOverlay> = HashMap::new();
    for (global, data) in &repaired {
        let (file_index, first, _) = map
            .iter()
            .find(|(_, f, c)| *global >= *f && *global < *f + *c)
            .copied()
            .expect("dilim haritada var");
        let file = &set.files[file_index];
        per_file
            .entry(file_index)
            .or_insert_with(|| FileOverlay {
                file_len: file.length,
                slice_size: set.slice_size,
                slices: BTreeMap::new(),
            })
            .slices
            .insert(global - first, Arc::new(data.clone()));
    }
    for (file_index, file_overlay) in per_file {
        overlay.insert(&set.files[file_index].name, file_overlay);
    }
    overlay.save(overlay_dir)?;

    emit(progress, RepairPhase::Done, 0, 0, "onarım tamam");
    Ok(RepairReport {
        verified_files,
        damaged_slices: damaged.len() as u32,
        repaired_slices: repaired.len() as u32,
        overlay_dir: Some(overlay_dir.to_path_buf()),
    })
}

enum RepairPassFailure {
    NewDamage(Vec<u64>),
    Cancelled,
    Io(io::Error),
}

/// Onarım turu: sağlam dilimleri okuyup akümülatörleri besler. "Sağlam"
/// sanılan dilim okunamazsa [`RepairPassFailure::NewDamage`] ile döner.
async fn run_repair_pass<F: RepairFetcher + 'static>(
    fetcher: &Arc<F>,
    set: &Par2Set,
    plan: &par2::RepairPlan,
    progress: &RepairProgressFn,
    done_bytes: &AtomicU64,
    total_bytes: u64,
    cancellation: &Option<watch::Receiver<bool>>,
) -> Result<Vec<(u64, Vec<u8>)>, RepairPassFailure> {
    emit(
        progress,
        RepairPhase::Repairing,
        0,
        total_bytes,
        "sağlam dilimler okunarak onarım hesaplanıyor",
    );
    done_bytes.store(0, Ordering::SeqCst);
    let map = set.global_slice_map();
    let mut accumulators = par2::RepairAccumulators::new(plan, set.slice_size);
    let mut newly_damaged = Vec::new();

    // Sütun sırası bağımsız olduğundan dilimler eşzamanlı okunur; uygulama
    // tamamlanma sırasında yapılır (XOR biriktirme sıradan bağımsızdır).
    let mut tasks = tokio::task::JoinSet::new();
    let mut pending = plan.present_indices.iter().enumerate();
    loop {
        while tasks.len() < SLICE_CONCURRENCY {
            let Some((column, &global)) = pending.next() else {
                break;
            };
            let (file, first) = file_of(&map, set, global);
            let name = file.name.clone();
            let range = slice_range(set, file, first, global);
            let fetcher = Arc::clone(fetcher);
            tasks.spawn(async move {
                (column, global, fetcher.read_range(&name, range).await)
            });
        }
        let joined = tokio::select! {
            result = tasks.join_next() => result,
            _ = async {
                if let Some(mut c) = cancellation.clone() {
                    wait_for_cancellation(&mut c).await;
                } else {
                    std::future::pending::<()>().await;
                }
            } => {
                tasks.abort_all();
                while tasks.join_next().await.is_some() {}
                return Err(RepairPassFailure::Cancelled);
            }
        };
        let Some(joined) = joined else {
            break;
        };
        let (column, global, result) = joined.map_err(|error| {
            RepairPassFailure::Io(io::Error::other(format!("dilim görevi düştü: {error}")))
        })?;
        match result {
            Ok(data) => {
                let padded = pad_to_slice(set, data);
                accumulators.add_present(plan, column, &padded);
                emit(
                    progress,
                    RepairPhase::Repairing,
                    done_bytes.fetch_add(padded.len() as u64, Ordering::SeqCst)
                        + padded.len() as u64,
                    total_bytes,
                    "onarım hesaplanıyor",
                );
            }
            Err(_) => newly_damaged.push(global),
        }
    }
    if !newly_damaged.is_empty() {
        return Err(RepairPassFailure::NewDamage(newly_damaged));
    }
    accumulators
        .finish(set, plan)
        .map_err(|error| RepairPassFailure::Io(io::Error::other(error.to_string())))
}

/// Dosyanın dilimlerini eşzamanlı okuyup sağlık durumlarını döndürür.
async fn verify_file<F: RepairFetcher + 'static>(
    fetcher: &Arc<F>,
    set: &Par2Set,
    file: &FileDesc,
    progress: &RepairProgressFn,
    total_bytes: u64,
    done_bytes: &AtomicU64,
    cancellation: &Option<watch::Receiver<bool>>,
) -> Result<Vec<SliceHealth>, RepairError> {
    let slice_count = set.file_slice_count(file);
    if !fetcher.has_file(&file.name) {
        // Dosya NZB'de hiç yok: tüm dilimler Missing, okuma yapılmaz.
        done_bytes.fetch_add(file.length, Ordering::SeqCst);
        return Ok(vec![SliceHealth::Missing; slice_count as usize]);
    }

    let mut health = vec![SliceHealth::Missing; slice_count as usize];
    let mut tasks = tokio::task::JoinSet::new();
    let mut pending = 0u64;
    while pending < slice_count || !tasks.is_empty() {
        while pending < slice_count && tasks.len() < SLICE_CONCURRENCY {
            let index = pending;
            pending += 1;
            let name = file.name.clone();
            let range = slice_range(set, file, 0, index);
            let checksum = set.slice_checksum(file, index);
            let fetcher = Arc::clone(fetcher);
            tasks.spawn(async move {
                let result = fetcher.read_range(&name, range).await;
                (index, result, checksum)
            });
        }
        let joined = tokio::select! {
            result = tasks.join_next() => result,
            _ = async {
                if let Some(mut c) = cancellation.clone() {
                    wait_for_cancellation(&mut c).await;
                } else {
                    std::future::pending::<()>().await;
                }
            } => {
                tasks.abort_all();
                while tasks.join_next().await.is_some() {}
                return Err(RepairError::Cancelled);
            }
        };
        let Some(joined) = joined else {
            break;
        };
        let (index, result, checksum) = joined
            .map_err(|error| RepairError::Io(io::Error::other(format!("doğrulama düştü: {error}"))))?;
        health[index as usize] = match result {
            Ok(data) => {
                let padded = pad_to_slice(set, data);
                match checksum {
                    Some(sum)
                        if md5::compute(&padded).0 == sum.md5
                            && crc32fast::hash(&padded) == sum.crc32 =>
                    {
                        SliceHealth::Ok
                    }
                    _ => SliceHealth::Damaged,
                }
            }
            Err(_) => SliceHealth::Damaged,
        };
        emit(
            progress,
            RepairPhase::Verifying,
            done_bytes.fetch_add(set.slice_size, Ordering::SeqCst) + set.slice_size,
            total_bytes,
            "dilimler doğrulanıyor",
        );
    }
    Ok(health)
}

/// Global dilim indeksinin dosyasını ve dosya-içi ilk dilimini döndürür.
fn file_of<'a>(
    map: &'a [(usize, u64, u64)],
    set: &'a Par2Set,
    global: u64,
) -> (&'a FileDesc, u64) {
    let (index, first, _) = map
        .iter()
        .find(|(_, first, count)| global >= *first && global < first + count)
        .expect("global dilim haritada var");
    (&set.files[*index], *first)
}

/// Dilimin dosya-içi bayt aralığı (son dilim kısa olur).
fn slice_range(set: &Par2Set, file: &FileDesc, first: u64, global: u64) -> Range<u64> {
    let index = global - first;
    let start = index * set.slice_size;
    let end = (start + set.slice_size).min(file.length);
    start..end
}

/// Okunan veriyi dilim boyuna sıfır dolguyla tamamlar.
fn pad_to_slice(set: &Par2Set, data: Vec<u8>) -> Vec<u8> {
    let slice_size = set.slice_size as usize;
    if data.len() == slice_size {
        return data;
    }
    let mut padded = vec![0u8; slice_size];
    let real = data.len().min(slice_size);
    padded[..real].copy_from_slice(&data[..real]);
    padded
}

fn ensure_active(cancellation: &Option<watch::Receiver<bool>>) -> Result<(), RepairError> {
    match cancellation {
        Some(receiver) if cancellation_requested(receiver) => Err(RepairError::Cancelled),
        _ => Ok(()),
    }
}

fn emit(
    progress: &RepairProgressFn,
    phase: RepairPhase,
    completed_bytes: u64,
    total_bytes: u64,
    detail: &str,
) {
    progress(RepairProgress {
        phase,
        completed_bytes,
        total_bytes,
        detail: detail.to_string(),
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/par2");

    /// Bellek içi sahte kaynak: gerçek flatdata dosyaları + yapay hasar.
    struct MockFetcher {
        files: HashMap<String, Vec<u8>>,
        par2: HashMap<String, Vec<u8>>,
        /// (dosya, dilim) -> okuma hatası üret.
        missing: std::collections::HashSet<(String, u64)>,
        /// (dosya, dilim) -> çöp veri döndür (MD5 uyuşmazlığı).
        corrupt: std::collections::HashSet<(String, u64)>,
        slice_size: u64,
    }

    impl MockFetcher {
        fn new() -> Self {
            let mut files = HashMap::new();
            let mut par2 = HashMap::new();
            for index in 0..10 {
                files.insert(
                    format!("test-{index}.data"),
                    std::fs::read(format!("{FIXTURE_DIR}/test-{index}.data")).unwrap(),
                );
            }
            par2.insert(
                "testdata.par2".to_string(),
                std::fs::read(format!("{FIXTURE_DIR}/testdata.par2")).unwrap(),
            );
            for name in [
                "testdata.vol00+01.par2",
                "testdata.vol01+02.par2",
                "testdata.vol03+04.par2",
                "testdata.vol07+08.par2",
                "testdata.vol15+16.par2",
                "testdata.vol31+29.par2",
            ] {
                par2.insert(
                    name.to_string(),
                    std::fs::read(format!("{FIXTURE_DIR}/{name}")).unwrap(),
                );
            }
            Self {
                files,
                par2,
                missing: Default::default(),
                corrupt: Default::default(),
                slice_size: 5376,
            }
        }

        fn par2_names() -> Vec<String> {
            let mut names = vec!["testdata.par2".to_string()];
            names.extend(
                [
                    "testdata.vol00+01.par2",
                    "testdata.vol01+02.par2",
                    "testdata.vol03+04.par2",
                    "testdata.vol07+08.par2",
                    "testdata.vol15+16.par2",
                    "testdata.vol31+29.par2",
                ]
                .into_iter()
                .map(str::to_string),
            );
            names
        }
    }

    impl RepairFetcher for MockFetcher {
        fn has_file(&self, name: &str) -> bool {
            self.files.contains_key(name)
        }

        async fn read_range(&self, name: &str, range: Range<u64>) -> io::Result<Vec<u8>> {
            let data = self
                .files
                .get(name)
                .ok_or_else(|| io::Error::other("dosya yok"))?;
            let first_slice = range.start / self.slice_size;
            let last_slice = (range.end - 1) / self.slice_size;
            for index in first_slice..=last_slice {
                if self.missing.contains(&(name.to_string(), index)) {
                    return Err(io::Error::other("segment sunucuda yok"));
                }
            }
            let mut out = data[range.start as usize..range.end as usize].to_vec();
            for index in first_slice..=last_slice {
                if self.corrupt.contains(&(name.to_string(), index)) {
                    // Dilimin bu aralıkla kesişen kısmını boz.
                    let slice_start = index * self.slice_size;
                    let from = range.start.max(slice_start);
                    let to = range.end.min(slice_start + self.slice_size);
                    for offset in from..to {
                        out[(offset - range.start) as usize] ^= 0xA5;
                    }
                }
            }
            Ok(out)
        }

        async fn read_par2(&self, name: &str) -> io::Result<Vec<u8>> {
            self.par2
                .get(name)
                .cloned()
                .ok_or_else(|| io::Error::other("par2 yok"))
        }
    }

    fn overlay_dir(tag: &str) -> PathBuf {
        std::env::temp_dir().join(format!("zanzibarr-repair-test-{tag}"))
    }

    fn report_progress() -> (Box<RepairProgressFn>, Arc<AtomicU64>) {
        let calls = Arc::new(AtomicU64::new(0));
        let counter = Arc::clone(&calls);
        let progress: Box<RepairProgressFn> = Box::new(move |_| {
            counter.fetch_add(1, Ordering::SeqCst);
        });
        (progress, calls)
    }

    #[tokio::test]
    async fn temiz_set_onarim_gerektirmez() {
        let fetcher = Arc::new(MockFetcher::new());
        let (progress, _) = report_progress();
        let dir = overlay_dir("temiz");
        let report = repair_release(&fetcher, &MockFetcher::par2_names(), &dir, &*progress, None)
            .await
            .unwrap();
        assert_eq!(report.damaged_slices, 0);
        assert_eq!(report.overlay_dir, None);
        assert_eq!(report.verified_files, 10);
    }

    #[tokio::test]
    async fn bozuk_ve_eksik_dilimler_uctan_uca_onarilir() {
        let mut fetcher = MockFetcher::new();
        // test-0: 2 dilim bozuk, test-1: 1 dilim eksik.
        fetcher.corrupt.insert(("test-0.data".to_string(), 2));
        fetcher.corrupt.insert(("test-0.data".to_string(), 7));
        fetcher.missing.insert(("test-1.data".to_string(), 5));
        let fetcher = Arc::new(fetcher);
        let (progress, progress_calls) = report_progress();
        let dir = overlay_dir("onarim");
        let _ = std::fs::remove_dir_all(&dir);

        let report = repair_release(&fetcher, &MockFetcher::par2_names(), &dir, &*progress, None)
            .await
            .unwrap();
        assert_eq!(report.damaged_slices, 3);
        assert_eq!(report.repaired_slices, 3);
        assert!(progress_calls.load(Ordering::SeqCst) > 10);

        // Katman diskten yüklenip orijinal baytlar doğrulanır.
        let overlay = RepairOverlay::load(&dir).unwrap().expect("katman yazıldı");
        let original0 = std::fs::read(format!("{FIXTURE_DIR}/test-0.data")).unwrap();
        let file0 = overlay.for_file("test-0.data").expect("test-0 katmanı");
        let slice2 = file0.slice_covering(2 * 5376).expect("dilim 2");
        assert_eq!(
            &slice2.1[..],
            &original0[(2 * 5376) as usize..(3 * 5376) as usize]
        );

        let original1 = std::fs::read(format!("{FIXTURE_DIR}/test-1.data")).unwrap();
        let file1 = overlay.for_file("test-1.data").expect("test-1 katmanı");
        let slice5 = file1.slice_covering(5 * 5376).expect("dilim 5");
        assert_eq!(
            &slice5.1[..],
            &original1[(5 * 5376) as usize..(6 * 5376) as usize]
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn eksik_dosya_onarilir() {
        let mut fetcher = MockFetcher::new();
        fetcher.files.remove("test-2.data"); // 17 dilim; 60 kurtarma yeterli
        let fetcher = Arc::new(fetcher);
        let (progress, _) = report_progress();
        let dir = overlay_dir("eksik-dosya");
        let _ = std::fs::remove_dir_all(&dir);

        let report = repair_release(&fetcher, &MockFetcher::par2_names(), &dir, &*progress, None)
            .await
            .unwrap();
        assert_eq!(report.damaged_slices, 17);

        let overlay = RepairOverlay::load(&dir).unwrap().unwrap();
        let original = std::fs::read(format!("{FIXTURE_DIR}/test-2.data")).unwrap();
        let file = overlay.for_file("test-2.data").unwrap();
        let mut rebuilt = Vec::new();
        for index in 0..17u64 {
            rebuilt.extend_from_slice(file.slices.get(&index).expect("dilim").as_slice());
        }
        rebuilt.truncate(original.len());
        assert_eq!(rebuilt, original);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn yetersiz_kurtarma_acik_hatayla_doner() {
        let mut fetcher = MockFetcher::new();
        // 60 kurtarma dilimini aşan hasar: 13 + 25 + 27 = 65 dilim eksik.
        fetcher.files.remove("test-0.data");
        fetcher.files.remove("test-6.data");
        fetcher.files.remove("test-3.data");
        let fetcher = Arc::new(fetcher);
        let (progress, _) = report_progress();
        let dir = overlay_dir("yetersiz");
        let result =
            repair_release(&fetcher, &MockFetcher::par2_names(), &dir, &progress, None).await;
        assert!(matches!(
            result,
            Err(RepairError::Par2(Par2Error::NotEnoughRecovery { .. }))
        ));
    }

    #[tokio::test]
    async fn iptal_dogrulama_turunda_durdurur() {
        let fetcher = Arc::new(MockFetcher::new());
        let (progress, _) = report_progress();
        let dir = overlay_dir("iptal");
        let (cancel, cancellation) = watch::channel(true); // baştan iptalli
        let result = repair_release(
            &fetcher,
            &MockFetcher::par2_names(),
            &dir,
            &*progress,
            Some(cancellation),
        )
        .await;
        assert!(matches!(result, Err(RepairError::Cancelled)));
        drop(cancel);
    }

    #[test]
    fn katman_kaydet_yukle_eslestirme() {
        let dir = overlay_dir("roundtrip");
        let _ = std::fs::remove_dir_all(&dir);
        let mut overlay = RepairOverlay::default();
        overlay.insert(
            "Movie.Part01.rar",
            FileOverlay {
                file_len: 10_000,
                slice_size: 1000,
                slices: BTreeMap::from([
                    (2u64, Arc::new(vec![0xAA; 1000])),
                    (5u64, Arc::new(vec![0xBB; 1000])),
                ]),
            },
        );
        overlay.save(&dir).unwrap();
        let loaded = RepairOverlay::load(&dir).unwrap().expect("katman var");
        let file = loaded.for_file("movie.part01.rar").expect("küçük harf eşleşme");
        assert_eq!(file.file_len, 10_000);
        assert_eq!(file.slices.len(), 2);
        assert_eq!(file.slices[&5].as_slice(), vec![0xBB; 1000].as_slice());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn katman_dilim_kesistirme() {
        let overlay = FileOverlay {
            file_len: 3000,
            slice_size: 1000,
            slices: BTreeMap::from([(1u64, Arc::new(vec![0xCC; 1000]))]),
        };
        assert!(overlay.slice_covering(0).is_none());
        let (index, _) = overlay.slice_covering(1500).expect("dilim 1 kapsar");
        assert_eq!(index, 1);
        assert_eq!(overlay.next_slice_start(0), 1000);
        assert_eq!(overlay.next_slice_start(1500), 3000);
    }
}
