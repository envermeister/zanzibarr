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

use crate::engine::archive::{sniff_archive_kind, ArchiveKind};
use crate::engine::nntp::{NntpPool, ProviderConfig, TlsNntpConnector};
use crate::engine::nntp_source::{
    read_body_with_timeout, NntpByteSource, BODY_READ_TIMEOUT, DEFAULT_PREFETCH_DEPTH,
};
use crate::engine::nzb::{self, NzbContentError, NzbFile};
use crate::engine::rar::{self, RarEntrySource, RarError};
use crate::engine::rarcompressed::CompressedRarEntrySource;
use crate::engine::server::{self, RangeSource};
use crate::engine::sevenzip::SevenZipEntrySource;
use crate::engine::yenc;

/// Tüm ağ/stream işleri bu global çok-iş-parçacıklı runtime'da yürür.
/// Server görevleri, başlatan çağrı bitse de burada yaşamaya devam eder.
pub(crate) static RUNTIME: Lazy<Runtime> =
    Lazy::new(|| Runtime::new().expect("could not create tokio runtime"));

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
    /// Cast cihazının (Chromecast/AirPlay) LAN üzerinden vuracağı token'lı URL.
    /// LAN listener'ı kurulamadıysa (sandbox, ağ yok) boş string — cast
    /// özelliği o oturumda kullanılamaz.
    pub cast_url: String,
    /// Çözülmüş dosya boyutu (bayt).
    pub size: u64,
    pub filename: String,
    pub segment_count: u32,
    /// Sıkıştırılmış arşiv (LZMA/LZMA2) ardışıl çözümle sunuluyorsa true;
    /// açılış ve uzak seek'ler STORE'a göre belirgin yavaştır.
    pub compressed: bool,
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
            Err("stream startup cancelled".into())
        }
        result = ready => {
            result.unwrap_or_else(|_| {
                Err("stream startup task ended unexpectedly".into())
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
    RarCompressed(CompressedRarEntrySource),
}

impl StreamSource {
    fn filename(&self) -> &str {
        match self {
            Self::Direct(source) => source.filename(),
            Self::SevenZip(source) => source.filename(),
            Self::Rar(source) => source.filename(),
            Self::RarCompressed(source) => source.filename(),
        }
    }

    fn segment_count(&self) -> usize {
        match self {
            Self::Direct(source) => source.segment_count(),
            Self::SevenZip(source) => source.segment_count(),
            Self::Rar(source) => source.segment_count(),
            Self::RarCompressed(source) => source.segment_count(),
        }
    }

    /// Kaynak ardışıl çözüm (sıkıştırılmış arşiv) gerektiriyorsa true.
    fn is_compressed(&self) -> bool {
        match self {
            Self::Direct(_) => false,
            Self::SevenZip(source) => source.is_compressed(),
            Self::Rar(_) => false,
            // Sıkıştırılmış RAR her zaman ardışıl çözüm yolundadır.
            Self::RarCompressed(_) => true,
        }
    }

    /// PAR2 onarım katmanını (varsa) kaynağa kurar. Katman diskte yoksa veya
    /// dosya adı eşleşmezse kaynak değişmeden kalır.
    fn install_overlay(&self, overlay: &crate::engine::repair::RepairOverlay) {
        match self {
            Self::Direct(source) => {
                if let Some(file_overlay) = overlay.for_file(source.filename()) {
                    source.set_overlay(std::sync::Arc::new(file_overlay.clone()));
                }
            }
            Self::SevenZip(source) => source.set_overlays(overlay),
            Self::Rar(source) => source.set_overlays(overlay),
            // PAR2 onarımı sıkıştırılmış yolda henüz bağlı değil; ciltler
            // spool sırasında doğrudan NNTP'den okunur.
            Self::RarCompressed(_) => {}
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
            Self::RarCompressed(source) => source.total_len(),
        }
    }

    fn content_type(&self) -> &str {
        match self {
            Self::Direct(source) => source.content_type(),
            Self::SevenZip(source) => source.content_type(),
            Self::Rar(source) => source.content_type(),
            Self::RarCompressed(source) => source.content_type(),
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
            Self::RarCompressed(source) => source.write_range(range, out).await,
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
        password: Option<String>,
    },
    /// Adından türü anlaşılamayan sayısal ekli obfuske set; gerçek biçim
    /// `prepare_stream_source` içinde ilk cildin içerik imzası koklanarak
    /// belirlenir (bkz. `probe_numbered_set`).
    Probe {
        base_name: String,
        volumes: Vec<NzbFile>,
        password: Option<String>,
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
                _ = wait_for_cancellation(cancellation.clone()) => {
                    return Err("stream startup cancelled".into());
                }
                result = NntpByteSource::with_options(
                    pool,
                    &file,
                    NntpByteSource::DEFAULT_CACHE_SEGMENTS,
                    DEFAULT_PREFETCH_DEPTH,
                    Some(cancellation),
                ) => {
                    result.map_err(|error| error.to_string())?
                }
            };
            Ok(StreamSource::Direct(source))
        }
        StreamSelection::SevenZip { volumes, password } => {
            build_sevenzip_source(pool, volumes, password, cancellation).await
        }
        StreamSelection::Rar { volumes, password } => {
            build_rar_source(pool, volumes, password, cancellation).await
        }
        StreamSelection::Probe {
            base_name,
            volumes,
            password,
        } => {
            let (kind, volumes, trace) =
                probe_numbered_set(&pool, &base_name, volumes, &cancellation).await?;
            match kind {
                // Kurulum hatasına koklama izini iliştir: obfuske setlerde
                // cihaz üzerindeki hata iletisi (ekran görüntüsü) tek canlı
                // teşhis kanalıdır; iz, sıralamanın hangi aşamayla
                // kurulduğunu söyler.
                ArchiveKind::Rar => build_rar_source(pool, volumes, password, cancellation)
                    .await
                    .map_err(|error| format!("{error} [{trace}]")),
                ArchiveKind::SevenZip => {
                    build_sevenzip_source(pool, volumes, password, cancellation).await
                }
            }
        }
    }
}

async fn build_sevenzip_source(
    pool: Arc<NntpPool<TlsNntpConnector>>,
    volumes: Vec<NzbFile>,
    password: Option<String>,
    cancellation: watch::Receiver<bool>,
) -> Result<StreamSource, String> {
    Ok(StreamSource::SevenZip(
        SevenZipEntrySource::new_cancellable(pool, volumes, password, cancellation)
            .await
            .map_err(|error| error.to_string())?,
    ))
}

async fn build_rar_source(
    pool: Arc<NntpPool<TlsNntpConnector>>,
    volumes: Vec<NzbFile>,
    password: Option<String>,
    cancellation: watch::Receiver<bool>,
) -> Result<StreamSource, String> {
    match RarEntrySource::new_cancellable(
        pool.clone(),
        volumes.clone(),
        password.clone(),
        cancellation.clone(),
    )
    .await
    {
        Ok(source) => Ok(StreamSource::Rar(source)),
        // STORE olmayan setler decode-ahead yoluna düşer: ciltler
        // geçici diske kopyalanır, libunrar hedef üyeyi büyüyen çıktı
        // dosyasına çözer, oynatıcı çıktıyı Range ile okur.
        Err(RarError::UnsupportedCompression) => Ok(StreamSource::RarCompressed(
            CompressedRarEntrySource::new_cancellable(pool, volumes, password, cancellation)
                .await
                .map_err(|error| error.to_string())?,
        )),
        Err(error) => Err(error.to_string()),
    }
}

/// Sayısal ekli obfuske setin gerçek arşiv biçimini içerik imzasından
/// belirler ve ciltleri arşiv sırasına dizer. Sıralama üç aşamalıdır:
///
/// 1. İlk cilt doğrulanmış ana ciltse sayısal sıralama kullanılır (ucuz yol,
///    poster'ların çoğu arşiv sırasıyla numaralar).
/// 2. Son cilt doğrulanmış ana ciltse set döndürülür (eski usul `.rNN`+`.rar`
///    adlandırmayı alfabetik numaralayan paylaşımlar).
/// 3. İki uç da çözülemezse tüm ciltlerin RAR5 ana başlığındaki **cilt
///    numarası** okunup küme numaraya göre dizilir — poster numaraları
///    karışık/kaydırmalı olduğunda ya da dosya başlıkları -hp ile şifreli
///    olduğunda (ana başlık açık kalır) bile yetkin sıralamayı verir.
///    Numaralar okunamazsa (RAR4) özgün sıralama korunur ve zincir
///    doğrulaması gerçek düzen hatasını raporlar.
///
/// Dikkat: RAR'da **her** cilt `Rar!` imzasını taşır; imza tek başına ana
/// cildi göstermez. Ana cilt doğrulaması ilk dosya başlığının `split_before`
/// bayrağına bakar (`rar::sniff_rar_volume_role`). 7z'de imza yalnız ilk
/// ciltte bulunduğundan ek doğrulama gerekmez.
async fn probe_numbered_set(
    pool: &Arc<NntpPool<TlsNntpConnector>>,
    base_name: &str,
    volumes: Vec<NzbFile>,
    cancellation: &watch::Receiver<bool>,
) -> Result<(ArchiveKind, Vec<NzbFile>, String), String> {
    /// Rol koklamasının kısa iz gösterimi: H=ana cilt, C=devam, ?=çözülemedi.
    fn role_mark(role: Option<bool>) -> &'static str {
        match role {
            Some(true) => "H",
            Some(false) => "C",
            None => "?",
        }
    }

    let head = fetch_first_segment(pool, &volumes[0], cancellation).await?;
    let head_kind = sniff_archive_kind(&head);
    match head_kind {
        Some(ArchiveKind::SevenZip) => {
            return Ok((ArchiveKind::SevenZip, volumes, "7z head-ok".into()));
        }
        // İlk cilt doğrulanmış ana ciltse sayısal sıralamaya güven (ucuz yol).
        Some(ArchiveKind::Rar) if rar::sniff_rar_volume_role(&head) == Some(true) => {
            return Ok((ArchiveKind::Rar, volumes, "rar h=H cheap".into()));
        }
        _ => {}
    }

    // İlk cilt ana cilt çıkmadı (devam cildi ya da rolü çözülemedi — -hp'de
    // dosya başlıkları şifrelidir). Son cilt doğrulanmış bir ana ciltse eski
    // usul (.rar sonda) sayılıp set döndürülür.
    let mut volumes = volumes;
    let last = volumes.pop().expect("numbered set has at least two volumes");
    let tail = fetch_first_segment(pool, &last, cancellation).await?;
    let tail_kind = sniff_archive_kind(&tail);
    let tail_is_archive_start = match tail_kind {
        Some(ArchiveKind::SevenZip) => true,
        Some(ArchiveKind::Rar) => rar::sniff_rar_volume_role(&tail) == Some(true),
        None => false,
    };
    if tail_is_archive_start {
        let kind = tail_kind.expect("tail kind just matched");
        let trace = match kind {
            ArchiveKind::SevenZip => "7z rotated".to_string(),
            ArchiveKind::Rar => "rar rotated h=C t=H".to_string(),
        };
        let mut rotated = Vec::with_capacity(volumes.len() + 1);
        rotated.push(last);
        rotated.extend(volumes);
        return Ok((kind, rotated, trace));
    }

    // İki ucun rolü de ana cildi göstermiyor: poster'ın numaralandırması
    // arşiv sırasıyla ilgisiz olabilir (karışık/kaydırmalı) ya da başlıklar
    // şifrelidir. RAR5 her cildin ana başlığına cilt numarasını yazar; orta
    // ciltlerin de ilk segmentlerini çekip kümeyi numaraya göre dizeriz.
    // Numaralar eksik ya da tekrarlıysa (RAR4, numarasız araçlar) içerikten
    // sıralama çözülemez — özgün sırayla devam edip zincir doğrulamasının
    // gerçek hatayı vermesine bırakılır.
    if head_kind == Some(ArchiveKind::Rar) {
        let head_role = rar::sniff_rar_volume_role(&head);
        let tail_role = rar::sniff_rar_volume_role(&tail);
        let mut all = Vec::with_capacity(volumes.len() + 1);
        all.extend(volumes);
        all.push(last);
        let mut numbers: Vec<Option<u64>> = vec![None; all.len()];
        numbers[0] = rar::sniff_rar_volume_number(&head);
        let last_index = all.len() - 1;
        numbers[last_index] = rar::sniff_rar_volume_number(&tail);
        let middle_heads =
            fetch_middle_first_segments(pool, &all[1..last_index], cancellation).await?;
        for (index, middle_head) in middle_heads.iter().enumerate() {
            numbers[index + 1] = rar::sniff_rar_volume_number(middle_head);
        }
        let found = numbers.iter().flatten().count();
        let trace_prefix = format!(
            "rar h={} t={} nums={found}/{}",
            role_mark(head_role),
            role_mark(tail_role),
            all.len()
        );
        if let Some((permutation, implied)) = volume_number_permutation(&numbers) {
            let min = numbers.iter().flatten().min().copied().unwrap_or(0);
            let max = numbers.iter().flatten().max().copied().unwrap_or(0);
            let mut slots: Vec<Option<NzbFile>> = all.into_iter().map(Some).collect();
            let ordered: Vec<NzbFile> = permutation
                .iter()
                .map(|&index| slots[index].take().expect("permutation indices are unique"))
                .collect();
            let first_name = ordered
                .first()
                .and_then(|file| file.filename().map(str::to_owned))
                .unwrap_or_else(|| "?".into());
            return Ok((
                ArchiveKind::Rar,
                ordered,
                format!(
                    "{trace_prefix} sorted {min}..{max} first={first_name}{}",
                    if implied { " (1 implied)" } else { "" }
                ),
            ));
        }
        return Ok((
            ArchiveKind::Rar,
            all,
            format!("{trace_prefix} unsortable, original order"),
        ));
    }

    Err(format!(
        "numbered volume set `{base_name}` is neither a RAR nor a 7z archive; unsupported obfuscated content"
    ))
}

/// Cilt numaralarından arşiv sırası permütasyonu üretir.
///
/// RAR5'te ilk cildin numara alanı atlanabilir (ima edilen 0). Tam olarak
/// bir cilt numarasızsa, bilinen numaralar kesintisiz tek aralığa
/// tamamlanacak şekilde o cilde numara ima edilir: tek iç boşluk varsa
/// boşluk, yoksa `min >= 1` ise başa (`min-1`, tipik olarak cilt 0), `min ==
/// 0` ise sona (`max+1`). Numarasız cilt birden çoksa, bilinen numaralar
/// tekrarlıysa ya da aralık birden çok eksik içeriyorsa `None` — çağıran
/// ad-tabanlı sıraya düşer. Başlangıç değeri (0/1) önemsizdir; yalnızca
/// göreli sıra kullanılır.
///
/// Dönüş: (permütasyon, numara_ima_edildi).
fn volume_number_permutation(numbers: &[Option<u64>]) -> Option<(Vec<usize>, bool)> {
    let count = numbers.len();
    if count < 2 {
        return None;
    }
    let mut indexed: Vec<(u64, usize)> = Vec::with_capacity(count);
    let mut unknown: Vec<usize> = Vec::new();
    for (index, number) in numbers.iter().enumerate() {
        match number {
            Some(number) => indexed.push((*number, index)),
            None => unknown.push(index),
        }
    }
    let mut known: Vec<u64> = indexed.iter().map(|(number, _)| *number).collect();
    known.sort_unstable();
    if known.windows(2).any(|pair| pair[0] == pair[1]) {
        return None;
    }
    let mut implied = false;
    match unknown.as_slice() {
        [] => {}
        [index] => {
            implied = true;
            indexed.push((implied_number(&known)?, *index));
        }
        _ => return None,
    }
    indexed.sort_by_key(|(number, _)| *number);
    Some((
        indexed.into_iter().map(|(_, index)| index).collect(),
        implied,
    ))
}

/// Tek numarasız cildin ima edilen numarası: bilinen numaralarda tek iç
/// boşluk varsa boşluk; numaralar kesintisizse ve en az 1'den başlıyorsa
/// başlangıcın biri (ima edilen ilk cilt), 0'dan başlıyorsa sonun biri
/// (ima edilen son cilt). Birden çok boşlukta ya da geniş boşlukta `None`.
fn implied_number(known: &[u64]) -> Option<u64> {
    let mut gap = None;
    for pair in known.windows(2) {
        match pair[1] - pair[0] {
            1 => {}
            2 if gap.is_none() => gap = Some(pair[0] + 1),
            _ => return None,
        }
    }
    if let Some(gap) = gap {
        return Some(gap);
    }
    let min = known.first().copied()?;
    let max = known.last().copied()?;
    if min >= 1 { Some(min - 1) } else { Some(max + 1) }
}

/// Orta ciltlerin ilk segmentlerini eşzamanlı çeker; dönüş `files` ile aynı
/// sıradadır. Havuz semaforu gerçek eşzamanlılığı sınırlar; görevler yalnızca
/// sıralamayı kurmak için başlık baytları taşır.
async fn fetch_middle_first_segments(
    pool: &Arc<NntpPool<TlsNntpConnector>>,
    files: &[NzbFile],
    cancellation: &watch::Receiver<bool>,
) -> Result<Vec<Vec<u8>>, String> {
    let mut set = tokio::task::JoinSet::new();
    for (index, file) in files.iter().enumerate() {
        let pool = Arc::clone(pool);
        let file = file.clone();
        let cancellation = cancellation.clone();
        set.spawn(
            async move { fetch_first_segment(&pool, &file, &cancellation).await.map(|head| (index, head)) },
        );
    }
    let mut indexed = Vec::with_capacity(files.len());
    while let Some(result) = set.join_next().await {
        indexed.push(result.map_err(|error| format!("probe task failed to complete: {error}"))??);
    }
    indexed.sort_by_key(|(index, _)| *index);
    Ok(indexed.into_iter().map(|(_, head)| head).collect())
}

/// Koklama için tek segment çekip yEnc çözer. Yalnızca ilk baytlar gerekse de
/// NNTP'nin aralık okuması yoktur; bir article'ın tamamı alınır (~1 MB).
async fn fetch_first_segment(
    pool: &Arc<NntpPool<TlsNntpConnector>>,
    file: &NzbFile,
    cancellation: &watch::Receiver<bool>,
) -> Result<Vec<u8>, String> {
    let segment = file.segments.first().ok_or_else(|| {
        format!(
            "`{}` has no segments",
            file.filename().unwrap_or("file with unknown name")
        )
    })?;
    let message_id = segment.message_id.clone();

    let work = async {
        let mut conn = pool.checkout().await.map_err(|error| error.to_string())?;
        let body = read_body_with_timeout(BODY_READ_TIMEOUT, conn.body_by_message_id(&message_id))
            .await
            .map_err(|error| error.to_string())?;
        // Durum satırı ve multiline sonlandırıcısı eksiksiz okundu; bağlantı
        // havuza dönebilir.
        conn.mark_reusable();
        drop(conn);
        yenc::decode(&body)
            .map(|part| part.data)
            .map_err(|error| error.to_string())
    };

    tokio::select! {
        biased;
        _ = wait_for_cancellation(cancellation.clone()) => {
            Err("stream startup cancelled".into())
        }
        result = work => result,
    }
}

fn ensure_stream_not_cancelled(cancellation: &watch::Receiver<bool>) -> Result<(), String> {
    if cancellation_requested(cancellation) {
        Err("stream startup cancelled".into())
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
            .map_err(|error| format!("could not read NZB: {error}"))?;
        if count == 0 {
            break;
        }
        let new_len = bytes
            .len()
            .checked_add(count)
            .ok_or_else(|| "NZB size overflow".to_string())?;
        if new_len > max_bytes {
            return Err(format!(
                "NZB file exceeds the safe size limit ({max_bytes} bytes)"
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
        std::fs::metadata(&nzb_path).map_err(|error| format!("could not read NZB: {error}"))?;
    if !metadata.is_file() {
        return Err("the selected NZB path is not a regular file".into());
    }
    if metadata.len() > MAX_NZB_FILE_BYTES as u64 {
        return Err(format!(
            "NZB file exceeds the safe size limit ({MAX_NZB_FILE_BYTES} bytes)"
        ));
    }

    let mut file =
        std::fs::File::open(&nzb_path).map_err(|error| format!("could not read NZB: {error}"))?;
    let bytes = read_nzb_bytes(&mut file, &cancellation, MAX_NZB_FILE_BYTES)?;
    let xml = String::from_utf8(bytes).map_err(|_| "NZB is not valid UTF-8 text".to_string())?;
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
                Ok(_) => Err("stream startup cancelled".into()),
                Err(error) => Err(format!("NZB prepare task failed to complete: {error}")),
            }
        }
        result = &mut task => {
            result
                .map_err(|error| format!("NZB prepare task failed to complete: {error}"))?
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
        let _ = ready.send(Err("stream startup cancelled".into()));
        return;
    }

    // Dosya okuma/parse oturum kurulduktan sonra yapılır. Eski bir begin
    // çağrısı yavaş kalsa bile daha yeni oturum onu iptal eder ve bitmesini
    // bekler; sonuçların sırası tersine dönemez.
    let selection = match load_stream_selection(nzb_path.clone(), cancellation.clone()).await {
        Ok(selection) if !cancellation_requested(&cancellation) => selection,
        Ok(_) => {
            let _ = ready.send(Err("stream startup cancelled".into()));
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

    // Önceki bir onarım oturumundan kalan katman varsa kur: hasarlı bölgeler
    // artık ağa çıkılmadan yerelden servis edilir.
    let overlay_dir = crate::engine::repair::RepairOverlay::dir_for_nzb(
        std::path::Path::new(nzb_path.as_str()),
    );
    match crate::engine::repair::RepairOverlay::load(&overlay_dir) {
        Ok(Some(overlay)) => source.install_overlay(&overlay),
        Ok(None) => {}
        Err(error) => {
            // Bozuk katman oynatmayı engellemez; ağ yolundan devam edilir.
            let _ = error;
        }
    }

    if cancellation_requested(&cancellation) {
        let _ = ready.send(Err("stream startup cancelled".into()));
        return;
    }

    let size = source.total_len();
    let filename = source.filename().to_string();
    let segment_count = source.segment_count().min(u32::MAX as usize) as u32;
    let compressed = source.is_compressed();
    let listener = match server::bind_local(0).await {
        Ok(listener) => listener,
        Err(error) => {
            let _ = ready.send(Err(format!("could not bind port: {error}")));
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

    // Cast paylaşımı: LAN listener'ı token'lı `/cast/<token>/` öneki ister;
    // kurulamazsa (sandbox, ağ yok) cast bu oturumda kapalı kalır, yerel
    // oynatma etkilenmez.
    let cast_token = generate_cast_token(session_id);
    let lan_listener = server::bind_lan(0).await.ok();
    let cast_url = match (&lan_listener, local_lan_ipv4()) {
        (Some(lan), Some(ip)) => match lan.local_addr() {
            Ok(address) => format!(
                "http://{ip}:{}/cast/{cast_token}/{encoded_name}",
                address.port()
            ),
            Err(_) => String::new(),
        },
        _ => String::new(),
    };

    let info = StreamInfo {
        session_id,
        url: format!("http://127.0.0.1:{port}/{encoded_name}"),
        cast_url,
        size,
        filename,
        segment_count,
        compressed,
    };

    if ready.send(Ok(info)).is_err() {
        return;
    }

    let source = Arc::new(source);
    match lan_listener {
        Some(lan) => {
            let prefix: Arc<str> = Arc::from(format!("/cast/{cast_token}/"));
            let _ = tokio::join!(
                server::serve_until(
                    listener,
                    Arc::clone(&source),
                    None,
                    wait_for_cancellation(cancellation.clone()),
                ),
                server::serve_until(
                    lan,
                    source,
                    Some(prefix),
                    wait_for_cancellation(cancellation),
                ),
            );
        }
        None => {
            let _ = server::serve_until(
                listener,
                source,
                None,
                wait_for_cancellation(cancellation),
            )
            .await;
        }
    }
}

/// Cast oturumu için 128-bit rastgele yol token'ı (hex). LAN tehdit modeli
/// için kriptografik RNG şart değil; zaman + pid + oturum kimliği karması
/// tahmin edilemezlik açısından yeterlidir.
fn generate_cast_token(session_id: u64) -> String {
    use sha2::Digest;
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let hash = sha2::Sha256::digest(format!(
        "zanzibarr-cast:{session_id}:{nanos}:{}",
        std::process::id()
    ));
    hash[..16].iter().map(|b| format!("{b:02x}")).collect()
}

/// Cihazın LAN IPv4 adresini bulur. UDP connect hilesi paket göndermez;
/// yalnızca yönlendirme tablosundan çıkış arayüzünü öğrenir.
fn local_lan_ipv4() -> Option<std::net::Ipv4Addr> {
    use std::net::UdpSocket;
    let socket = UdpSocket::bind(("0.0.0.0", 0)).ok()?;
    socket.connect(("8.8.8.8", 80)).ok()?;
    match socket.local_addr().ok()?.ip() {
        std::net::IpAddr::V4(v4) => Some(v4),
        std::net::IpAddr::V6(_) => None,
    }
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
            if let Some(set) = sets.into_iter().max_by_key(|set| {
                set.volumes.iter().fold(0u64, |total, volume| {
                    total.saturating_add(volume.file.encoded_bytes())
                })
            }) {
                return Ok(StreamSelection::Rar {
                    volumes: set
                        .volumes
                        .into_iter()
                        .map(|volume| volume.file.clone())
                        .collect(),
                    password: parsed.meta_value("password").map(str::to_owned),
                });
            }

            // Ad çözümü tamamen başarısız: gerçek uzantıları silinmiş obfuske
            // bir sayısal set olabilir. En büyük set seçilir; gerçek biçim,
            // ağ erişiminin kurulduğu prepare aşamasında içerik imzası
            // koklanarak belirlenir.
            let set = parsed
                .numbered_volume_sets()
                .into_iter()
                .max_by_key(|set| {
                    set.volumes.iter().fold(0u64, |total, volume| {
                        total.saturating_add(volume.file.encoded_bytes())
                    })
                })
                .ok_or_else(|| {
                    "no direct video or supported split 7z/RAR STORE set in the NZB".to_string()
                })?;
            Ok(StreamSelection::Probe {
                base_name: set.base_name,
                volumes: set
                    .volumes
                    .into_iter()
                    .map(|volume| volume.file.clone())
                    .collect(),
                password: parsed.meta_value("password").map(str::to_owned),
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
            .ok_or_else(|| "stream session is no longer active".to_string())?;
        let ready = stream
            .ready
            .take()
            .ok_or_else(|| "stream session result already expected".to_string())?;
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
    fn cilt_numarasi_permutasyonu_arsiv_sirasina_dizer() {
        // Poster numaraları karışık: NZB sırası cilt [2, 0, 1].
        let numbers = vec![Some(2), Some(0), Some(1)];
        assert_eq!(
            volume_number_permutation(&numbers),
            Some((vec![1, 2, 0], false))
        );

        // Zaten sıralı küme kimlik permütasyonu verir.
        let identity = vec![Some(10), Some(11), Some(12)];
        assert_eq!(
            volume_number_permutation(&identity),
            Some((vec![0, 1, 2], false))
        );

        // 1'den başlayan numaralandırma da geçerli (göreli sıra yeterli).
        let one_based = vec![Some(3), Some(1), Some(2)];
        assert_eq!(
            volume_number_permutation(&one_based),
            Some((vec![1, 2, 0], false))
        );
    }

    #[test]
    fn cilt_numarasi_tek_eksikte_ima_ile_doldurulur() {
        // İç boşluk: eksik cilt 1 numaraya ima edilir → [0,1,2].
        assert_eq!(
            volume_number_permutation(&[Some(0), None, Some(2)]),
            Some((vec![0, 1, 2], true))
        );
        // İma edilen ilk cilt (WinRAR cilt 0'a numara alanı yazmaz):
        // numarasız cilt başa düşer.
        assert_eq!(
            volume_number_permutation(&[None, Some(1), Some(2), Some(3)]),
            Some((vec![0, 1, 2, 3], true))
        );
        // İma edilen son cilt: numarasız cilt sona düşer.
        assert_eq!(
            volume_number_permutation(&[Some(0), Some(1), None]),
            Some((vec![0, 1, 2], true))
        );
        // Karışık sırada iç boşluk: 1 ve 3 biliniyor, boşluk 2.
        assert_eq!(
            volume_number_permutation(&[Some(1), Some(3), None]),
            Some((vec![0, 2, 1], true))
        );
    }

    #[test]
    fn cilt_numarasi_cozulemezse_permutasyon_yok() {
        // Birden çok numarasız cilt çözülemez.
        assert_eq!(volume_number_permutation(&[None, None, Some(0)]), None);
        // Tekrarlı numaralar reddedilir (tek eksikle bile).
        assert_eq!(volume_number_permutation(&[Some(1), Some(1)]), None);
        assert_eq!(volume_number_permutation(&[Some(1), Some(1), None]), None);
        // Birden çok eksik içeren aralık çözülemez.
        assert_eq!(volume_number_permutation(&[Some(0), Some(5), None]), None);
        assert_eq!(volume_number_permutation(&[Some(0)]), None);
        assert_eq!(volume_number_permutation(&[]), None);
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

        let active = take_active_stream(Some(42)).expect("expected the correct session");
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
                cast_url: String::new(),
                size: 1,
                filename: "movie.mkv".into(),
                segment_count: 1,
                compressed: false,
            }))
            .is_ok());
        assert!(cancel.send(true).is_ok());

        let result = RUNTIME.block_on(wait_for_stream_ready(ready, cancellation));
        let Err(error) = result else {
            panic!("stopped session must not return the old URL");
        };
        assert!(error.contains("cancel"));
    }

    #[test]
    fn nzb_okuyucu_boyut_sinirini_ve_iptali_uygular() {
        let (_cancel_guard, cancellation) = watch::channel(false);
        let mut oversized = std::io::Cursor::new(b"123456".as_slice());
        let error = read_nzb_bytes(&mut oversized, &cancellation, 5).unwrap_err();
        assert!(error.contains("size limit"));

        let (cancel, cancellation) = watch::channel(false);
        assert!(cancel.send(true).is_ok());
        let mut input = std::io::Cursor::new(b"<nzb/>".as_slice());
        let error = read_nzb_bytes(&mut input, &cancellation, 1024).unwrap_err();
        assert!(error.contains("cancel"));
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
            panic!("expected 7z selection");
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
            panic!("expected 7z selection");
        };
        assert_eq!(volumes.len(), 2);
        assert_eq!(volumes[0].filename(), Some("large.7z.001"));
    }

    #[test]
    fn split_rar_ciltleri_sayisal_sirayla_secilir() {
        let parsed = nzb::Nzb {
            meta: vec![("password".into(), "nzb-parolasi".into())],
            files: vec![
                file("\"movie.part02.rar\" yEnc (1/1)", 1, 1000),
                file("\"movie.part01.rar\" yEnc (1/1)", 1, 1000),
            ],
        };
        let selection = select_stream(&parsed).unwrap();
        let StreamSelection::Rar { volumes, password } = selection else {
            panic!("expected RAR selection");
        };
        assert_eq!(volumes[0].filename(), Some("movie.part01.rar"));
        assert_eq!(volumes[1].filename(), Some("movie.part02.rar"));
        // NZB password metası RAR yoluna da taşınır (7z ile aynı kural).
        assert_eq!(password.as_deref(), Some("nzb-parolasi"));
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
        let StreamSelection::Rar { volumes, password } = select_stream(&parsed).unwrap() else {
            panic!("expected RAR selection");
        };
        assert_eq!(volumes.len(), 2);
        assert_eq!(volumes[0].filename(), Some("large.part01.rar"));
        assert!(password.is_none());
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

    #[test]
    fn obfuske_sayisal_set_probe_secimine_duser() {
        let parsed = nzb::Nzb {
            meta: vec![("password".into(), "TESTPASS123".into())],
            files: vec![
                file("\"33dce3ecfd2d186566653db06253ceba.par2\" yEnc (1/1)", 1, 10),
                file("\"33dce3ecfd2d186566653db06253ceba.11\" yEnc (1/1)", 1, 1000),
                file("\"33dce3ecfd2d186566653db06253ceba.10\" yEnc (1/1)", 1, 1000),
            ],
        };
        let selection = select_stream(&parsed).unwrap();
        let StreamSelection::Probe {
            base_name,
            volumes,
            password,
        } = selection
        else {
            panic!("expected Probe selection");
        };
        assert_eq!(base_name, "33dce3ecfd2d186566653db06253ceba");
        assert_eq!(volumes.len(), 2);
        assert_eq!(
            volumes[0].filename(),
            Some("33dce3ecfd2d186566653db06253ceba.10")
        );
        assert_eq!(
            volumes[1].filename(),
            Some("33dce3ecfd2d186566653db06253ceba.11")
        );
        assert_eq!(password.as_deref(), Some("TESTPASS123"));
    }

    #[test]
    fn taninmayan_icerik_hala_acik_hata_verir() {
        let parsed = nzb::Nzb {
            meta: vec![],
            files: vec![file("\"readme.nfo\" yEnc (1/1)", 1, 10)],
        };
        let Err(error) = select_stream(&parsed) else {
            panic!("unknown content must keep the explicit error");
        };
        assert!(error.contains("no direct video or supported split 7z/RAR STORE set"));
    }
}
