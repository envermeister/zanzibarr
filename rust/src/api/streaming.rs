//! Dart'a açılan streaming API'si (flutter_rust_bridge).
//!
//! Dart, güvenli depodan okuduğu sağlayıcı bilgilerini ve bir NZB dosya
//! yolunu verir; Rust bir localhost HTTP Range server ayağa kaldırıp
//! media_kit'in açacağı URL'i döndürür. Ağır iş (NNTP, yEnc, byte-range)
//! tümüyle bu tarafta kalır.
//!
//! Kimlik bilgileri yalnızca çağrı parametresi olarak gelir; Rust bunları
//! diske yazmaz, loglamaz.

use std::io::Read;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use once_cell::sync::Lazy;
use tokio::runtime::Runtime;
use tokio::sync::{oneshot, watch};
use tokio::task::JoinHandle;

use crate::engine::nntp::{ProviderConfig, TlsNntpConnector};
use crate::engine::nntp_source::NntpByteSource;
use crate::engine::nzb::{self, NzbContentError, NzbFile};
use crate::engine::rar::RarEntrySource;
use crate::engine::server::{self, RangeSource};
use crate::engine::sevenzip::SevenZipEntrySource;

/// Tüm ağ/stream işleri bu global çok-iş-parçacıklı runtime'da yürür.
/// Server görevleri, başlatan çağrı bitse de burada yaşamaya devam eder.
static RUNTIME: Lazy<Runtime> = Lazy::new(|| Runtime::new().expect("tokio runtime kurulamadı"));

/// Uygulama şu anda tek oynatıcı oturumu çalıştırır. Önceki localhost server
/// kaydedilmeden bırakılırsa taşıdığı NNTP havuzu ve boşta TLS bağlantıları
/// sonsuza dek açık kalır. Aktif görevi kimliğiyle saklayarak hem yeni stream
/// öncesinde hem de Flutter ekranı kapanırken deterministik olarak durdururuz.
struct ActiveStream {
    session_id: u64,
    cancel: watch::Sender<bool>,
    task: JoinHandle<()>,
    ready: Option<oneshot::Receiver<Result<StreamInfo, String>>>,
}

static ACTIVE_STREAM: Lazy<Mutex<Option<ActiveStream>>> = Lazy::new(|| Mutex::new(None));
static NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);
const MAX_NZB_FILE_BYTES: usize = 64 * 1024 * 1024;
const NZB_READ_CHUNK_BYTES: usize = 64 * 1024;

/// Dart'tan gelen sağlayıcı yapılandırması.
pub struct ProviderConfigDto {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub max_connections: u32,
}

impl From<ProviderConfigDto> for ProviderConfig {
    fn from(dto: ProviderConfigDto) -> Self {
        ProviderConfig {
            host: dto.host,
            port: dto.port,
            username: dto.username,
            password: dto.password,
            max_connections: dto.max_connections.max(1) as usize,
        }
    }
}

/// Başlatılan stream'in oynatıcıya verilecek bilgileri.
pub struct StreamInfo {
    /// Yalnız bu localhost server oturumunu durdurmak için kullanılan kimlik.
    pub session_id: u64,
    /// media_kit'in açacağı localhost URL'i.
    pub url: String,
    /// Çözülmüş dosya boyutu (bayt).
    pub size: u64,
    pub filename: String,
    pub segment_count: u32,
}

#[cfg(test)]
fn take_active_stream(session_id: Option<u64>) -> Option<ActiveStream> {
    let mut active = ACTIVE_STREAM.lock().expect("aktif stream kilidi");
    let matches = active
        .as_ref()
        .is_some_and(|stream| session_id.is_none_or(|expected| expected == stream.session_id));
    matches.then(|| active.take()).flatten()
}

fn cancel_active_stream(session_id: u64) -> bool {
    let active = ACTIVE_STREAM.lock().expect("aktif stream kilidi");
    let Some(stream) = active
        .as_ref()
        .filter(|stream| stream.session_id == session_id)
    else {
        return false;
    };
    let _ = stream.cancel.send(true);
    true
}

async fn terminate_stream(stream: ActiveStream) {
    let _ = stream.cancel.send(true);
    // Oturum görevi server'ın bütün HTTP child görevlerini kapatıp beklemeden
    // bitmez. Böylece yeni sağlayıcı havuzu eski TLS oturumları düşmeden
    // kurulmaz.
    let _ = stream.task.await;
}

fn cancellation_requested(cancellation: &watch::Receiver<bool>) -> bool {
    *cancellation.borrow()
}

async fn wait_for_cancellation(mut cancellation: watch::Receiver<bool>) {
    if cancellation_requested(&cancellation) {
        return;
    }
    loop {
        if cancellation.changed().await.is_err() || cancellation_requested(&cancellation) {
            return;
        }
    }
}

async fn wait_for_stream_ready(
    ready: oneshot::Receiver<Result<StreamInfo, String>>,
    cancellation: watch::Receiver<bool>,
) -> Result<StreamInfo, String> {
    tokio::select! {
        // Durdurma ile daha önce tamponlanmış başarı aynı anda hazırsa eski,
        // artık dinlemeyen localhost URL'sini kesinlikle döndürmeyiz.
        biased;
        _ = wait_for_cancellation(cancellation) => {
            Err("akış başlatma iptal edildi".into())
        }
        result = ready => {
            result.unwrap_or_else(|_| {
                Err("akış başlatma görevi beklenmedik biçimde sonlandı".into())
            })
        }
    }
}

fn next_session_id() -> u64 {
    loop {
        let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
        if id != 0 {
            return id;
        }
    }
}

enum StreamSource {
    Direct(NntpByteSource),
    SevenZip(SevenZipEntrySource),
    Rar(RarEntrySource),
}

impl StreamSource {
    fn filename(&self) -> &str {
        match self {
            Self::Direct(source) => source.filename(),
            Self::SevenZip(source) => source.filename(),
            Self::Rar(source) => source.filename(),
        }
    }

    fn segment_count(&self) -> usize {
        match self {
            Self::Direct(source) => source.segment_count(),
            Self::SevenZip(source) => source.segment_count(),
            Self::Rar(source) => source.segment_count(),
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
impl RangeSource for StreamSource {
    fn total_len(&self) -> u64 {
        match self {
            Self::Direct(source) => source.total_len(),
            Self::SevenZip(source) => source.total_len(),
            Self::Rar(source) => source.total_len(),
        }
    }

    fn content_type(&self) -> &str {
        match self {
            Self::Direct(source) => source.content_type(),
            Self::SevenZip(source) => source.content_type(),
            Self::Rar(source) => source.content_type(),
        }
    }

    async fn write_range<W>(&self, range: std::ops::Range<u64>, out: &mut W) -> std::io::Result<()>
    where
        W: tokio::io::AsyncWrite + Unpin + Send,
    {
        match self {
            Self::Direct(source) => source.write_range(range, out).await,
            Self::SevenZip(source) => source.write_range(range, out).await,
            Self::Rar(source) => source.write_range(range, out).await,
        }
    }
}

enum StreamSelection {
    Direct(NzbFile),
    SevenZip {
        volumes: Vec<NzbFile>,
        password: Option<String>,
    },
    Rar {
        volumes: Vec<NzbFile>,
    },
}

async fn prepare_stream_source(
    config: ProviderConfigDto,
    selection: StreamSelection,
    cancellation: watch::Receiver<bool>,
) -> Result<StreamSource, String> {
    let pool = TlsNntpConnector::new(config.into()).into_pool();
    match selection {
        StreamSelection::Direct(file) => {
            let source = tokio::select! {
                biased;
                _ = wait_for_cancellation(cancellation) => {
                    return Err("akış başlatma iptal edildi".into());
                }
                result = NntpByteSource::new(pool, &file) => {
                    result.map_err(|error| error.to_string())?
                }
            };
            Ok(StreamSource::Direct(source))
        }
        StreamSelection::SevenZip { volumes, password } => Ok(StreamSource::SevenZip(
            SevenZipEntrySource::new_cancellable(pool, volumes, password, cancellation)
                .await
                .map_err(|error| error.to_string())?,
        )),
        StreamSelection::Rar { volumes } => Ok(StreamSource::Rar(
            RarEntrySource::new_cancellable(pool, volumes, cancellation)
                .await
                .map_err(|error| error.to_string())?,
        )),
    }
}

fn ensure_stream_not_cancelled(cancellation: &watch::Receiver<bool>) -> Result<(), String> {
    if cancellation_requested(cancellation) {
        Err("akış başlatma iptal edildi".into())
    } else {
        Ok(())
    }
}

fn read_nzb_bytes<R: Read>(
    reader: &mut R,
    cancellation: &watch::Receiver<bool>,
    max_bytes: usize,
) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    let mut chunk = [0u8; NZB_READ_CHUNK_BYTES];
    loop {
        ensure_stream_not_cancelled(cancellation)?;
        let count = reader
            .read(&mut chunk)
            .map_err(|error| format!("NZB okunamadı: {error}"))?;
        if count == 0 {
            break;
        }
        let new_len = bytes
            .len()
            .checked_add(count)
            .ok_or_else(|| "NZB boyutu taştı".to_string())?;
        if new_len > max_bytes {
            return Err(format!(
                "NZB dosyası güvenli boyut sınırını aşıyor ({max_bytes} bayt)"
            ));
        }
        bytes.extend_from_slice(&chunk[..count]);
    }
    ensure_stream_not_cancelled(cancellation)?;
    Ok(bytes)
}

fn load_stream_selection_blocking(
    nzb_path: String,
    cancellation: watch::Receiver<bool>,
) -> Result<StreamSelection, String> {
    ensure_stream_not_cancelled(&cancellation)?;
    let metadata =
        std::fs::metadata(&nzb_path).map_err(|error| format!("NZB okunamadı: {error}"))?;
    if !metadata.is_file() {
        return Err("Seçilen NZB yolu normal bir dosya değil".into());
    }
    if metadata.len() > MAX_NZB_FILE_BYTES as u64 {
        return Err(format!(
            "NZB dosyası güvenli boyut sınırını aşıyor ({MAX_NZB_FILE_BYTES} bayt)"
        ));
    }

    let mut file =
        std::fs::File::open(&nzb_path).map_err(|error| format!("NZB okunamadı: {error}"))?;
    let bytes = read_nzb_bytes(&mut file, &cancellation, MAX_NZB_FILE_BYTES)?;
    let xml = String::from_utf8(bytes).map_err(|_| "NZB geçerli UTF-8 metni değil".to_string())?;
    ensure_stream_not_cancelled(&cancellation)?;
    let parsed = nzb::parse_nzb(&xml).map_err(|error| error.to_string())?;
    ensure_stream_not_cancelled(&cancellation)?;
    select_stream(&parsed)
}

async fn load_stream_selection(
    nzb_path: String,
    cancellation: watch::Receiver<bool>,
) -> Result<StreamSelection, String> {
    ensure_stream_not_cancelled(&cancellation)?;
    let task_cancellation = cancellation.clone();
    let mut task = tokio::task::spawn_blocking(move || {
        load_stream_selection_blocking(nzb_path, task_cancellation)
    });

    tokio::select! {
        biased;
        _ = wait_for_cancellation(cancellation.clone()) => {
            // spawn_blocking zorla durdurulamaz. Parçalı okuyucu aynı watch
            // sinyalini görür; handle'ı sonuna kadar bekleyerek detached dosya
            // okuyucusu/parser bırakmayız.
            match task.await {
                Ok(_) => Err("akış başlatma iptal edildi".into()),
                Err(error) => Err(format!("NZB hazırlama görevi tamamlanamadı: {error}")),
            }
        }
        result = &mut task => {
            result
                .map_err(|error| format!("NZB hazırlama görevi tamamlanamadı: {error}"))?
        }
    }
}

async fn run_stream_session(
    session_id: u64,
    config: ProviderConfigDto,
    nzb_path: String,
    cancellation: watch::Receiver<bool>,
    ready: oneshot::Sender<Result<StreamInfo, String>>,
    previous: Option<ActiveStream>,
) {
    // Oturumlar zincir halinde kapanır: yeni ağ işi, önceki server ve onun tüm
    // HTTP/NNTP görevleri gerçekten düştükten sonra başlayabilir.
    if let Some(previous) = previous {
        terminate_stream(previous).await;
    }

    if cancellation_requested(&cancellation) {
        let _ = ready.send(Err("akış başlatma iptal edildi".into()));
        return;
    }

    // Dosya okuma/parse oturum kurulduktan sonra yapılır. Eski bir begin
    // çağrısı yavaş kalsa bile daha yeni oturum onu iptal eder ve bitmesini
    // bekler; sonuçların sırası tersine dönemez.
    let selection = match load_stream_selection(nzb_path, cancellation.clone()).await {
        Ok(selection) if !cancellation_requested(&cancellation) => selection,
        Ok(_) => {
            let _ = ready.send(Err("akış başlatma iptal edildi".into()));
            return;
        }
        Err(error) => {
            let _ = ready.send(Err(error));
            return;
        }
    };

    let source = match prepare_stream_source(config, selection, cancellation.clone()).await {
        Ok(source) => source,
        Err(error) => {
            let _ = ready.send(Err(error));
            return;
        }
    };

    if cancellation_requested(&cancellation) {
        let _ = ready.send(Err("akış başlatma iptal edildi".into()));
        return;
    }

    let size = source.total_len();
    let filename = source.filename().to_string();
    let segment_count = source.segment_count().min(u32::MAX as usize) as u32;
    let listener = match server::bind_local(0).await {
        Ok(listener) => listener,
        Err(error) => {
            let _ = ready.send(Err(format!("port bağlanamadı: {error}")));
            return;
        }
    };
    let port = match listener.local_addr() {
        Ok(address) => address.port(),
        Err(error) => {
            let _ = ready.send(Err(error.to_string()));
            return;
        }
    };
    let encoded_name = url_encode_path(&filename);
    let info = StreamInfo {
        session_id,
        url: format!("http://127.0.0.1:{port}/{encoded_name}"),
        size,
        filename,
        segment_count,
    };

    if ready.send(Ok(info)).is_err() {
        return;
    }

    let _ = server::serve_until(
        listener,
        Arc::new(source),
        wait_for_cancellation(cancellation),
    )
    .await;
}

fn select_stream(parsed: &nzb::Nzb) -> Result<StreamSelection, String> {
    match parsed.select_playable_media() {
        Ok(file) => Ok(StreamSelection::Direct(file.clone())),
        Err(NzbContentError::NoPlayableMedia) => {
            // Önce 7z setleri; bulunamazsa RAR setleri. Her iki biçimde de en
            // büyük kodlu boyutlu set seçilir.
            let sets = parsed.split_7z_sets().map_err(|error| error.to_string())?;
            if let Some(set) = sets.into_iter().max_by_key(|set| {
                set.volumes.iter().fold(0u64, |total, volume| {
                    total.saturating_add(volume.file.encoded_bytes())
                })
            }) {
                return Ok(StreamSelection::SevenZip {
                    volumes: set
                        .volumes
                        .into_iter()
                        .map(|volume| volume.file.clone())
                        .collect(),
                    password: parsed.meta_value("password").map(str::to_owned),
                });
            }

            let sets = parsed.split_rar_sets().map_err(|error| error.to_string())?;
            let set = sets
                .into_iter()
                .max_by_key(|set| {
                    set.volumes.iter().fold(0u64, |total, volume| {
                        total.saturating_add(volume.file.encoded_bytes())
                    })
                })
                .ok_or_else(|| {
                    "NZB'de doğrudan video veya desteklenen split 7z/RAR STORE seti yok".to_string()
                })?;
            Ok(StreamSelection::Rar {
                volumes: set
                    .volumes
                    .into_iter()
                    .map(|volume| volume.file.clone())
                    .collect(),
            })
        }
        Err(error) => Err(error.to_string()),
    }
}

/// NZB'yi doğrular, iptal edilebilir bir hazırlama oturumu başlatır ve session
/// kimliğini hemen döndürür. Ağ/bootstrap sonucu [`await_stream`] ile alınır;
/// bu ayrım Flutter'ın uzun hazırlığı daha sonuç gelmeden durdurabilmesini
/// sağlar.
pub fn begin_stream(config: ProviderConfigDto, nzb_path: String) -> u64 {
    let session_id = next_session_id();
    let (cancel, cancellation) = watch::channel(false);
    let (ready, ready_result) = oneshot::channel();

    // Take + spawn + install tek kısa kritik bölgede yapılır. Eşzamanlı yeni
    // bir start çağrısı bu görevi "previous" olarak devralıp önce iptal eder;
    // ağ I/O'su sırasında hiçbir std::sync::Mutex tutulmaz.
    let mut active = ACTIVE_STREAM.lock().expect("aktif stream kilidi");
    let previous = active.take();
    let task = RUNTIME.spawn(run_stream_session(
        session_id,
        config,
        nzb_path,
        cancellation,
        ready,
        previous,
    ));
    *active = Some(ActiveStream {
        session_id,
        cancel,
        task,
        ready: Some(ready_result),
    });
    drop(active);

    session_id
}

/// [`begin_stream`] ile başlatılan oturumun localhost server bilgilerini
/// bekler. Session başka bir seçim veya ekran kapanışıyla iptal edilirse açık
/// hata döner; hiçbir global kilit ağ I/O'su boyunca tutulmaz.
pub fn await_stream(session_id: u64) -> Result<StreamInfo, String> {
    let (ready_result, cancellation) = {
        let mut active = ACTIVE_STREAM.lock().expect("aktif stream kilidi");
        let stream = active
            .as_mut()
            .filter(|stream| stream.session_id == session_id)
            .ok_or_else(|| "akış oturumu artık etkin değil".to_string())?;
        let ready = stream
            .ready
            .take()
            .ok_or_else(|| "akış oturumu sonucu zaten bekleniyor".to_string())?;
        (ready, stream.cancel.subscribe())
    };

    let result = RUNTIME.block_on(wait_for_stream_ready(ready_result, cancellation));

    // Kayıt yerinde kalır: eşzamanlı yeni bir begin çağrısı onu `previous`
    // olarak devralıp görev tamamen kapanana dek bekler. Önce kaydı kaldırmak,
    // eski TLS oturumları drain olurken yeni havuzun başlamasına yol açardı.
    if result.is_err() {
        cancel_active_stream(session_id);
    }
    result
}

/// Tek çağrılı Rust/CLI kolaylık yolu. Flutter, hazırlık sırasında iptal
/// edebilmek için doğrudan [`begin_stream`] + [`await_stream`] kullanır.
pub fn start_stream(config: ProviderConfigDto, nzb_path: String) -> Result<StreamInfo, String> {
    let session_id = begin_stream(config, nzb_path);
    await_stream(session_id)
}

/// Verilen oynatıcı oturumuna ait localhost server'ı ve tüm açık HTTP/NNTP
/// görevlerini durdurur. Kimlik artık aktif değilse yeni bir oturuma dokunmaz.
pub fn stop_stream(session_id: u64) -> bool {
    // Kaydı burada kaldırmayız. Görev watch sinyaliyle kendi graceful kapanış
    // yolunu tamamlar; yeni begin aynı kaydı devralıp task'ı await ederek eski
    // bağlantılar düşmeden yeni sağlayıcı oturumu açamaz.
    cancel_active_stream(session_id)
}

/// URL yol bileşeni için minimal yüzde-kodlama (boşluk ve URL-güvensiz
/// karakterler). Dosya adları genelde güvenlidir ama garantiye alırız.
fn url_encode_path(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    for byte in name.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(subject: &str, segments: u32, bytes: u64) -> NzbFile {
        NzbFile {
            poster: "poster".into(),
            date: None,
            subject: subject.into(),
            groups: vec![],
            segments: (1..=segments)
                .map(|number| nzb::NzbSegment {
                    number,
                    bytes,
                    message_id: format!("id-{number}"),
                })
                .collect(),
        }
    }

    #[test]
    fn url_encode_bosluk_ve_ozel_karakter() {
        assert_eq!(url_encode_path("film.mkv"), "film.mkv");
        assert_eq!(url_encode_path("a b.mkv"), "a%20b.mkv");
        assert_eq!(url_encode_path("x&y.mkv"), "x%26y.mkv");
    }

    #[test]
    fn dto_config_donusumu() {
        let dto = ProviderConfigDto {
            host: "h".into(),
            port: 563,
            username: "u".into(),
            password: "p".into(),
            max_connections: 0, // en az 1'e yükseltilmeli
        };
        let config: ProviderConfig = dto.into();
        assert_eq!(config.max_connections, 1);
        assert_eq!(config.port, 563);
    }

    #[test]
    fn stop_kimligi_yeni_veya_farkli_oturumu_almaz() {
        assert!(take_active_stream(None).is_none());

        let (cancel, cancellation) = watch::channel(false);
        let task = RUNTIME.spawn(wait_for_cancellation(cancellation));
        *ACTIVE_STREAM.lock().expect("aktif stream test kilidi") = Some(ActiveStream {
            session_id: 42,
            cancel,
            task,
            ready: None,
        });

        assert!(!cancel_active_stream(41));
        assert_eq!(
            ACTIVE_STREAM
                .lock()
                .expect("aktif stream test kilidi")
                .as_ref()
                .map(|stream| stream.session_id),
            Some(42)
        );
        assert!(cancel_active_stream(42));
        assert!(ACTIVE_STREAM
            .lock()
            .expect("aktif stream test kilidi")
            .is_some());

        let active = take_active_stream(Some(42)).expect("doğru session alınmalı");
        RUNTIME.block_on(terminate_stream(active));
        assert!(ACTIVE_STREAM
            .lock()
            .expect("aktif stream test kilidi")
            .is_none());
    }

    #[test]
    fn iptal_tamponlanmis_hazir_sonucundan_onceliklidir() {
        let (cancel, cancellation) = watch::channel(false);
        let (sender, ready) = oneshot::channel();
        assert!(sender
            .send(Ok(StreamInfo {
                session_id: 7,
                url: "http://127.0.0.1:1/movie.mkv".into(),
                size: 1,
                filename: "movie.mkv".into(),
                segment_count: 1,
            }))
            .is_ok());
        assert!(cancel.send(true).is_ok());

        let result = RUNTIME.block_on(wait_for_stream_ready(ready, cancellation));
        let Err(error) = result else {
            panic!("durdurulmuş oturum eski URL'yi döndürmemeli");
        };
        assert!(error.contains("iptal"));
    }

    #[test]
    fn nzb_okuyucu_boyut_sinirini_ve_iptali_uygular() {
        let (_cancel_guard, cancellation) = watch::channel(false);
        let mut oversized = std::io::Cursor::new(b"123456".as_slice());
        let error = read_nzb_bytes(&mut oversized, &cancellation, 5).unwrap_err();
        assert!(error.contains("boyut sınırını"));

        let (cancel, cancellation) = watch::channel(false);
        assert!(cancel.send(true).is_ok());
        let mut input = std::io::Cursor::new(b"<nzb/>".as_slice());
        let error = read_nzb_bytes(&mut input, &cancellation, 1024).unwrap_err();
        assert!(error.contains("iptal"));
    }

    #[test]
    fn dogrudan_medya_par2den_once_secilir() {
        let parsed = nzb::Nzb {
            meta: vec![],
            files: vec![
                file("\"recovery.vol01+02.par2\" yEnc (1/20)", 20, 1000),
                file("\"movie.mkv\" yEnc (1/3)", 3, 2000),
            ],
        };
        let selection = select_stream(&parsed).unwrap();
        assert!(matches!(selection, StreamSelection::Direct(_)));
    }

    #[test]
    fn split_7z_ciltleri_sayisal_sirayla_secilir() {
        let parsed = nzb::Nzb {
            meta: vec![("password".into(), "placeholder".into())],
            files: vec![
                file("\"archive.7z.002\" yEnc (1/1)", 1, 1000),
                file("\"archive.7z.001\" yEnc (1/1)", 1, 1000),
            ],
        };
        let selection = select_stream(&parsed).unwrap();
        let StreamSelection::SevenZip { volumes, password } = selection else {
            panic!("7z seçimi bekleniyordu");
        };
        assert_eq!(volumes[0].filename(), Some("archive.7z.001"));
        assert_eq!(volumes[1].filename(), Some("archive.7z.002"));
        assert!(password.is_some());
    }

    #[test]
    fn split_7z_set_boyutu_tasmada_panik_yerine_doyar() {
        let parsed = nzb::Nzb {
            meta: vec![],
            files: vec![
                file("\"large.7z.002\" yEnc (1/1)", 1, u64::MAX),
                file("\"small.7z.001\" yEnc (1/1)", 1, 1),
                file("\"large.7z.001\" yEnc (1/1)", 1, u64::MAX),
            ],
        };

        let StreamSelection::SevenZip { volumes, .. } = select_stream(&parsed).unwrap() else {
            panic!("7z seçimi bekleniyordu");
        };
        assert_eq!(volumes.len(), 2);
        assert_eq!(volumes[0].filename(), Some("large.7z.001"));
    }

    #[test]
    fn split_rar_ciltleri_sayisal_sirayla_secilir() {
        let parsed = nzb::Nzb {
            meta: vec![],
            files: vec![
                file("\"movie.part02.rar\" yEnc (1/1)", 1, 1000),
                file("\"movie.part01.rar\" yEnc (1/1)", 1, 1000),
            ],
        };
        let selection = select_stream(&parsed).unwrap();
        let StreamSelection::Rar { volumes } = selection else {
            panic!("RAR seçimi bekleniyordu");
        };
        assert_eq!(volumes[0].filename(), Some("movie.part01.rar"));
        assert_eq!(volumes[1].filename(), Some("movie.part02.rar"));
    }

    #[test]
    fn rar_setlerinin_en_buyugu_secilir() {
        let parsed = nzb::Nzb {
            meta: vec![],
            files: vec![
                file("\"small.part01.rar\" yEnc (1/1)", 1, 10),
                file("\"large.part01.rar\" yEnc (1/1)", 1, 9000),
                file("\"large.part02.rar\" yEnc (1/1)", 1, 9000),
            ],
        };
        let StreamSelection::Rar { volumes } = select_stream(&parsed).unwrap() else {
            panic!("RAR seçimi bekleniyordu");
        };
        assert_eq!(volumes.len(), 2);
        assert_eq!(volumes[0].filename(), Some("large.part01.rar"));
    }

    #[test]
    fn yedi_z_ve_rar_birlikteyse_once_7z_secilir() {
        let parsed = nzb::Nzb {
            meta: vec![],
            files: vec![
                file("\"movie.part01.rar\" yEnc (1/1)", 1, 9000),
                file("\"archive.7z.001\" yEnc (1/1)", 1, 10),
            ],
        };
        assert!(matches!(
            select_stream(&parsed).unwrap(),
            StreamSelection::SevenZip { .. }
        ));
    }
}
