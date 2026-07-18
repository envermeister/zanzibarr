//! Bölünmüş arşiv yayınlarının (7z, RAR) ortak NNTP cilt altyapısı.
//!
//! Ciltler diske indirilmez. Her arşiv cildi mevcut NNTP+yEnc kaynağıyla
//! açılır, tek bir sanal byte uzayında birleştirilir ve arşiv başlıklarının
//! istediği aralıklar o uzaydan tembel olarak çekilir. 7z ve RAR arka uçları
//! bu modüldeki yapıları paylaşır; biçim-özel başlık ayrıştırma kendi
//! modüllerindedir.

use std::future::Future;
use std::io::{self, Read, Seek, SeekFrom};
use std::ops::Range;
use std::sync::Arc;

use thiserror::Error;
use tokio::io::AsyncWrite;
use tokio::sync::watch;

use super::nntp::{NntpPool, TlsNntpConnector};
use super::nntp_source::NntpByteSource;
use super::nzb::NzbFile;
use super::server::RangeSource;

pub(crate) const ARCHIVE_VOLUME_CACHE_SEGMENTS: usize = 4;
pub(crate) const MAX_ARCHIVE_VOLUMES: usize = 4096;
pub(crate) const BLOCKING_READER_MAX_CHUNK: usize = 1024 * 1024;

/// Cilt kümesi kurulurken oluşabilecek hatalar. Biçim-özel hata türleri
/// (SevenZipError, RarError) bu türe `From` ile bağlanır.
#[derive(Debug, Error)]
pub(crate) enum VolumeSetError {
    #[error("{0}")]
    Io(#[from] io::Error),
    #[error("{0}")]
    InvalidLayout(String),
    #[error("arşiv ciltleri hazırlanırken iptal edildi")]
    Cancelled,
}

/// `spawn_blocking` içinde yürütülen arşiv ayrıştırma görevinin sonucu.
#[derive(Debug, Error)]
pub(crate) enum BlockingTaskError {
    #[error("ayrıştırma görevi tamamlanamadı: {0}")]
    Task(String),
    #[error("arşiv hazırlama iptal edildi")]
    Cancelled,
}

pub(crate) fn cancellation_requested(cancellation: &watch::Receiver<bool>) -> bool {
    *cancellation.borrow() || cancellation.has_changed().is_err()
}

pub(crate) async fn wait_for_cancellation(cancellation: &mut watch::Receiver<bool>) {
    loop {
        if cancellation_requested(cancellation) {
            return;
        }
        if cancellation.changed().await.is_err() {
            return;
        }
    }
}

fn validate_volume_count(count: usize) -> Result<(), VolumeSetError> {
    if count == 0 {
        return Err(VolumeSetError::InvalidLayout("arşiv cildi yok".into()));
    }
    if count > MAX_ARCHIVE_VOLUMES {
        return Err(VolumeSetError::InvalidLayout(format!(
            "arşiv cilt sayısı {count}; güvenli sınır {MAX_ARCHIVE_VOLUMES}"
        )));
    }
    Ok(())
}

fn ensure_not_cancelled(cancellation: &watch::Receiver<bool>) -> Result<(), VolumeSetError> {
    if cancellation_requested(cancellation) {
        Err(VolumeSetError::Cancelled)
    } else {
        Ok(())
    }
}

async fn bootstrap_sequential<I, O, F, Fut>(
    items: Vec<I>,
    cancellation: &mut watch::Receiver<bool>,
    mut bootstrap: F,
) -> Result<Vec<O>, VolumeSetError>
where
    F: FnMut(I) -> Fut,
    Fut: Future<Output = Result<O, VolumeSetError>>,
{
    let mut output = Vec::with_capacity(items.len());
    for item in items {
        ensure_not_cancelled(cancellation)?;
        let value = tokio::select! {
            result = bootstrap(item) => result?,
            _ = wait_for_cancellation(cancellation) => {
                return Err(VolumeSetError::Cancelled);
            }
        };
        output.push(value);
    }
    Ok(output)
}

/// Bölünmüş arşiv ciltlerini (`.7z.NNN`, `.partNN.rar`, ...) tek bir sanal
/// byte kaynağı olarak gösterir. Cilt sınırları gerçek yEnc `size=`
/// bilgisinden öğrenilir.
pub(crate) struct NntpVolumeSet {
    volumes: Vec<Arc<NntpByteSource>>,
    starts: Vec<u64>,
    total_len: u64,
    segment_count: usize,
}

impl NntpVolumeSet {
    pub(crate) async fn new_cancellable(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        files: Vec<NzbFile>,
        cancellation: &mut watch::Receiver<bool>,
    ) -> Result<Self, VolumeSetError> {
        validate_volume_count(files.len())?;
        ensure_not_cancelled(cancellation)?;

        // Her cildin ilk article'ı yEnc `size=` değerini taşır. Ciltleri tam
        // sıralı ve tek tek bootstrap etmek, tamamlanan BODY sonrasında aynı
        // havuz bağlantısının yeniden kullanılmasını sağlar; 140 ciltli bir
        // set bile bağlantı oturumu yağdırmaz.
        let volumes = bootstrap_sequential(files, cancellation, |file| {
            let pool = Arc::clone(&pool);
            async move {
                let source =
                    NntpByteSource::with_cache_capacity(pool, &file, ARCHIVE_VOLUME_CACHE_SEGMENTS)
                        .await
                        .map_err(VolumeSetError::Io)?;
                Ok(Arc::new(source))
            }
        })
        .await?;
        ensure_not_cancelled(cancellation)?;

        let mut starts = Vec::with_capacity(volumes.len());
        let mut total_len = 0u64;
        let mut segment_count = 0usize;
        for volume in &volumes {
            starts.push(total_len);
            total_len = total_len
                .checked_add(volume.total_len())
                .ok_or_else(|| VolumeSetError::InvalidLayout("arşiv boyutu taştı".into()))?;
            segment_count = segment_count.saturating_add(volume.segment_count());
        }

        Ok(Self {
            volumes,
            starts,
            total_len,
            segment_count,
        })
    }

    pub(crate) fn total_len(&self) -> u64 {
        self.total_len
    }

    pub(crate) fn segment_count(&self) -> usize {
        self.segment_count
    }

    pub(crate) fn volume_count(&self) -> usize {
        self.volumes.len()
    }

    /// Cildin sanal byte uzayındaki başlangıç ofseti.
    pub(crate) fn volume_start(&self, index: usize) -> u64 {
        self.starts[index]
    }

    /// Cildin çözülmüş (yEnc sonrası) gerçek bayt uzunluğu.
    pub(crate) fn volume_len(&self, index: usize) -> u64 {
        self.volumes[index].total_len()
    }

    fn volume_at(&self, offset: u64) -> Option<usize> {
        if offset >= self.total_len {
            return None;
        }
        Some(self.starts.partition_point(|&start| start <= offset) - 1)
    }

    pub(crate) async fn read_range_bytes(&self, range: Range<u64>) -> io::Result<Vec<u8>> {
        validate_range(range.clone(), self.total_len)?;
        let capacity = usize::try_from(range.end - range.start)
            .map_err(|_| io::Error::other("istenen aralık belleğe sığmıyor"))?;
        let mut output = Vec::with_capacity(capacity);
        let mut cursor = range.start;

        while cursor < range.end {
            let index = self
                .volume_at(cursor)
                .ok_or_else(|| io::Error::other("arşiv cilt ofseti bulunamadı"))?;
            let volume_start = self.starts[index];
            let volume_len = self.volumes[index].total_len();
            let end = range.end.min(volume_start + volume_len);
            let bytes = self.volumes[index]
                .read_range_bytes((cursor - volume_start)..(end - volume_start))
                .await?;
            output.extend_from_slice(&bytes);
            cursor = end;
        }
        Ok(output)
    }

    pub(crate) async fn write_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        validate_range(range.clone(), self.total_len)?;
        let mut cursor = range.start;
        while cursor < range.end {
            let index = self
                .volume_at(cursor)
                .ok_or_else(|| io::Error::other("arşiv cilt ofseti bulunamadı"))?;
            let volume_start = self.starts[index];
            let volume_len = self.volumes[index].total_len();
            let end = range.end.min(volume_start + volume_len);
            self.volumes[index]
                .write_range((cursor - volume_start)..(end - volume_start), out)
                .await?;
            cursor = end;
        }
        Ok(())
    }
}

pub(crate) fn validate_range(range: Range<u64>, total_len: u64) -> io::Result<()> {
    if range.start >= range.end || range.end > total_len {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "geçersiz byte aralığı {}..{} (boyut {total_len})",
                range.start, range.end
            ),
        ));
    }
    Ok(())
}

/// Senkron `Read + Seek` isteyen arşiv parser'larını asenkron NNTP kaynağına
/// bağlar. Yalnız `spawn_blocking` içinde kullanılır.
pub(crate) struct BlockingArchiveReader {
    source: Arc<NntpVolumeSet>,
    runtime: tokio::runtime::Handle,
    cancellation: watch::Receiver<bool>,
    position: u64,
}

impl BlockingArchiveReader {
    pub(crate) fn new(
        source: Arc<NntpVolumeSet>,
        runtime: tokio::runtime::Handle,
        cancellation: watch::Receiver<bool>,
    ) -> Self {
        Self {
            source,
            runtime,
            cancellation,
            position: 0,
        }
    }

    fn ensure_active(&self) -> io::Result<()> {
        if cancellation_requested(&self.cancellation) {
            Err(cancellation_io_error())
        } else {
            Ok(())
        }
    }
}

fn cancellation_io_error() -> io::Error {
    io::Error::new(io::ErrorKind::Interrupted, "arşiv hazırlama iptal edildi")
}

impl Read for BlockingArchiveReader {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        self.ensure_active()?;
        if buffer.is_empty() || self.position >= self.source.total_len() {
            return Ok(0);
        }
        let wanted = buffer
            .len()
            .min(BLOCKING_READER_MAX_CHUNK)
            .min((self.source.total_len() - self.position) as usize);
        let end = self.position + wanted as u64;
        let source = Arc::clone(&self.source);
        let range = self.position..end;
        let runtime = self.runtime.clone();
        let cancellation = &mut self.cancellation;
        let bytes = runtime.block_on(async {
            tokio::select! {
                result = source.read_range_bytes(range) => result,
                _ = wait_for_cancellation(cancellation) => Err(cancellation_io_error()),
            }
        })?;
        buffer[..bytes.len()].copy_from_slice(&bytes);
        self.position += bytes.len() as u64;
        Ok(bytes.len())
    }
}

impl Seek for BlockingArchiveReader {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.ensure_active()?;
        let target = match position {
            SeekFrom::Start(value) => i128::from(value),
            SeekFrom::Current(delta) => i128::from(self.position) + i128::from(delta),
            SeekFrom::End(delta) => i128::from(self.source.total_len()) + i128::from(delta),
        };
        if target < 0 || target > i128::from(self.source.total_len()) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!(
                    "arşiv seek sınırının dışında: hedef {target}, boyut {}",
                    self.source.total_len()
                ),
            ));
        }
        self.position = target as u64;
        Ok(self.position)
    }
}

/// Senkron arşiv parser'ını iptal edilebilir biçimde `spawn_blocking` içinde
/// çalıştırır. İptal durumunda detached parser bırakmaz: reader aynı watch
/// sinyalini her read/seek'te görüp Interrupted ile çıkar ve JoinHandle
/// sonuna kadar beklenir.
pub(crate) async fn run_blocking_cancellable<T, F, E>(
    mut cancellation: watch::Receiver<bool>,
    task: F,
) -> Result<T, E>
where
    T: Send + 'static,
    F: FnOnce(watch::Receiver<bool>) -> Result<T, E> + Send + 'static,
    E: From<BlockingTaskError> + Send + 'static,
{
    if cancellation_requested(&cancellation) {
        return Err(BlockingTaskError::Cancelled.into());
    }
    let task_cancellation = cancellation.clone();
    let mut handle = tokio::task::spawn_blocking(move || task(task_cancellation));

    tokio::select! {
        result = &mut handle => {
            let output = result.map_err(|error| BlockingTaskError::Task(error.to_string()))?;
            if cancellation_requested(&cancellation) {
                Err(BlockingTaskError::Cancelled.into())
            } else {
                output
            }
        }
        _ = wait_for_cancellation(&mut cancellation) => {
            match handle.await {
                Ok(_) => Err(BlockingTaskError::Cancelled.into()),
                Err(error) => Err(BlockingTaskError::Task(error.to_string()).into()),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::SeekFrom;

    #[test]
    fn cilt_sayisi_bos_ve_asiri_setleri_reddeder() {
        assert!(validate_volume_count(140).is_ok());
        assert!(matches!(
            validate_volume_count(0),
            Err(VolumeSetError::InvalidLayout(_))
        ));
        assert!(matches!(
            validate_volume_count(MAX_ARCHIVE_VOLUMES + 1),
            Err(VolumeSetError::InvalidLayout(_))
        ));
    }

    #[tokio::test]
    async fn cilt_bootstrap_tam_sirali_ve_tektir() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        let (_cancellation_guard, mut cancellation) = watch::channel(false);
        let active = Arc::new(AtomicUsize::new(0));
        let peak = Arc::new(AtomicUsize::new(0));
        let output = bootstrap_sequential(vec![3, 1, 2], &mut cancellation, |item| {
            let active = Arc::clone(&active);
            let peak = Arc::clone(&peak);
            async move {
                let current = active.fetch_add(1, Ordering::SeqCst) + 1;
                peak.fetch_max(current, Ordering::SeqCst);
                tokio::time::sleep(std::time::Duration::from_millis(2)).await;
                active.fetch_sub(1, Ordering::SeqCst);
                Ok::<_, VolumeSetError>(item)
            }
        })
        .await
        .unwrap();

        assert_eq!(output, vec![3, 1, 2]);
        assert_eq!(peak.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn cilt_bootstrap_devam_eden_okumayi_iptal_eder() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let (cancel_tx, mut cancellation) = watch::channel(false);
        let started = Arc::new(AtomicBool::new(false));
        let started_in_task = Arc::clone(&started);
        let task = tokio::spawn(async move {
            bootstrap_sequential(vec![1], &mut cancellation, move |_| {
                let started = Arc::clone(&started_in_task);
                async move {
                    started.store(true, Ordering::SeqCst);
                    std::future::pending::<Result<(), VolumeSetError>>().await
                }
            })
            .await
        });

        while !started.load(Ordering::SeqCst) {
            tokio::task::yield_now().await;
        }
        cancel_tx.send(true).unwrap();
        let result = tokio::time::timeout(std::time::Duration::from_secs(1), task)
            .await
            .expect("bootstrap iptal sinyalinde bitmeli")
            .unwrap();
        assert!(matches!(result, Err(VolumeSetError::Cancelled)));
    }

    #[tokio::test]
    async fn blocking_reader_read_ve_seek_oncesi_iptali_gorur() {
        let archive = Arc::new(NntpVolumeSet {
            volumes: Vec::new(),
            starts: Vec::new(),
            total_len: 1,
            segment_count: 0,
        });
        let (cancel_tx, cancellation) = watch::channel(false);
        let mut reader =
            BlockingArchiveReader::new(archive, tokio::runtime::Handle::current(), cancellation);
        cancel_tx.send(true).unwrap();

        let read_error = reader.read(&mut [0]).unwrap_err();
        assert_eq!(read_error.kind(), io::ErrorKind::Interrupted);
        let seek_error = reader.seek(SeekFrom::Start(0)).unwrap_err();
        assert_eq!(seek_error.kind(), io::ErrorKind::Interrupted);
    }

    #[tokio::test]
    async fn blocking_parser_iptalde_detached_birakilmaz() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let (cancel_tx, cancellation) = watch::channel(false);
        let (started_tx, started_rx) = tokio::sync::oneshot::channel();
        let finished = Arc::new(AtomicBool::new(false));
        let finished_in_task = Arc::clone(&finished);
        let task = tokio::spawn(run_blocking_cancellable(
            cancellation,
            move |reader_cancellation| {
                let _ = started_tx.send(());
                while !cancellation_requested(&reader_cancellation) {
                    std::thread::yield_now();
                }
                // Outer future bu blocking iş gerçekten dönmeden sonuç
                // vermemeli; gecikme detached-task regresyonunu görünür kılar.
                std::thread::sleep(std::time::Duration::from_millis(25));
                finished_in_task.store(true, Ordering::SeqCst);
                Err::<(), _>(BlockingTaskError::Cancelled)
            },
        ));

        started_rx.await.unwrap();
        cancel_tx.send(true).unwrap();
        let result = tokio::time::timeout(std::time::Duration::from_secs(1), task)
            .await
            .expect("blocking parser cooperative olarak kapanmalı")
            .unwrap();
        assert!(matches!(result, Err(BlockingTaskError::Cancelled)));
        assert!(
            finished.load(Ordering::SeqCst),
            "outer future blocking parser bitmeden dönmemeli"
        );
    }
}
