//! PAR2 onarım API'si (flutter_rust_bridge).
//!
//! Oynatma/başlatma kalıcı hasara (sunucuda eksik article, yEnc CRC
//! uyuşmazlığı) takıldığında kullanıcı onarım başlatır. Motor recovery
//! set'in tüm dilimlerini bir kez doğrular, hasarlıları Reed-Solomon ile
//! onarır ve katmanı diske yazar; sonraki `begin_stream` katmanı kurar.
//!
//! Oturum modeli [`crate::api::streaming`]`dekiyle aynıdır: `begin_repair`
//! kimliği hemen döndürür, ilerleme `repair_progress` ile yoklanır, sonuç
//! `await_repair` ile alınır, `cancel_repair` ile durdurulur.

use std::collections::HashMap;
use std::ops::Range;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use once_cell::sync::Lazy;
use tokio::sync::{oneshot, watch};
use tokio::task::JoinHandle;

use crate::engine::locator::SegmentLocator;
use crate::engine::nntp::{NntpPool, TlsNntpConnector};
use crate::engine::nntp_source::{read_body_with_timeout, SegmentCache, BODY_READ_TIMEOUT};
use crate::engine::nzb::{self, NzbFile};
use crate::engine::repair::{
    repair_release, RepairError, RepairFetcher, RepairOverlay, RepairPhase, RepairProgress,
};
use crate::engine::yenc;

use super::streaming::{ProviderConfigDto, RUNTIME};

const REPAIR_SEGMENT_CACHE: usize = 64;
const MAX_NZB_FILE_BYTES: u64 = 64 * 1024 * 1024;

/// Onarım oturumunun ilerleme anlığı.
pub struct RepairProgressDto {
    /// "loading" | "verifying" | "solving" | "repairing" | "writing" | "done"
    pub phase: String,
    pub completed_bytes: u64,
    pub total_bytes: u64,
    pub detail: String,
}

/// Onarım sonucu. `clean` true ise set hasarsız çıktı ve katman gerekmedi.
pub struct RepairReportDto {
    pub verified_files: u32,
    pub damaged_slices: u32,
    pub repaired_slices: u32,
    pub clean: bool,
    /// Katman diske yazıldıysa true; sonraki oynatma onarılan bölgeleri
    /// yerelden servis eder.
    pub overlay_active: bool,
}

struct ActiveRepair {
    session_id: u64,
    cancel: watch::Sender<bool>,
    task: JoinHandle<()>,
    ready: Option<oneshot::Receiver<Result<RepairReportDto, String>>>,
    progress: Arc<Mutex<RepairProgressDto>>,
}

static ACTIVE_REPAIR: Lazy<Mutex<Option<ActiveRepair>>> = Lazy::new(|| Mutex::new(None));
static NEXT_REPAIR_ID: AtomicU64 = AtomicU64::new(1);

// ---------------------------------------------------------------------------
// NNTP fetcher — toleranslı dilim okuyucu
// ---------------------------------------------------------------------------

/// [`RepairFetcher`] için NZB+NNTP hali. `NntpByteSource`'un aksine ilk
/// segmenti çekemeyen (hasarlı) dosyalarda bile kurulabilir; boyut ve
/// konumlar yEnc kayıtlarından tembel öğrenilir.
struct NntpRepairFetcher {
    pool: Arc<NntpPool<TlsNntpConnector>>,
    files: HashMap<String, NzbFile>,
    locators: Mutex<HashMap<String, Arc<Mutex<SegmentLocator>>>>,
    cache: Mutex<HashMap<String, Arc<Mutex<SegmentCache>>>>,
    cancellation: watch::Receiver<bool>,
}

impl NntpRepairFetcher {
    fn new(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        files: Vec<NzbFile>,
        cancellation: watch::Receiver<bool>,
    ) -> Self {
        let files = files
            .into_iter()
            .filter_map(|file| {
                let name = file.filename().map(str::to_ascii_lowercase);
                name.map(|name| (name, file))
            })
            .collect();
        Self {
            pool,
            files,
            locators: Mutex::new(HashMap::new()),
            cache: Mutex::new(HashMap::new()),
            cancellation,
        }
    }

    fn file(&self, name: &str) -> Result<&NzbFile, RepairError> {
        self.files
            .get(&name.to_ascii_lowercase())
            .ok_or_else(|| RepairError::Io(std::io::Error::other("dosya NZB'de yok")))
    }

    fn locator_for(&self, name: &str) -> Result<Arc<Mutex<SegmentLocator>>, RepairError> {
        let mut locators = self.locators.lock().expect("locator lock");
        if let Some(locator) = locators.get(&name.to_ascii_lowercase()) {
            return Ok(Arc::clone(locator));
        }
        let file = self.file(name)?;
        let locator = Arc::new(Mutex::new(SegmentLocator::from_nzb_file(file)));
        locators.insert(name.to_ascii_lowercase(), Arc::clone(&locator));
        Ok(locator)
    }

    fn cache_for(&self, name: &str) -> Arc<Mutex<SegmentCache>> {
        let mut cache = self.cache.lock().expect("cache lock");
        cache
            .entry(name.to_ascii_lowercase())
            .or_insert_with(|| Arc::new(Mutex::new(SegmentCache::new(REPAIR_SEGMENT_CACHE))))
            .clone()
    }

    /// Segmenti çeker, yEnc çözer, konumunu eşleyiciye kaydeder.
    async fn fetch_segment(
        &self,
        name: &str,
        index: usize,
    ) -> std::io::Result<Arc<Vec<u8>>> {
        let locator = self.locator_for(name).map_err(std::io::Error::other)?;
        let cache = self.cache_for(name);
        if let Some(data) = cache.lock().expect("cache").get(index) {
            return Ok(data);
        }
        let message_id = {
            let loc = locator.lock().expect("locator");
            loc.message_id(index)
                .ok_or_else(|| std::io::Error::other(format!("segment {index} yok")))?
                .to_string()
        };

        let work = async {
            let mut conn = self
                .pool
                .checkout()
                .await
                .map_err(|error| std::io::Error::other(error.to_string()))?;
            let body =
                match read_body_with_timeout(BODY_READ_TIMEOUT, conn.body_by_message_id(&message_id))
                    .await
                {
                    Ok(body) => {
                        conn.mark_reusable();
                        body
                    }
                    Err(error) => return Err(std::io::Error::other(error.to_string())),
                };
            drop(conn);
            yenc::decode(&body).map_err(|error| std::io::Error::other(error.to_string()))
        };

        let part = {
            let mut cancellation = self.cancellation.clone();
            tokio::select! {
                biased;
                _ = cancellation.changed() => {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::Interrupted,
                        "repair fetch cancelled",
                    ));
                }
                result = work => result?,
            }
        };

        {
            let mut loc = locator.lock().expect("locator");
            if !loc.is_located(index) {
                loc.record_part(index, &part)
                    .map_err(|error| std::io::Error::other(error.to_string()))?;
            }
        }
        let data = Arc::new(part.data.clone());
        cache.lock().expect("cache").insert(index, Arc::clone(&data));
        Ok(data)
    }

    /// `offset`'i içeren segmenti ve span'ini bulur; gerekiyorsa çeker.
    async fn locate(
        &self,
        name: &str,
        offset: u64,
    ) -> std::io::Result<(usize, Range<u64>)> {
        let locator = self.locator_for(name).map_err(std::io::Error::other)?;
        loop {
            let outcome = {
                let loc = locator.lock().expect("locator");
                loc.resolve(offset..offset + 1)
            };
            match outcome {
                Ok(slices) => {
                    let index = slices[0].index;
                    let span = locator
                        .lock()
                        .expect("locator")
                        .decoded_span(index)
                        .expect("decoded segment has a span");
                    return Ok((index, span));
                }
                Err(crate::engine::locator::LocatorError::NeedSegments(indices)) => {
                    for index in indices {
                        self.fetch_segment(name, index).await?;
                    }
                }
                Err(other) => return Err(std::io::Error::other(other.to_string())),
            }
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
impl RepairFetcher for NntpRepairFetcher {
    fn has_file(&self, name: &str) -> bool {
        self.files.contains_key(&name.to_ascii_lowercase())
    }

    async fn read_range(&self, name: &str, range: Range<u64>) -> std::io::Result<Vec<u8>> {
        let mut output = Vec::with_capacity((range.end - range.start) as usize);
        let mut cursor = range.start;
        while cursor < range.end {
            let (index, span) = self.locate(name, cursor).await?;
            let seg_end = span.end.min(range.end);
            let data = self.fetch_segment(name, index).await?;
            let from = (cursor - span.start) as usize;
            let to = (seg_end - span.start) as usize;
            output.extend_from_slice(&data[from..to]);
            cursor = seg_end;
        }
        Ok(output)
    }

    async fn read_par2(&self, name: &str) -> std::io::Result<Vec<u8>> {
        let locator = self.locator_for(name).map_err(std::io::Error::other)?;
        let mut output: Vec<u8> = Vec::new();
        let mut index = 0usize;
        let segment_total = {
            let loc = locator.lock().expect("locator");
            loc.segment_count()
        };
        loop {
            let data = self.fetch_segment(name, index).await?;
            let span = locator
                .lock()
                .expect("locator")
                .decoded_span(index)
                .expect("decoded segment has a span");
            if span.end as usize > output.len() {
                output.resize(span.end as usize, 0);
            }
            output[span.start as usize..span.end as usize].copy_from_slice(&data);

            let file_size = locator.lock().expect("locator").file_size();
            if let Some(size) = file_size {
                if span.end >= size {
                    output.truncate(size as usize);
                    break;
                }
            }
            index += 1;
            if index > segment_total + 1 {
                return Err(std::io::Error::other(
                    "PAR2 file did not complete even after fetching all segments",
                ));
            }
        }
        Ok(output)
    }
}

// ---------------------------------------------------------------------------
// Oturum yönetimi (begin/await/progress/cancel)
// ---------------------------------------------------------------------------

/// Onarım oturumunu başlatır ve kimliği hemen döndürür. Sonuç
/// [`await_repair`] ile alınır; ilerleme [`repair_progress`] ile yoklanır.
pub fn begin_repair(config: ProviderConfigDto, nzb_path: String) -> u64 {
    let session_id = NEXT_REPAIR_ID.fetch_add(1, Ordering::SeqCst);
    let (cancel, cancellation) = watch::channel(false);
    let (ready, ready_result) = oneshot::channel();
    let progress = Arc::new(Mutex::new(RepairProgressDto {
        phase: "loading".to_string(),
        completed_bytes: 0,
        total_bytes: 0,
        detail: String::new(),
    }));

    let mut active = ACTIVE_REPAIR.lock().expect("active repair lock");
    if let Some(previous) = active.take() {
        let _ = previous.cancel.send(true);
        // Önceki görevin kapanmasını bekletmek için yeni göreve taşınır.
        RUNTIME.spawn(async move {
            let _ = previous.task.await;
        });
    }

    let task = RUNTIME.spawn(run_repair_session(
        config,
        nzb_path,
        cancellation,
        ready,
        Arc::clone(&progress),
    ));
    *active = Some(ActiveRepair {
        session_id,
        cancel,
        task,
        ready: Some(ready_result),
        progress,
    });
    session_id
}

/// Oturumun son ilerleme anlığını döndürür; oturum yoksa None.
pub fn repair_progress(session_id: u64) -> Option<RepairProgressDto> {
    let active = ACTIVE_REPAIR.lock().expect("active repair lock");
    let repair = active
        .as_ref()
        .filter(|repair| repair.session_id == session_id)?;
    let progress = repair.progress.lock().expect("ilerleme kilidi");
    Some(RepairProgressDto {
        phase: progress.phase.clone(),
        completed_bytes: progress.completed_bytes,
        total_bytes: progress.total_bytes,
        detail: progress.detail.clone(),
    })
}

/// Oturum sonucunu bekler. Oturum iptal edilmişse açık hata döner.
pub fn await_repair(session_id: u64) -> Result<RepairReportDto, String> {
    let (ready_result, cancel) = {
        let mut active = ACTIVE_REPAIR.lock().expect("active repair lock");
        let repair = active
            .as_mut()
            .filter(|repair| repair.session_id == session_id)
            .ok_or_else(|| "repair session is no longer active".to_string())?;
        let ready = repair
            .ready
            .take()
            .ok_or_else(|| "repair result already expected".to_string())?;
        (ready, repair.cancel.clone())
    };

    let result = RUNTIME.block_on(async move {
        match ready_result.await {
            Ok(result) => result,
            Err(_) => Err("repair session closed unexpectedly".to_string()),
        }
    });
    if result.is_err() {
        let _ = cancel.send(true);
    }
    result
}

/// Oturumu iptal eder. Kimlik artık aktif değilse false döner.
pub fn cancel_repair(session_id: u64) -> bool {
    let active = ACTIVE_REPAIR.lock().expect("active repair lock");
    let Some(repair) = active
        .as_ref()
        .filter(|repair| repair.session_id == session_id)
    else {
        return false;
    };
    let _ = repair.cancel.send(true);
    true
}

async fn run_repair_session(
    config: ProviderConfigDto,
    nzb_path: String,
    cancellation: watch::Receiver<bool>,
    ready: oneshot::Sender<Result<RepairReportDto, String>>,
    progress: Arc<Mutex<RepairProgressDto>>,
) {
    let result = run_repair_inner(config, nzb_path, cancellation, progress).await;
    let _ = ready.send(result);
}

async fn run_repair_inner(
    config: ProviderConfigDto,
    nzb_path: String,
    cancellation: watch::Receiver<bool>,
    progress: Arc<Mutex<RepairProgressDto>>,
) -> Result<RepairReportDto, String> {
    // NZB'yi oku ve .par2 dosyalarını topla.
    let path_for_read = nzb_path.clone();
    let nzb_bytes = tokio::task::spawn_blocking(move || std::fs::read(&path_for_read))
        .await
        .map_err(|error| error.to_string())?
        .map_err(|error| format!("could not read NZB: {error}"))?;
    if nzb_bytes.len() as u64 > MAX_NZB_FILE_BYTES {
        return Err(format!(
            "NZB file exceeds the safe size limit ({MAX_NZB_FILE_BYTES} bytes)"
        ));
    }
    let nzb_text = String::from_utf8(nzb_bytes).map_err(|_| "NZB is not UTF-8".to_string())?;
    let parsed = nzb::parse_nzb(&nzb_text).map_err(|error| error.to_string())?;

    let par2_names: Vec<String> = parsed
        .files
        .iter()
        .filter_map(|file| file.filename())
        .filter(|name| name.to_ascii_lowercase().ends_with(".par2"))
        .map(str::to_string)
        .collect();
    if par2_names.is_empty() {
        return Err("no PAR2 file in the NZB; this release cannot be repaired".to_string());
    }

    let pool = TlsNntpConnector::new(config.into()).into_pool();
    let fetcher = Arc::new(NntpRepairFetcher::new(
        pool,
        parsed.files.clone(),
        cancellation.clone(),
    ));
    let overlay_dir = RepairOverlay::dir_for_nzb(Path::new(&nzb_path));

    let progress_fn = {
        let progress = Arc::clone(&progress);
        move |update: RepairProgress| {
            let phase = match update.phase {
                RepairPhase::LoadingPar2 => "loading",
                RepairPhase::Verifying => "verifying",
                RepairPhase::Solving => "solving",
                RepairPhase::Repairing => "repairing",
                RepairPhase::Writing => "writing",
                RepairPhase::Done => "done",
            };
            let mut slot = progress.lock().expect("ilerleme kilidi");
            slot.phase = phase.to_string();
            slot.completed_bytes = update.completed_bytes;
            slot.total_bytes = update.total_bytes;
            slot.detail = update.detail;
        }
    };

    let report = repair_release(
        &fetcher,
        &par2_names,
        &overlay_dir,
        &progress_fn,
        Some(cancellation),
    )
    .await
    .map_err(|error| error.to_string())?;

    Ok(RepairReportDto {
        verified_files: report.verified_files,
        damaged_slices: report.damaged_slices,
        repaired_slices: report.repaired_slices,
        clean: report.overlay_dir.is_none(),
        overlay_active: report.overlay_dir.is_some(),
    })
}
