//! Çok ciltli 7z STORE/AES yayınlarını sanal, seek edilebilir medya dosyasına
//! dönüştürür.
//!
//! 7z ciltleri diske indirilmez. Her `.7z.NNN` dosyası mevcut NNTP+yEnc
//! kaynağıyla açılır, tek bir sanal byte uzayında birleştirilir ve yalnız 7z
//! başlığının istediği aralıklar çekilir. İçerideki medya girdisi COPY/STORE
//! ise pack aralığı doğrudan sunulur; AES-256-CBC varsa istenen bloklar yerinde
//! çözülür. LZMA/LZMA2/solid arşivler, rastgele seek'i bozmamak için açıkça
//! reddedilir.

use std::future::Future;
use std::io::{self, Cursor, Read, Seek, SeekFrom};
use std::ops::Range;
use std::sync::Arc;

use aes::Aes256;
use cbc::cipher::{block_padding::NoPadding, BlockDecryptMut, KeyIvInit};
use thiserror::Error;
use tokio::io::{AsyncWrite, AsyncWriteExt};
use tokio::sync::watch;
use zeroize::Zeroizing;
use zesven::codec::{method, CopyDecoder, Lzma2Decoder, LzmaDecoder};
use zesven::crypto::{derive_key, Aes256Decoder, AesProperties};
use zesven::format::header::StartHeader;
use zesven::format::parser::{ArchiveHeader, HeaderParser};
use zesven::format::reader::read_u8;
use zesven::format::streams::{Folder, PackInfo, ResourceLimits, SubStreamsInfo, UnpackInfo};
use zesven::format::{property_id, SIGNATURE_HEADER_SIZE};
use zesven::Password;

use super::nntp::{NntpPool, TlsNntpConnector};
use super::nntp_source::NntpByteSource;
use super::nzb::{is_playable_media_filename, NzbFile};
use super::server::{content_type_for, RangeSource};

const ARCHIVE_VOLUME_CACHE_SEGMENTS: usize = 4;
const MAX_ARCHIVE_VOLUMES: usize = 4096;
const BLOCKING_READER_MAX_CHUNK: usize = 1024 * 1024;
const AES_STREAM_CHUNK: u64 = 1024 * 1024;
const AES_BLOCK_SIZE: u64 = 16;

type Aes256CbcDec = cbc::Decryptor<Aes256>;

#[derive(Debug, Error)]
pub enum SevenZipError {
    #[error("7z ciltleri hazırlanamadı: {0}")]
    Io(#[from] io::Error),
    #[error("7z başlığı okunamadı: {0}")]
    Header(String),
    #[error("7z arşivinde oynatılabilir medya dosyası yok")]
    NoPlayableMedia,
    #[error("7z arşivi sıkıştırılmış; yalnız COPY/STORE arşivleri seek edilerek oynatılabilir")]
    UnsupportedCompression,
    #[error("7z arşivi solid; rastgele seek için non-solid STORE arşivi gerekli")]
    SolidArchive,
    #[error("parola korumalı 7z arşivinde NZB password metası yok")]
    MissingPassword,
    #[error("geçersiz 7z yerleşimi: {0}")]
    InvalidLayout(String),
    #[error("7z hazırlama görevi tamamlanamadı: {0}")]
    Task(String),
    #[error("7z hazırlama iptal edildi")]
    Cancelled,
}

/// Birleştirilmiş `.7z.001`, `.7z.002`, ... dosyalarını tek byte kaynağı
/// olarak gösterir. Cilt sınırları gerçek yEnc `size=` bilgisinden öğrenilir.
struct NntpVolumeSet {
    volumes: Vec<Arc<NntpByteSource>>,
    starts: Vec<u64>,
    total_len: u64,
    segment_count: usize,
}

fn validate_volume_count(count: usize) -> Result<(), SevenZipError> {
    if count == 0 {
        return Err(SevenZipError::InvalidLayout("7z cildi yok".into()));
    }
    if count > MAX_ARCHIVE_VOLUMES {
        return Err(SevenZipError::InvalidLayout(format!(
            "7z cilt sayısı {count}; güvenli sınır {MAX_ARCHIVE_VOLUMES}"
        )));
    }
    Ok(())
}

fn cancellation_requested(cancellation: &watch::Receiver<bool>) -> bool {
    *cancellation.borrow() || cancellation.has_changed().is_err()
}

fn ensure_not_cancelled(cancellation: &watch::Receiver<bool>) -> Result<(), SevenZipError> {
    if cancellation_requested(cancellation) {
        Err(SevenZipError::Cancelled)
    } else {
        Ok(())
    }
}

async fn wait_for_cancellation(cancellation: &mut watch::Receiver<bool>) {
    loop {
        if cancellation_requested(cancellation) {
            return;
        }
        if cancellation.changed().await.is_err() {
            return;
        }
    }
}

async fn bootstrap_sequential<I, O, F, Fut>(
    items: Vec<I>,
    cancellation: &mut watch::Receiver<bool>,
    mut bootstrap: F,
) -> Result<Vec<O>, SevenZipError>
where
    F: FnMut(I) -> Fut,
    Fut: Future<Output = Result<O, SevenZipError>>,
{
    let mut output = Vec::with_capacity(items.len());
    for item in items {
        ensure_not_cancelled(cancellation)?;
        let value = tokio::select! {
            result = bootstrap(item) => result?,
            _ = wait_for_cancellation(cancellation) => {
                return Err(SevenZipError::Cancelled);
            }
        };
        output.push(value);
    }
    Ok(output)
}

impl NntpVolumeSet {
    async fn new_cancellable(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        files: Vec<NzbFile>,
        cancellation: &mut watch::Receiver<bool>,
    ) -> Result<Self, SevenZipError> {
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
                        .map_err(SevenZipError::Io)?;
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
                .ok_or_else(|| SevenZipError::InvalidLayout("arşiv boyutu taştı".into()))?;
            segment_count = segment_count.saturating_add(volume.segment_count());
        }

        Ok(Self {
            volumes,
            starts,
            total_len,
            segment_count,
        })
    }

    fn total_len(&self) -> u64 {
        self.total_len
    }

    fn segment_count(&self) -> usize {
        self.segment_count
    }

    fn volume_at(&self, offset: u64) -> Option<usize> {
        if offset >= self.total_len {
            return None;
        }
        Some(self.starts.partition_point(|&start| start <= offset) - 1)
    }

    async fn read_range_bytes(&self, range: Range<u64>) -> io::Result<Vec<u8>> {
        validate_range(range.clone(), self.total_len)?;
        let capacity = usize::try_from(range.end - range.start)
            .map_err(|_| io::Error::other("istenen aralık belleğe sığmıyor"))?;
        let mut output = Vec::with_capacity(capacity);
        let mut cursor = range.start;

        while cursor < range.end {
            let index = self
                .volume_at(cursor)
                .ok_or_else(|| io::Error::other("7z cilt ofseti bulunamadı"))?;
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

    async fn write_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        validate_range(range.clone(), self.total_len)?;
        let mut cursor = range.start;
        while cursor < range.end {
            let index = self
                .volume_at(cursor)
                .ok_or_else(|| io::Error::other("7z cilt ofseti bulunamadı"))?;
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

fn validate_range(range: Range<u64>, total_len: u64) -> io::Result<()> {
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

fn checked_pack_sum(values: &[u64]) -> Result<u64, SevenZipError> {
    values.iter().try_fold(0u64, |total, &value| {
        total
            .checked_add(value)
            .ok_or_else(|| SevenZipError::InvalidLayout("pack boyut toplamı taştı".into()))
    })
}

fn aes_packed_size(decoded_size: u64) -> Result<u64, SevenZipError> {
    decoded_size
        .div_ceil(AES_BLOCK_SIZE)
        .checked_mul(AES_BLOCK_SIZE)
        .ok_or_else(|| SevenZipError::InvalidLayout("AES pack boyutu taştı".into()))
}

/// Senkron `Read + Seek` isteyen 7z parser'ını asenkron NNTP kaynağına
/// bağlar. Yalnız `spawn_blocking` içinde kullanılır.
struct BlockingArchiveReader {
    source: Arc<NntpVolumeSet>,
    runtime: tokio::runtime::Handle,
    cancellation: watch::Receiver<bool>,
    position: u64,
}

impl BlockingArchiveReader {
    fn new(
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
    io::Error::new(io::ErrorKind::Interrupted, "7z hazırlama iptal edildi")
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
                    "7z seek arşiv sınırının dışında: hedef {target}, boyut {}",
                    self.source.total_len()
                ),
            ));
        }
        self.position = target as u64;
        Ok(self.position)
    }
}

async fn run_blocking_cancellable<T, F>(
    mut cancellation: watch::Receiver<bool>,
    task: F,
) -> Result<T, SevenZipError>
where
    T: Send + 'static,
    F: FnOnce(watch::Receiver<bool>) -> Result<T, SevenZipError> + Send + 'static,
{
    ensure_not_cancelled(&cancellation)?;
    let task_cancellation = cancellation.clone();
    let mut handle = tokio::task::spawn_blocking(move || task(task_cancellation));

    tokio::select! {
        result = &mut handle => {
            let output = result.map_err(|error| SevenZipError::Task(error.to_string()))?;
            if cancellation_requested(&cancellation) {
                Err(SevenZipError::Cancelled)
            } else {
                output
            }
        }
        _ = wait_for_cancellation(&mut cancellation) => {
            // spawn_blocking abort edilemez. Reader aynı watch sinyalini her
            // read/seek'te görüp Interrupted ile çıkar; burada JoinHandle'ı
            // sonuna kadar await ederek detached parser bırakmayız.
            match handle.await {
                Ok(_) => Err(SevenZipError::Cancelled),
                Err(error) => Err(SevenZipError::Task(error.to_string())),
            }
        }
    }
}

struct AesPlan {
    key: Zeroizing<[u8; 32]>,
    iv: [u8; 16],
}

struct EntryPlan {
    filename: String,
    decoded_size: u64,
    packed_range: Range<u64>,
    aes: Option<AesPlan>,
}

/// Oynatıcıya doğrudan medya dosyası gibi görünen 7z içeriği.
pub struct SevenZipEntrySource {
    archive: Arc<NntpVolumeSet>,
    plan: EntryPlan,
    content_type: &'static str,
}

impl SevenZipEntrySource {
    pub async fn new(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        files: Vec<NzbFile>,
        password: Option<String>,
    ) -> Result<Self, SevenZipError> {
        // CLI/test çağrılarında iptal sahibi yoktur; sender bu await boyunca
        // canlı tutularak receiver'ın kapanması yanlış iptal sayılmaz.
        let (_cancellation_guard, cancellation) = watch::channel(false);
        Self::new_cancellable(pool, files, password, cancellation).await
    }

    pub async fn new_cancellable(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        files: Vec<NzbFile>,
        password: Option<String>,
        mut cancellation: watch::Receiver<bool>,
    ) -> Result<Self, SevenZipError> {
        let archive =
            Arc::new(NntpVolumeSet::new_cancellable(pool, files, &mut cancellation).await?);
        ensure_not_cancelled(&cancellation)?;
        let archive_for_parser = Arc::clone(&archive);
        let archive_len = archive.total_len();
        let runtime = tokio::runtime::Handle::current();

        let plan = run_blocking_cancellable(cancellation, move |reader_cancellation| {
            let mut reader =
                BlockingArchiveReader::new(archive_for_parser, runtime, reader_cancellation);
            parse_entry_plan(&mut reader, archive_len, password)
        })
        .await?;

        let content_type = content_type_for(&plan.filename);
        Ok(Self {
            archive,
            plan,
            content_type,
        })
    }

    pub fn filename(&self) -> &str {
        &self.plan.filename
    }

    pub fn segment_count(&self) -> usize {
        self.archive.segment_count()
    }

    async fn write_aes_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        let aes = self.plan.aes.as_ref().expect("AES planı mevcut");
        let mut cursor = range.start;

        while cursor < range.end {
            let chunk_end = range.end.min(cursor.saturating_add(AES_STREAM_CHUNK));
            let first_block = cursor / AES_BLOCK_SIZE;
            let last_block_exclusive = chunk_end.div_ceil(AES_BLOCK_SIZE);
            let cipher_start = self.plan.packed_range.start + first_block * AES_BLOCK_SIZE;
            let cipher_end = self.plan.packed_range.start + last_block_exclusive * AES_BLOCK_SIZE;

            let iv = if first_block == 0 {
                aes.iv
            } else {
                let previous = self
                    .archive
                    .read_range_bytes((cipher_start - AES_BLOCK_SIZE)..cipher_start)
                    .await?;
                previous
                    .try_into()
                    .map_err(|_| io::Error::other("AES önceki blok boyutu geçersiz"))?
            };

            let mut ciphertext = self
                .archive
                .read_range_bytes(cipher_start..cipher_end)
                .await?;
            decrypt_blocks(&aes.key, &iv, &mut ciphertext)?;

            let within_first_block = (cursor % AES_BLOCK_SIZE) as usize;
            let wanted = (chunk_end - cursor) as usize;
            out.write_all(&ciphertext[within_first_block..within_first_block + wanted])
                .await?;
            cursor = chunk_end;
        }
        Ok(())
    }
}

impl RangeSource for SevenZipEntrySource {
    fn total_len(&self) -> u64 {
        self.plan.decoded_size
    }

    fn content_type(&self) -> &str {
        self.content_type
    }

    async fn write_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        validate_range(range.clone(), self.plan.decoded_size)?;
        if self.plan.aes.is_some() {
            self.write_aes_range(range, out).await
        } else {
            self.archive
                .write_range(
                    (self.plan.packed_range.start + range.start)
                        ..(self.plan.packed_range.start + range.end),
                    out,
                )
                .await
        }
    }
}

fn parse_entry_plan<R: Read + Seek>(
    reader: &mut R,
    archive_len: u64,
    password: Option<String>,
) -> Result<EntryPlan, SevenZipError> {
    preflight_archive_size(reader, archive_len)?;

    let password = password.map(Password::new);
    let limits = ResourceLimits::default()
        .max_entry_unpacked(256 * 1024 * 1024 * 1024)
        .max_total_unpacked(512 * 1024 * 1024 * 1024);
    let header = read_standard_archive_header(reader, archive_len, &limits, password.as_ref())?;
    plan_from_header(&header, archive_len, password.as_ref())
}

/// 7z başlangıç ve next-header CRC'lerini doğrular; plain başlığı doğrudan,
/// encoded başlığı ise standartta tanımlanan StreamsInfo üzerinden çözer.
/// Encoded-header `PackPos` tabanı her zaman 32 baytlık signature header'ın
/// sonudur; next-header'ın dosyadaki konumu bu hesaba karıştırılmaz.
fn read_standard_archive_header<R: Read + Seek>(
    reader: &mut R,
    archive_len: u64,
    limits: &ResourceLimits,
    password: Option<&Password>,
) -> Result<ArchiveHeader, SevenZipError> {
    reader.seek(SeekFrom::Start(0))?;
    let start_header =
        StartHeader::parse(reader).map_err(|error| SevenZipError::Header(error.to_string()))?;

    if start_header.next_header_size == 0 {
        return Ok(ArchiveHeader::default());
    }
    if start_header.next_header_size > limits.max_header_bytes {
        return Err(SevenZipError::InvalidLayout(format!(
            "next header {} bayt; güvenli başlık sınırı {} bayt",
            start_header.next_header_size, limits.max_header_bytes
        )));
    }

    let header_position = start_header.next_header_position();
    let header_end = header_position
        .checked_add(start_header.next_header_size)
        .ok_or_else(|| SevenZipError::InvalidLayout("next header sonu taştı".into()))?;
    if header_end > archive_len {
        return Err(SevenZipError::InvalidLayout(
            "next header mevcut 7z ciltlerinin dışında; set eksik".into(),
        ));
    }

    let header_size = usize::try_from(start_header.next_header_size)
        .map_err(|_| SevenZipError::InvalidLayout("next header belleğe sığmıyor".into()))?;
    reader.seek(SeekFrom::Start(header_position))?;
    let mut header_data = vec![0u8; header_size];
    reader.read_exact(&mut header_data)?;
    verify_header_crc("next header", &header_data, start_header.next_header_crc)?;

    let marker = header_data
        .first()
        .copied()
        .ok_or_else(|| SevenZipError::InvalidLayout("7z next header verisi boş".into()))?;
    match marker {
        property_id::HEADER => {
            let mut parser = HeaderParser::with_limits(limits.clone());
            parser
                .parse_header(&mut Cursor::new(header_data))
                .map_err(|error| SevenZipError::Header(error.to_string()))
        }
        property_id::ENCODED_HEADER => {
            let mut cursor = Cursor::new(&header_data[1..]);
            let streams = parse_encoded_streams_info(&mut cursor, limits)?;
            let header_encrypted = streams.unpack_info.as_ref().is_some_and(|info| {
                info.folders.iter().any(|folder| {
                    folder
                        .coders
                        .iter()
                        .any(|coder| coder.method_id.as_slice() == method::AES)
                })
            });
            let decoded = decode_encoded_header(reader, archive_len, &streams, limits, password)?;
            if decoded.first().copied() != Some(property_id::HEADER) {
                return Err(SevenZipError::InvalidLayout(
                    "çözülen 7z başlığı HEADER işaretçisiyle başlamıyor".into(),
                ));
            }

            let mut parser = HeaderParser::with_limits(limits.clone());
            let mut header = parser
                .parse_header(&mut Cursor::new(decoded))
                .map_err(|error| SevenZipError::Header(error.to_string()))?;
            header.header_encrypted = header_encrypted;
            Ok(header)
        }
        other => Err(SevenZipError::InvalidLayout(format!(
            "tanınmayan 7z başlık işaretçisi: {other:#x}"
        ))),
    }
}

/// ENCODED_HEADER işaretçisinden sonra gelen standart StreamsInfo yapısını,
/// `zesven`in herkese açık ve sınır kontrollü parçalarıyla okur.
fn parse_encoded_streams_info<R: Read>(
    reader: &mut R,
    limits: &ResourceLimits,
) -> Result<ArchiveHeader, SevenZipError> {
    let mut streams = ArchiveHeader::default();
    loop {
        match read_u8(reader)? {
            property_id::END => break,
            property_id::PACK_INFO => {
                if streams.pack_info.is_some() {
                    return Err(SevenZipError::InvalidLayout(
                        "encoded header birden fazla PackInfo içeriyor".into(),
                    ));
                }
                streams.pack_info = Some(
                    PackInfo::parse(reader, limits)
                        .map_err(|error| SevenZipError::Header(error.to_string()))?,
                );
            }
            property_id::UNPACK_INFO => {
                if streams.unpack_info.is_some() {
                    return Err(SevenZipError::InvalidLayout(
                        "encoded header birden fazla UnpackInfo içeriyor".into(),
                    ));
                }
                streams.unpack_info = Some(
                    UnpackInfo::parse(reader, limits)
                        .map_err(|error| SevenZipError::Header(error.to_string()))?,
                );
            }
            property_id::SUBSTREAMS_INFO => {
                if streams.substreams_info.is_some() {
                    return Err(SevenZipError::InvalidLayout(
                        "encoded header birden fazla SubStreamsInfo içeriyor".into(),
                    ));
                }
                let folders = streams
                    .unpack_info
                    .as_ref()
                    .ok_or_else(|| {
                        SevenZipError::InvalidLayout(
                            "SubStreamsInfo, UnpackInfo'dan önce geldi".into(),
                        )
                    })?
                    .folders
                    .as_slice();
                streams.substreams_info = Some(
                    SubStreamsInfo::parse(reader, folders, limits)
                        .map_err(|error| SevenZipError::Header(error.to_string()))?,
                );
            }
            other => {
                return Err(SevenZipError::InvalidLayout(format!(
                    "encoded header StreamsInfo içinde tanınmayan özellik: {other:#x}"
                )));
            }
        }
    }
    Ok(streams)
}

type HeaderDecoder = Box<dyn Read + Send>;

fn decode_encoded_header<R: Read + Seek>(
    reader: &mut R,
    archive_len: u64,
    streams: &ArchiveHeader,
    limits: &ResourceLimits,
    password: Option<&Password>,
) -> Result<Vec<u8>, SevenZipError> {
    let pack_info = streams
        .pack_info
        .as_ref()
        .ok_or_else(|| SevenZipError::InvalidLayout("encoded header PackInfo içermiyor".into()))?;
    let unpack_info = streams.unpack_info.as_ref().ok_or_else(|| {
        SevenZipError::InvalidLayout("encoded header UnpackInfo içermiyor".into())
    })?;
    if pack_info.pack_sizes.len() != 1 || unpack_info.folders.len() != 1 {
        return Err(SevenZipError::InvalidLayout(
            "encoded header yalnız tek folder ve tek pack stream ile destekleniyor".into(),
        ));
    }

    let folder = &unpack_info.folders[0];
    let coder_order = simple_coder_order(folder)?;
    if folder.unpack_sizes.len() != folder.coders.len() {
        return Err(SevenZipError::InvalidLayout(format!(
            "encoded header {} coder için {} unpack boyutu taşıyor",
            folder.coders.len(),
            folder.unpack_sizes.len()
        )));
    }

    if let Some(substreams) = streams.substreams_info.as_ref() {
        if substreams.num_unpack_streams_in_folders.as_slice() != [1] {
            return Err(SevenZipError::InvalidLayout(
                "encoded header birden fazla unpack substream içeriyor".into(),
            ));
        }
    }

    let pack_size = pack_info.pack_sizes[0];
    if pack_size > limits.max_header_bytes {
        return Err(SevenZipError::InvalidLayout(format!(
            "encoded header pack stream'i {pack_size} bayt; güvenli başlık sınırı {} bayt",
            limits.max_header_bytes
        )));
    }
    let pack_start = SIGNATURE_HEADER_SIZE
        .checked_add(pack_info.pack_pos)
        .ok_or_else(|| SevenZipError::InvalidLayout("encoded header pack ofseti taştı".into()))?;
    let pack_end = pack_start
        .checked_add(pack_size)
        .ok_or_else(|| SevenZipError::InvalidLayout("encoded header pack sonu taştı".into()))?;
    if pack_end > archive_len {
        return Err(SevenZipError::InvalidLayout(
            "encoded header pack aralığı mevcut 7z ciltlerinin dışında; set eksik".into(),
        ));
    }

    let pack_len = usize::try_from(pack_size)
        .map_err(|_| SevenZipError::InvalidLayout("encoded header pack belleğe sığmıyor".into()))?;
    reader.seek(SeekFrom::Start(pack_start))?;
    let mut packed = vec![0u8; pack_len];
    reader.read_exact(&mut packed)?;
    if let Some(expected_crc) = pack_info.pack_crcs.first().copied().flatten() {
        verify_header_crc("encoded header pack stream", &packed, expected_crc)?;
    }

    let mut decoder: HeaderDecoder = Box::new(Cursor::new(packed));
    for &coder_index in &coder_order {
        let coder = &folder.coders[coder_index];
        let decoded_size = folder.unpack_sizes[coder_index];
        if decoded_size > limits.max_header_bytes {
            return Err(SevenZipError::InvalidLayout(format!(
                "encoded header coder çıktısı {decoded_size} bayt; güvenli başlık sınırı {} bayt",
                limits.max_header_bytes
            )));
        }
        let properties = coder.properties.as_deref().unwrap_or_default();
        decoder = match coder.method_id.as_slice() {
            method::COPY => Box::new(CopyDecoder::new(decoder, decoded_size)),
            method::AES => {
                let password = password.ok_or(SevenZipError::MissingPassword)?;
                let aes = Aes256Decoder::new(decoder, properties, password)
                    .map_err(|error| SevenZipError::Header(error.to_string()))?;
                Box::new(aes.take(decoded_size))
            }
            method::LZMA => Box::new(
                LzmaDecoder::new(decoder, properties, decoded_size)
                    .map_err(|error| SevenZipError::Header(error.to_string()))?,
            ),
            method::LZMA2 => Box::new(
                Lzma2Decoder::new(decoder, properties)
                    .map_err(|error| SevenZipError::Header(error.to_string()))?
                    .take(decoded_size),
            ),
            unsupported => {
                return Err(SevenZipError::InvalidLayout(format!(
                    "encoded header desteklenmeyen coder içeriyor: {}",
                    method::name(unsupported)
                )));
            }
        };
    }

    let final_coder = *coder_order
        .last()
        .ok_or_else(|| SevenZipError::InvalidLayout("encoded header coder zinciri boş".into()))?;
    let expected_size = folder.unpack_sizes[final_coder];
    let capacity = usize::try_from(expected_size)
        .map_err(|_| SevenZipError::InvalidLayout("çözülen başlık belleğe sığmıyor".into()))?;
    let mut decoded = Vec::with_capacity(capacity);
    decoder.read_to_end(&mut decoded)?;
    if decoded.len() as u64 != expected_size {
        return Err(SevenZipError::InvalidLayout(format!(
            "çözülen başlık {} bayt, beklenen {expected_size} bayt",
            decoded.len()
        )));
    }

    if let Some(expected_crc) = folder.unpack_crc {
        verify_header_crc("çözülen encoded header", &decoded, expected_crc)?;
    }
    if let Some(expected_crc) = streams
        .substreams_info
        .as_ref()
        .and_then(|info| info.digests.first())
        .copied()
        .flatten()
    {
        verify_header_crc("çözülen encoded header substream", &decoded, expected_crc)?;
    }
    Ok(decoded)
}

/// Tek giriş/tek çıkışlı coder'ları bind-pair yönünde, pack stream'den nihai
/// çıktıya doğru sıralar. Liste sırasına güvenilmez; örneğin `[COPY, AES]`
/// tanımı gerçek veri akışında önce AES, sonra COPY olabilir.
fn simple_coder_order(folder: &Folder) -> Result<Vec<usize>, SevenZipError> {
    if folder.coders.is_empty() {
        return Err(SevenZipError::InvalidLayout(
            "encoded header coder zinciri boş".into(),
        ));
    }
    if folder
        .coders
        .iter()
        .any(|coder| coder.num_in_streams != 1 || coder.num_out_streams != 1)
    {
        return Err(SevenZipError::InvalidLayout(
            "encoded header yalnız tek giriş/tek çıkışlı coder zincirlerini destekliyor".into(),
        ));
    }
    if folder.packed_streams.len() != 1 || folder.bind_pairs.len() + 1 != folder.coders.len() {
        return Err(SevenZipError::InvalidLayout(
            "encoded header coder graph'ı basit bir zincir değil".into(),
        ));
    }

    let coder_count = folder.coders.len();
    let mut incoming_bound = vec![false; coder_count];
    let mut outgoing_bound = vec![false; coder_count];
    let mut next_input = vec![None; coder_count];
    for pair in &folder.bind_pairs {
        let input = usize::try_from(pair.in_index)
            .ok()
            .filter(|&index| index < coder_count)
            .ok_or_else(|| {
                SevenZipError::InvalidLayout("encoded header bind input indeksi geçersiz".into())
            })?;
        let output = usize::try_from(pair.out_index)
            .ok()
            .filter(|&index| index < coder_count)
            .ok_or_else(|| {
                SevenZipError::InvalidLayout("encoded header bind output indeksi geçersiz".into())
            })?;
        if incoming_bound[input] || outgoing_bound[output] {
            return Err(SevenZipError::InvalidLayout(
                "encoded header coder graph'ında yinelenen bind stream'i var".into(),
            ));
        }
        incoming_bound[input] = true;
        outgoing_bound[output] = true;
        next_input[output] = Some(input);
    }

    let mut current = usize::try_from(folder.packed_streams[0])
        .ok()
        .filter(|&index| index < coder_count)
        .ok_or_else(|| {
            SevenZipError::InvalidLayout("encoded header packed stream indeksi geçersiz".into())
        })?;
    if incoming_bound[current] {
        return Err(SevenZipError::InvalidLayout(
            "encoded header packed stream'i aynı zamanda bind girdisi".into(),
        ));
    }

    let mut visited = vec![false; coder_count];
    let mut order = Vec::with_capacity(coder_count);
    loop {
        if visited[current] {
            return Err(SevenZipError::InvalidLayout(
                "encoded header coder graph'ında döngü var".into(),
            ));
        }
        visited[current] = true;
        order.push(current);
        match next_input[current] {
            Some(next) => current = next,
            None => break,
        }
    }
    if order.len() != coder_count {
        return Err(SevenZipError::InvalidLayout(
            "encoded header coder graph'ı bağlantısız".into(),
        ));
    }
    Ok(order)
}

fn verify_header_crc(label: &str, data: &[u8], expected_crc: u32) -> Result<(), SevenZipError> {
    let actual_crc = crc32fast::hash(data);
    if actual_crc != expected_crc {
        return Err(SevenZipError::Header(format!(
            "{label} CRC uyuşmazlığı: beklenen {expected_crc:#x}, bulunan {actual_crc:#x}"
        )));
    }
    Ok(())
}

/// Tam başlığı (ve gerekirse şifreli başlık stream'lerini) çözmeden önce,
/// start header'ın işaret ettiği son baytın mevcut ciltlerde bulunduğunu
/// doğrular. Böylece eksik setler parser'ın anlamsız bir uzak seek hatasına
/// dönüşmeden, yalnız güvenli boyut bilgileriyle reddedilir.
fn preflight_archive_size<R: Read + Seek>(
    reader: &mut R,
    archive_len: u64,
) -> Result<(), SevenZipError> {
    reader.seek(SeekFrom::Start(0))?;
    let start_header =
        StartHeader::parse(reader).map_err(|error| SevenZipError::Header(error.to_string()))?;
    let required_len = SIGNATURE_HEADER_SIZE
        .checked_add(start_header.next_header_offset)
        .and_then(|value| value.checked_add(start_header.next_header_size))
        .ok_or_else(|| SevenZipError::InvalidLayout("7z başlığındaki toplam boyut taştı".into()))?;

    if required_len > archive_len {
        return Err(SevenZipError::InvalidLayout(format!(
            "7z başlığı {required_len} baytlık fiziksel arşiv bekliyor, NZB ciltleri yalnız {archive_len} bayt sağlıyor; set eksik"
        )));
    }

    reader.seek(SeekFrom::Start(0))?;
    Ok(())
}

fn plan_from_header(
    header: &ArchiveHeader,
    archive_len: u64,
    password: Option<&Password>,
) -> Result<EntryPlan, SevenZipError> {
    let pack_info = header
        .pack_info
        .as_ref()
        .ok_or_else(|| SevenZipError::InvalidLayout("PackInfo yok".into()))?;
    let folders = &header
        .unpack_info
        .as_ref()
        .ok_or_else(|| SevenZipError::InvalidLayout("UnpackInfo yok".into()))?
        .folders;
    let entries = &header
        .files_info
        .as_ref()
        .ok_or_else(|| SevenZipError::InvalidLayout("FilesInfo yok".into()))?
        .entries;

    let streams_per_folder = header
        .substreams_info
        .as_ref()
        .map(|info| info.num_unpack_streams_in_folders.clone())
        .unwrap_or_else(|| vec![1; folders.len()]);
    if streams_per_folder.len() != folders.len() {
        return Err(SevenZipError::InvalidLayout(
            "folder/substream sayısı uyuşmuyor".into(),
        ));
    }

    // FilesInfo'daki stream sırasını folder sırasına bağla ve en büyük medya
    // girdisini seç. Dizinler/boş dosyalar stream tüketmez.
    let mut folder_index = 0usize;
    let mut remaining_in_folder = streams_per_folder.first().copied().unwrap_or(0);
    let mut selected: Option<(&zesven::format::files::ArchiveEntry, usize)> = None;
    for entry in entries.iter().filter(|entry| entry.has_stream) {
        while folder_index < folders.len() && remaining_in_folder == 0 {
            folder_index += 1;
            remaining_in_folder = streams_per_folder.get(folder_index).copied().unwrap_or(0);
        }
        if folder_index >= folders.len() {
            return Err(SevenZipError::InvalidLayout(
                "dosya stream'i için folder bulunamadı".into(),
            ));
        }

        if is_playable_media_filename(&entry.name)
            && selected.is_none_or(|(current, _)| entry.size > current.size)
        {
            selected = Some((entry, folder_index));
        }
        remaining_in_folder -= 1;
    }

    let (entry, folder_index) = selected.ok_or(SevenZipError::NoPlayableMedia)?;
    if streams_per_folder[folder_index] != 1 {
        return Err(SevenZipError::SolidArchive);
    }

    let folder = &folders[folder_index];
    if folder.packed_streams.len() != 1 {
        return Err(SevenZipError::UnsupportedCompression);
    }
    // Medya verisinde de yalnız tek giriş/çıkışlı, bağlantılı bir coder zinciri
    // kabul edilir. Yalnız method adına bakmak; bozuk bind graph'ı veya iki kez
    // AES uygulayan bir arşivi yanlışlıkla tek decrypt ile sunabilirdi.
    simple_coder_order(folder)?;
    let aes_count = folder
        .coders
        .iter()
        .filter(|coder| coder.method_id.as_slice() == method::AES)
        .count();
    if folder.coders.is_empty()
        || aes_count > 1
        || folder.coders.iter().any(|coder| {
            coder.method_id.as_slice() != method::COPY && coder.method_id.as_slice() != method::AES
        })
    {
        return Err(SevenZipError::UnsupportedCompression);
    }

    let pack_index = folders[..folder_index]
        .iter()
        .try_fold(0usize, |total, folder| {
            total.checked_add(folder.packed_streams.len())
        })
        .ok_or_else(|| SevenZipError::InvalidLayout("pack stream indeksi taştı".into()))?;
    let packed_size = *pack_info
        .pack_sizes
        .get(pack_index)
        .ok_or_else(|| SevenZipError::InvalidLayout("medya pack stream boyutu yok".into()))?;
    let previous_sizes = pack_info
        .pack_sizes
        .get(..pack_index)
        .ok_or_else(|| SevenZipError::InvalidLayout("önceki pack stream'leri yok".into()))?;
    let previous_packed = checked_pack_sum(previous_sizes)?;
    let packed_start = SIGNATURE_HEADER_SIZE
        .checked_add(pack_info.pack_pos)
        .and_then(|value| value.checked_add(previous_packed))
        .ok_or_else(|| SevenZipError::InvalidLayout("pack ofseti taştı".into()))?;
    let packed_end = packed_start
        .checked_add(packed_size)
        .ok_or_else(|| SevenZipError::InvalidLayout("pack sonu taştı".into()))?;
    if packed_end > archive_len {
        return Err(SevenZipError::InvalidLayout(
            "medya pack aralığı mevcut 7z ciltlerinin dışında; set eksik".into(),
        ));
    }

    let aes = if aes_count == 1 {
        let password = password.ok_or(SevenZipError::MissingPassword)?;
        let coder = folder
            .coders
            .iter()
            .find(|coder| coder.method_id.as_slice() == method::AES)
            .expect("AES coder bulundu");
        let properties = coder
            .properties
            .as_deref()
            .ok_or_else(|| SevenZipError::InvalidLayout("AES coder özellikleri yok".into()))?;
        let properties = AesProperties::parse(properties)
            .map_err(|error| SevenZipError::Header(error.to_string()))?;
        let expected_packed = aes_packed_size(entry.size)?;
        if packed_size != expected_packed {
            return Err(SevenZipError::InvalidLayout(format!(
                "AES pack boyutu {packed_size}, beklenen STORE boyutu {expected_packed}"
            )));
        }
        let key = derive_key(password, &properties.salt, properties.num_cycles_power)
            .map_err(|error| SevenZipError::Header(error.to_string()))?;
        let iv: [u8; 16] = properties
            .iv
            .try_into()
            .map_err(|_| SevenZipError::InvalidLayout("AES IV boyutu 16 değil".into()))?;
        Some(AesPlan {
            key: Zeroizing::new(key),
            iv,
        })
    } else {
        if packed_size != entry.size {
            return Err(SevenZipError::InvalidLayout(format!(
                "COPY pack boyutu {packed_size}, medya boyutu {}",
                entry.size
            )));
        }
        None
    };

    Ok(EntryPlan {
        filename: entry.name.clone(),
        decoded_size: entry.size,
        packed_range: packed_start..packed_end,
        aes,
    })
}

fn decrypt_blocks(key: &[u8; 32], iv: &[u8; 16], ciphertext: &mut [u8]) -> io::Result<()> {
    if !ciphertext.len().is_multiple_of(AES_BLOCK_SIZE as usize) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "AES ciphertext 16 bayt hizalı değil",
        ));
    }
    Aes256CbcDec::new_from_slices(key, iv)
        .map_err(|_| io::Error::other("AES key/IV boyutu geçersiz"))?
        .decrypt_padded_mut::<NoPadding>(ciphertext)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "AES çözme başarısız"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use cbc::cipher::{BlockEncryptMut, KeyIvInit};
    use std::io::Cursor;
    use zesven::format::files::{ArchiveEntry, FilesInfo};
    use zesven::format::streams::{BindPair, Coder, Folder, PackInfo, SubStreamsInfo, UnpackInfo};
    use zesven::format::SIGNATURE;

    type Aes256CbcEnc = cbc::Encryptor<Aes256>;

    fn header_with(method_id: &[u8], properties: Option<Vec<u8>>, size: u64) -> ArchiveHeader {
        ArchiveHeader {
            pack_info: Some(PackInfo {
                pack_pos: 100,
                pack_sizes: vec![size],
                pack_crcs: vec![None],
            }),
            unpack_info: Some(UnpackInfo {
                folders: vec![Folder {
                    coders: vec![Coder {
                        method_id: method_id.to_vec(),
                        num_in_streams: 1,
                        num_out_streams: 1,
                        properties,
                    }],
                    bind_pairs: vec![],
                    packed_streams: vec![0],
                    unpack_sizes: vec![size],
                    unpack_crc: None,
                }],
            }),
            substreams_info: Some(SubStreamsInfo {
                num_unpack_streams_in_folders: vec![1],
                unpack_sizes: vec![size],
                digests: vec![None],
            }),
            files_info: Some(FilesInfo {
                entries: vec![ArchiveEntry {
                    name: "movie.mkv".into(),
                    is_directory: false,
                    is_anti: false,
                    has_stream: true,
                    size,
                    crc: None,
                    ctime: None,
                    atime: None,
                    mtime: None,
                    attributes: None,
                }],
                comment: None,
            }),
            header_encrypted: false,
        }
    }

    #[test]
    fn copy_medya_pack_araligina_eslenir() {
        let header = header_with(method::COPY, None, 32);
        let plan = plan_from_header(&header, 200, None).unwrap();
        assert_eq!(plan.filename, "movie.mkv");
        assert_eq!(plan.decoded_size, 32);
        assert_eq!(plan.packed_range, 132..164);
        assert!(plan.aes.is_none());
    }

    #[test]
    fn sikistirilmis_7z_reddedilir() {
        let header = header_with(method::LZMA2, Some(vec![0]), 32);
        assert!(matches!(
            plan_from_header(&header, 200, None),
            Err(SevenZipError::UnsupportedCompression)
        ));
    }

    #[test]
    fn medya_coder_zincirinde_ikinci_aes_reddedilir() {
        let mut header = header_with(method::AES, Some(vec![0, 0]), 32);
        let folder = &mut header.unpack_info.as_mut().unwrap().folders[0];
        folder.coders.push(Coder {
            method_id: method::AES.to_vec(),
            num_in_streams: 1,
            num_out_streams: 1,
            properties: Some(vec![0, 0]),
        });
        folder.bind_pairs.push(BindPair {
            in_index: 1,
            out_index: 0,
        });
        folder.unpack_sizes.push(32);

        assert!(matches!(
            plan_from_header(&header, 200, Some(&Password::new("placeholder"))),
            Err(SevenZipError::UnsupportedCompression)
        ));
    }

    #[test]
    fn medya_coder_graphinda_gecersiz_pack_indeksi_reddedilir() {
        let mut header = header_with(method::COPY, None, 32);
        header.unpack_info.as_mut().unwrap().folders[0].packed_streams = vec![1];

        assert!(matches!(
            plan_from_header(&header, 200, None),
            Err(SevenZipError::InvalidLayout(_))
        ));
    }

    #[test]
    fn cilt_sayisi_bos_ve_asiri_setleri_reddeder() {
        assert!(validate_volume_count(140).is_ok());
        assert!(matches!(
            validate_volume_count(0),
            Err(SevenZipError::InvalidLayout(_))
        ));
        assert!(matches!(
            validate_volume_count(MAX_ARCHIVE_VOLUMES + 1),
            Err(SevenZipError::InvalidLayout(_))
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
                Ok::<_, SevenZipError>(item)
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
                    std::future::pending::<Result<(), SevenZipError>>().await
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
        assert!(matches!(result, Err(SevenZipError::Cancelled)));
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
                Err::<(), _>(SevenZipError::Cancelled)
            },
        ));

        started_rx.await.unwrap();
        cancel_tx.send(true).unwrap();
        let result = tokio::time::timeout(std::time::Duration::from_secs(1), task)
            .await
            .expect("blocking parser cooperative olarak kapanmalı")
            .unwrap();
        assert!(matches!(result, Err(SevenZipError::Cancelled)));
        assert!(
            finished.load(Ordering::SeqCst),
            "outer future blocking parser bitmeden dönmemeli"
        );
    }

    #[test]
    fn pack_boyut_toplami_ve_aes_hizalama_tasmasi_reddedilir() {
        assert_eq!(checked_pack_sum(&[10, 20, 30]).unwrap(), 60);
        assert!(matches!(
            checked_pack_sum(&[u64::MAX, 1]),
            Err(SevenZipError::InvalidLayout(_))
        ));
        assert_eq!(aes_packed_size(17).unwrap(), 32);
        assert!(matches!(
            aes_packed_size(u64::MAX),
            Err(SevenZipError::InvalidLayout(_))
        ));
    }

    #[test]
    fn start_header_eksik_cilt_setini_parserdan_once_reddeder() {
        let next_header_offset = 100u64;
        let next_header_size = 40u64;
        let mut header_data = Vec::with_capacity(20);
        header_data.extend_from_slice(&next_header_offset.to_le_bytes());
        header_data.extend_from_slice(&next_header_size.to_le_bytes());
        header_data.extend_from_slice(&0u32.to_le_bytes());

        let mut bytes = Vec::with_capacity(SIGNATURE_HEADER_SIZE as usize);
        bytes.extend_from_slice(SIGNATURE);
        bytes.extend_from_slice(&[0, 4]);
        bytes.extend_from_slice(&crc32fast::hash(&header_data).to_le_bytes());
        bytes.extend_from_slice(&header_data);

        let error = preflight_archive_size(&mut Cursor::new(bytes), 140).unwrap_err();
        assert_eq!(
            error.to_string(),
            "geçersiz 7z yerleşimi: 7z başlığı 172 baytlık fiziksel arşiv bekliyor, NZB ciltleri yalnız 140 bayt sağlıyor; set eksik"
        );
    }

    #[test]
    fn encrypted_header_coder_sirasi_bind_graphindan_cikarilir() {
        let folder = Folder {
            // 7z coder listesi decode sırası değildir: packed stream AES'e
            // girer, AES çıktısı COPY girdisine bağlanır.
            coders: vec![
                Coder {
                    method_id: method::COPY.to_vec(),
                    num_in_streams: 1,
                    num_out_streams: 1,
                    properties: None,
                },
                Coder {
                    method_id: method::AES.to_vec(),
                    num_in_streams: 1,
                    num_out_streams: 1,
                    properties: Some(vec![0, 0]),
                },
            ],
            bind_pairs: vec![BindPair {
                in_index: 0,
                out_index: 1,
            }],
            packed_streams: vec![1],
            unpack_sizes: vec![2, 16],
            unpack_crc: None,
        };

        assert_eq!(simple_coder_order(&folder).unwrap(), vec![1, 0]);
    }

    #[test]
    fn baglantisiz_encoded_header_coder_graphi_reddedilir() {
        let folder = Folder {
            coders: vec![
                Coder {
                    method_id: method::COPY.to_vec(),
                    num_in_streams: 1,
                    num_out_streams: 1,
                    properties: None,
                },
                Coder {
                    method_id: method::COPY.to_vec(),
                    num_in_streams: 1,
                    num_out_streams: 1,
                    properties: None,
                },
            ],
            bind_pairs: vec![BindPair {
                in_index: 0,
                out_index: 0,
            }],
            packed_streams: vec![1],
            unpack_sizes: vec![2, 2],
            unpack_crc: None,
        };

        assert!(matches!(
            simple_coder_order(&folder),
            Err(SevenZipError::InvalidLayout(_))
        ));
    }

    #[test]
    fn encoded_header_pack_ofseti_signature_header_sonundan_hesaplanir() {
        let decoded = vec![property_id::HEADER, property_id::END];
        let pack_pos = 5u64;
        let pack_start = (SIGNATURE_HEADER_SIZE + pack_pos) as usize;
        let mut archive = vec![0xA5; pack_start + decoded.len()];
        archive[pack_start..].copy_from_slice(&decoded);

        let streams = ArchiveHeader {
            pack_info: Some(PackInfo {
                pack_pos,
                pack_sizes: vec![decoded.len() as u64],
                pack_crcs: vec![Some(crc32fast::hash(&decoded))],
            }),
            unpack_info: Some(UnpackInfo {
                folders: vec![Folder {
                    coders: vec![Coder {
                        method_id: method::COPY.to_vec(),
                        num_in_streams: 1,
                        num_out_streams: 1,
                        properties: None,
                    }],
                    bind_pairs: vec![],
                    packed_streams: vec![0],
                    unpack_sizes: vec![decoded.len() as u64],
                    unpack_crc: Some(crc32fast::hash(&decoded)),
                }],
            }),
            substreams_info: None,
            files_info: None,
            header_encrypted: false,
        };
        let archive_len = archive.len() as u64;

        let actual = decode_encoded_header(
            &mut Cursor::new(archive),
            archive_len,
            &streams,
            &ResourceLimits::default(),
            None,
        )
        .unwrap();
        assert_eq!(actual, decoded);
    }

    #[test]
    fn plain_next_header_crc_dogrulanir() {
        let next_header = [property_id::HEADER, property_id::END];
        let mut descriptor = Vec::with_capacity(20);
        descriptor.extend_from_slice(&0u64.to_le_bytes());
        descriptor.extend_from_slice(&(next_header.len() as u64).to_le_bytes());
        descriptor.extend_from_slice(&0xDEAD_BEEFu32.to_le_bytes());

        let mut archive = Vec::new();
        archive.extend_from_slice(SIGNATURE);
        archive.extend_from_slice(&[0, 4]);
        archive.extend_from_slice(&crc32fast::hash(&descriptor).to_le_bytes());
        archive.extend_from_slice(&descriptor);
        archive.extend_from_slice(&next_header);
        let archive_len = archive.len() as u64;

        assert!(matches!(
            read_standard_archive_header(
                &mut Cursor::new(archive),
                archive_len,
                &ResourceLimits::default(),
                None,
            ),
            Err(SevenZipError::Header(message)) if message.contains("next header CRC")
        ));
    }

    #[test]
    fn aes_bloklari_seek_edilebilir_bicimde_cozulur() {
        let key = [7u8; 32];
        let iv = [11u8; 16];
        let plaintext = *b"0123456789ABCDEFfedcba9876543210";
        let mut ciphertext = plaintext;
        Aes256CbcEnc::new_from_slices(&key, &iv)
            .unwrap()
            .encrypt_padded_mut::<NoPadding>(&mut ciphertext, plaintext.len())
            .unwrap();

        decrypt_blocks(&key, &iv, &mut ciphertext).unwrap();
        assert_eq!(ciphertext, plaintext);
    }
}
