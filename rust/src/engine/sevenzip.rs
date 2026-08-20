//! Çok ciltli 7z yayınlarını sanal, seek edilebilir medya dosyasına
//! dönüştürür.
//!
//! 7z ciltleri diske indirilmez. Her `.7z.NNN` dosyası mevcut NNTP+yEnc
//! kaynağıyla açılır, tek bir sanal byte uzayında birleştirilir ve yalnız 7z
//! başlığının istediği aralıklar çekilir. İçerideki medya girdisi COPY/STORE
//! ise pack aralığı doğrudan sunulur; AES-256-CBC varsa istenen bloklar yerinde
//! çözülür. LZMA/LZMA2 (ve solid folder) girdileri ise
//! [`SeekableDecodeSource`] cephesiyle sunulur: decoder pack akışını baştan
//! sırayla çözer, pencere önbelleği yakın geriye okumaları karşılar, uzak
//! geriye sıçramalarda zincir baştan kurulur. BCJ/PPMd gibi codec'ler ve
//! çok-pack'li folder'lar açıkça reddedilir.

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

use super::archive::{
    cancellation_requested, run_blocking_cancellable, validate_range, BlockingArchiveReader,
    BlockingTaskError, NntpVolumeSet, VolumeSetError,
};
use super::nntp::{NntpPool, TlsNntpConnector};
use super::nzb::{is_playable_media_filename, NzbFile};
use super::seekable_decode::SeekableDecodeSource;
use super::server::{content_type_for, RangeSource};

const AES_STREAM_CHUNK: u64 = 1024 * 1024;
const AES_BLOCK_SIZE: u64 = 16;

type Aes256CbcDec = cbc::Decryptor<Aes256>;

#[derive(Debug, Error)]
pub enum SevenZipError {
    #[error("could not prepare 7z volumes: {0}")]
    Io(#[from] io::Error),
    #[error("could not read 7z header: {0}")]
    Header(String),
    #[error("no playable media file in the 7z archive")]
    NoPlayableMedia,
    #[error("7z archive uses an unsupported codec/layout (BCJ, PPMd, multi-pack folder, etc.); COPY, AES, LZMA and LZMA2 are supported")]
    UnsupportedCompression,
    #[error("password-protected 7z archive but the NZB has no password metadata")]
    MissingPassword,
    #[error("invalid 7z layout: {0}")]
    InvalidLayout(String),
    #[error("7z prepare task failed to complete: {0}")]
    Task(String),
    #[error("7z preparation cancelled")]
    Cancelled,
}

impl From<VolumeSetError> for SevenZipError {
    fn from(error: VolumeSetError) -> Self {
        match error {
            VolumeSetError::Io(error) => Self::Io(error),
            VolumeSetError::InvalidLayout(message) => Self::InvalidLayout(message),
            VolumeSetError::Cancelled => Self::Cancelled,
        }
    }
}

impl From<BlockingTaskError> for SevenZipError {
    fn from(error: BlockingTaskError) -> Self {
        match error {
            BlockingTaskError::Task(message) => Self::Task(message),
            BlockingTaskError::Cancelled => Self::Cancelled,
        }
    }
}

fn ensure_not_cancelled(cancellation: &watch::Receiver<bool>) -> Result<(), SevenZipError> {
    if cancellation_requested(cancellation) {
        Err(SevenZipError::Cancelled)
    } else {
        Ok(())
    }
}

fn checked_pack_sum(values: &[u64]) -> Result<u64, SevenZipError> {
    values.iter().try_fold(0u64, |total, &value| {
        total
            .checked_add(value)
            .ok_or_else(|| SevenZipError::InvalidLayout("pack size total overflow".into()))
    })
}

fn aes_packed_size(decoded_size: u64) -> Result<u64, SevenZipError> {
    decoded_size
        .div_ceil(AES_BLOCK_SIZE)
        .checked_mul(AES_BLOCK_SIZE)
        .ok_or_else(|| SevenZipError::InvalidLayout("AES pack size overflow".into()))
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
    packing: PackingPlan,
}

/// Medya verisinin sunuluş biçimi.
enum PackingPlan {
    /// COPY veya AES-STORE: pack aralığı doğrudan (veya blok-blok çözülerek)
    /// seek edilebilir — mevcut hızlı yol.
    Direct,
    /// LZMA/LZMA2 (+ isteğe bağlı AES) zinciri: ardışıl çözüm gerekir,
    /// [`SeekableDecodeSource`] cephesiyle sunulur.
    Compressed(CompressedPlan),
}

struct CompressedPlan {
    /// [`simple_coder_order`] sırasıyla coder adımları.
    steps: Vec<CoderStep>,
    /// Solid folder'da seçilen dosyadan önce çözülüp atılacak bayt sayısı.
    prefix_skip: u64,
    /// Zincirde AES adımı varsa gerekli (doğrulama [`plan_from_header`]).
    password: Option<Password>,
}

#[derive(Clone)]
struct CoderStep {
    method_id: Vec<u8>,
    properties: Vec<u8>,
    unpack_size: u64,
}

/// Oynatıcıya doğrudan medya dosyası gibi görünen 7z içeriği.
pub struct SevenZipEntrySource {
    archive: Arc<NntpVolumeSet>,
    plan: EntryPlan,
    content_type: &'static str,
    /// Sıkıştırılmış zincirlerde ardışıl çözüm cephesi; STORE yollarında None.
    facade: Option<SeekableDecodeSource>,
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

        let plan = run_blocking_cancellable(cancellation.clone(), move |reader_cancellation| {
            let mut reader =
                BlockingArchiveReader::new(archive_for_parser, runtime, reader_cancellation);
            parse_entry_plan(&mut reader, archive_len, password)
        })
        .await?;

        let content_type = content_type_for(&plan.filename);
        let facade = match &plan.packing {
            PackingPlan::Direct => None,
            PackingPlan::Compressed(compressed) => Some(build_decode_facade(
                &archive,
                &plan,
                compressed,
                cancellation,
            )),
        };
        Ok(Self {
            archive,
            plan,
            content_type,
            facade,
        })
    }

    pub fn filename(&self) -> &str {
        &self.plan.filename
    }

    pub fn segment_count(&self) -> usize {
        self.archive.segment_count()
    }

    /// PAR2 onarım katmanını cilt kümesine dağıtır.
    pub fn set_overlays(&self, overlay: &crate::engine::repair::RepairOverlay) {
        self.archive.set_overlays(overlay);
    }

    /// Medya LZMA/LZMA2 zinciriyle ardışıl çözülüyorsa true (yavaş seek uyarısı).
    pub fn is_compressed(&self) -> bool {
        self.facade.is_some()
    }

    async fn write_aes_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        let aes = self.plan.aes.as_ref().expect("AES plan present");
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
                    .map_err(|_| io::Error::other("invalid AES previous block size"))?
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
        if let Some(facade) = &self.facade {
            return facade.write_range(range, out).await;
        }
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
            "next header is {} bytes; safe header limit is {} bytes",
            start_header.next_header_size, limits.max_header_bytes
        )));
    }

    let header_position = start_header.next_header_position();
    let header_end = header_position
        .checked_add(start_header.next_header_size)
        .ok_or_else(|| SevenZipError::InvalidLayout("next header end overflow".into()))?;
    if header_end > archive_len {
        return Err(SevenZipError::InvalidLayout(
            "next header is outside available 7z volumes; set is incomplete".into(),
        ));
    }

    let header_size = usize::try_from(start_header.next_header_size)
        .map_err(|_| SevenZipError::InvalidLayout("next header does not fit in memory".into()))?;
    reader.seek(SeekFrom::Start(header_position))?;
    let mut header_data = vec![0u8; header_size];
    reader.read_exact(&mut header_data)?;
    verify_header_crc("next header", &header_data, start_header.next_header_crc)?;

    let marker = header_data
        .first()
        .copied()
        .ok_or_else(|| SevenZipError::InvalidLayout("7z next header data is empty".into()))?;
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
                    "decoded 7z header does not start with the HEADER marker".into(),
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
            "unrecognized 7z header marker: {other:#x}"
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
                        "encoded header contains multiple PackInfo".into(),
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
                        "encoded header contains multiple UnpackInfo".into(),
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
                        "encoded header contains multiple SubStreamsInfo".into(),
                    ));
                }
                let folders = streams
                    .unpack_info
                    .as_ref()
                    .ok_or_else(|| {
                        SevenZipError::InvalidLayout(
                            "SubStreamsInfo came before UnpackInfo".into(),
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
                    "unrecognized property in encoded header StreamsInfo: {other:#x}"
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
        .ok_or_else(|| SevenZipError::InvalidLayout("encoded header contains no PackInfo".into()))?;
    let unpack_info = streams.unpack_info.as_ref().ok_or_else(|| {
        SevenZipError::InvalidLayout("encoded header contains no UnpackInfo".into())
    })?;
    if pack_info.pack_sizes.len() != 1 || unpack_info.folders.len() != 1 {
        return Err(SevenZipError::InvalidLayout(
            "encoded header is only supported with a single folder and single pack stream".into(),
        ));
    }

    let folder = &unpack_info.folders[0];
    let coder_order = simple_coder_order(folder)?;
    if folder.unpack_sizes.len() != folder.coders.len() {
        return Err(SevenZipError::InvalidLayout(format!(
            "encoded header carries {} unpack size for coder {}",
            folder.coders.len(),
            folder.unpack_sizes.len()
        )));
    }

    if let Some(substreams) = streams.substreams_info.as_ref() {
        if substreams.num_unpack_streams_in_folders.as_slice() != [1] {
            return Err(SevenZipError::InvalidLayout(
                "encoded header contains multiple unpack substreams".into(),
            ));
        }
    }

    let pack_size = pack_info.pack_sizes[0];
    if pack_size > limits.max_header_bytes {
        return Err(SevenZipError::InvalidLayout(format!(
            "encoded header pack stream is {pack_size} bytes; safe header limit is {} bytes",
            limits.max_header_bytes
        )));
    }
    let pack_start = SIGNATURE_HEADER_SIZE
        .checked_add(pack_info.pack_pos)
        .ok_or_else(|| SevenZipError::InvalidLayout("encoded header pack offset overflow".into()))?;
    let pack_end = pack_start
        .checked_add(pack_size)
        .ok_or_else(|| SevenZipError::InvalidLayout("encoded header pack end overflow".into()))?;
    if pack_end > archive_len {
        return Err(SevenZipError::InvalidLayout(
            "encoded header pack range is outside available 7z volumes; set is incomplete".into(),
        ));
    }

    let pack_len = usize::try_from(pack_size)
        .map_err(|_| SevenZipError::InvalidLayout("encoded header pack does not fit in memory".into()))?;
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
                "encoded header coder output is {decoded_size} bytes; safe header limit is {} bytes",
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
                    "encoded header contains an unsupported coder: {}",
                    method::name(unsupported)
                )));
            }
        };
    }

    let final_coder = *coder_order
        .last()
        .ok_or_else(|| SevenZipError::InvalidLayout("encoded header coder chain is empty".into()))?;
    let expected_size = folder.unpack_sizes[final_coder];
    let capacity = usize::try_from(expected_size)
        .map_err(|_| SevenZipError::InvalidLayout("decoded header does not fit in memory".into()))?;
    let mut decoded = Vec::with_capacity(capacity);
    decoder.read_to_end(&mut decoded)?;
    if decoded.len() as u64 != expected_size {
        return Err(SevenZipError::InvalidLayout(format!(
            "decoded header is {} bytes, expected {expected_size} bytes",
            decoded.len()
        )));
    }

    if let Some(expected_crc) = folder.unpack_crc {
        verify_header_crc("decoded encoded header", &decoded, expected_crc)?;
    }
    if let Some(expected_crc) = streams
        .substreams_info
        .as_ref()
        .and_then(|info| info.digests.first())
        .copied()
        .flatten()
    {
        verify_header_crc("decoded encoded header substream", &decoded, expected_crc)?;
    }
    Ok(decoded)
}

/// Tek giriş/tek çıkışlı coder'ları bind-pair yönünde, pack stream'den nihai
/// çıktıya doğru sıralar. Liste sırasına güvenilmez; örneğin `[COPY, AES]`
/// tanımı gerçek veri akışında önce AES, sonra COPY olabilir.
fn simple_coder_order(folder: &Folder) -> Result<Vec<usize>, SevenZipError> {
    if folder.coders.is_empty() {
        return Err(SevenZipError::InvalidLayout(
            "encoded header coder chain is empty".into(),
        ));
    }
    if folder
        .coders
        .iter()
        .any(|coder| coder.num_in_streams != 1 || coder.num_out_streams != 1)
    {
        return Err(SevenZipError::InvalidLayout(
            "encoded header only supports single-input/single-output coder chains".into(),
        ));
    }
    if folder.packed_streams.len() != 1 || folder.bind_pairs.len() + 1 != folder.coders.len() {
        return Err(SevenZipError::InvalidLayout(
            "encoded header coder graph is not a simple chain".into(),
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
                SevenZipError::InvalidLayout("encoded header bind input index invalid".into())
            })?;
        let output = usize::try_from(pair.out_index)
            .ok()
            .filter(|&index| index < coder_count)
            .ok_or_else(|| {
                SevenZipError::InvalidLayout("encoded header bind output index invalid".into())
            })?;
        if incoming_bound[input] || outgoing_bound[output] {
            return Err(SevenZipError::InvalidLayout(
                "encoded header coder graph has a duplicate bind stream".into(),
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
            SevenZipError::InvalidLayout("encoded header packed stream index invalid".into())
        })?;
    if incoming_bound[current] {
        return Err(SevenZipError::InvalidLayout(
            "encoded header packed stream is also a bind input".into(),
        ));
    }

    let mut visited = vec![false; coder_count];
    let mut order = Vec::with_capacity(coder_count);
    loop {
        if visited[current] {
            return Err(SevenZipError::InvalidLayout(
                "encoded header coder graph has a cycle".into(),
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
            "encoded header coder graph is disconnected".into(),
        ));
    }
    Ok(order)
}

fn verify_header_crc(label: &str, data: &[u8], expected_crc: u32) -> Result<(), SevenZipError> {
    let actual_crc = crc32fast::hash(data);
    if actual_crc != expected_crc {
        return Err(SevenZipError::Header(format!(
            "{label} CRC mismatch: expected {expected_crc:#x}, got {actual_crc:#x}"
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
        .ok_or_else(|| SevenZipError::InvalidLayout("total size overflow in 7z header".into()))?;

    if required_len > archive_len {
        return Err(SevenZipError::InvalidLayout(format!(
            "7z header expects {required_len} bytes of physical archive but NZB volumes only provide {archive_len} bytes; set is incomplete"
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
            "folder/substream count mismatch".into(),
        ));
    }

    // FilesInfo'daki stream sırasını folder sırasına bağla ve en büyük medya
    // girdisini seç. Dizinler/boş dosyalar stream tüketmez. `folder_prefix`,
    // solid folder içinde seçilen girdiden ÖNCE gelen dosyaların toplam
    // çözülmüş boyutudur; çözüm cephesi bu kadar baytı atlayarak başlar.
    let mut folder_index = 0usize;
    let mut remaining_in_folder = streams_per_folder.first().copied().unwrap_or(0);
    let mut folder_prefix = 0u64;
    let mut selected: Option<(&zesven::format::files::ArchiveEntry, usize, u64)> = None;
    for entry in entries.iter().filter(|entry| entry.has_stream) {
        while folder_index < folders.len() && remaining_in_folder == 0 {
            folder_index += 1;
            remaining_in_folder = streams_per_folder.get(folder_index).copied().unwrap_or(0);
            folder_prefix = 0;
        }
        if folder_index >= folders.len() {
            return Err(SevenZipError::InvalidLayout(
                "no folder found for file stream".into(),
            ));
        }

        if is_playable_media_filename(&entry.name)
            && selected.is_none_or(|(current, _, _)| entry.size > current.size)
        {
            selected = Some((entry, folder_index, folder_prefix));
        }
        folder_prefix = folder_prefix
            .checked_add(entry.size)
            .ok_or_else(|| SevenZipError::InvalidLayout("folder-internal offset overflow".into()))?;
        remaining_in_folder -= 1;
    }

    let (entry, folder_index, prefix_skip) = selected.ok_or(SevenZipError::NoPlayableMedia)?;

    let folder = &folders[folder_index];
    if folder.packed_streams.len() != 1 {
        return Err(SevenZipError::UnsupportedCompression);
    }
    // Medya verisinde de yalnız tek giriş/çıkışlı, bağlantılı bir coder zinciri
    // kabul edilir. Yalnız method adına bakmak; bozuk bind graph'ı veya iki kez
    // AES uygulayan bir arşivi yanlışlıkla tek decrypt ile sunabilirdi.
    let coder_order = simple_coder_order(folder)?;
    let aes_count = folder
        .coders
        .iter()
        .filter(|coder| coder.method_id.as_slice() == method::AES)
        .count();
    let coder_supported = |method_id: &[u8]| {
        matches!(
            method_id,
            m if m == method::COPY
                || m == method::AES
                || m == method::LZMA
                || m == method::LZMA2
        )
    };
    if folder.coders.is_empty()
        || aes_count > 1
        || folder
            .coders
            .iter()
            .any(|coder| !coder_supported(coder.method_id.as_slice()))
    {
        return Err(SevenZipError::UnsupportedCompression);
    }
    let compressed = folder.coders.iter().any(|coder| {
        matches!(
            coder.method_id.as_slice(),
            m if m == method::LZMA || m == method::LZMA2
        )
    });

    let pack_index = folders[..folder_index]
        .iter()
        .try_fold(0usize, |total, folder| {
            total.checked_add(folder.packed_streams.len())
        })
        .ok_or_else(|| SevenZipError::InvalidLayout("pack stream index overflow".into()))?;
    let packed_size = *pack_info
        .pack_sizes
        .get(pack_index)
        .ok_or_else(|| SevenZipError::InvalidLayout("medya pack stream boyutu yok".into()))?;
    let previous_sizes = pack_info
        .pack_sizes
        .get(..pack_index)
        .ok_or_else(|| SevenZipError::InvalidLayout("no previous pack streams".into()))?;
    let previous_packed = checked_pack_sum(previous_sizes)?;
    let packed_start = SIGNATURE_HEADER_SIZE
        .checked_add(pack_info.pack_pos)
        .and_then(|value| value.checked_add(previous_packed))
        .ok_or_else(|| SevenZipError::InvalidLayout("pack offset overflow".into()))?;
    let packed_end = packed_start
        .checked_add(packed_size)
        .ok_or_else(|| SevenZipError::InvalidLayout("pack end overflow".into()))?;
    if packed_end > archive_len {
        return Err(SevenZipError::InvalidLayout(
            "media pack range is outside available 7z volumes; set is incomplete".into(),
        ));
    }

    let (aes, packing) = if compressed {
        // Sıkıştırılmış zincir: pack boyutu ile medya boyutu doğal olarak
        // farklıdır; STORE denetimleri uygulanmaz. AES varsa zincirin bir
        // adımı olarak çözüm fabrikasında ele alınır.
        if aes_count == 1 && password.is_none() {
            return Err(SevenZipError::MissingPassword);
        }
        let steps = coder_order
            .iter()
            .map(|&index| {
                let coder = &folder.coders[index];
                CoderStep {
                    method_id: coder.method_id.clone(),
                    properties: coder.properties.clone().unwrap_or_default(),
                    unpack_size: folder.unpack_sizes[index],
                }
            })
            .collect();
        (
            None,
            PackingPlan::Compressed(CompressedPlan {
                steps,
                prefix_skip,
                password: password.cloned(),
            }),
        )
    } else {
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
                .ok_or_else(|| SevenZipError::InvalidLayout("no AES coder properties".into()))?;
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
                .map_err(|_| SevenZipError::InvalidLayout("AES IV size is not 16".into()))?;
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
        (aes, PackingPlan::Direct)
    };

    Ok(EntryPlan {
        filename: entry.name.clone(),
        decoded_size: entry.size,
        packed_range: packed_start..packed_end,
        aes,
        packing,
    })
}

/// Coder zincirini pack akışı üzerine kurar. [`plan_from_header`] method
/// kümeyi doğruladığından burada yalnız COPY/AES/LZMA/LZMA2 görülür; zincir
/// kurulumu birim testlerde de çağrılabilir.
fn build_chain_decoder(
    base: Box<dyn Read + Send>,
    steps: &[CoderStep],
    password: Option<&Password>,
) -> io::Result<Box<dyn Read + Send>> {
    let mut decoder = base;
    for step in steps {
        decoder = match step.method_id.as_slice() {
            m if m == method::COPY => Box::new(CopyDecoder::new(decoder, step.unpack_size)),
            m if m == method::AES => {
                let password = password
                    .ok_or_else(|| io::Error::other("no password for the AES chain"))?;
                let aes = Aes256Decoder::new(decoder, &step.properties, password)
                    .map_err(|error| io::Error::other(error.to_string()))?;
                Box::new(aes.take(step.unpack_size))
            }
            m if m == method::LZMA => Box::new(
                LzmaDecoder::new(decoder, &step.properties, step.unpack_size)
                    .map_err(|error| io::Error::other(error.to_string()))?,
            ),
            m if m == method::LZMA2 => Box::new(
                Lzma2Decoder::new(decoder, &step.properties)
                    .map_err(|error| io::Error::other(error.to_string()))?
                    .take(step.unpack_size),
            ),
            other => {
                return Err(io::Error::other(format!(
                    "desteklenmeyen coder: {}",
                    method::name(other)
                )))
            }
        };
    }
    Ok(decoder)
}

/// Sıkıştırılmış plan için [`SeekableDecodeSource`] kurar. Fabrika her
/// çağrıda cilt kümesinin pack aralığından başlayan taze bir zincir açar;
/// solid öneki (varsa) her açılışta çözülüp atılır.
fn build_decode_facade(
    archive: &Arc<NntpVolumeSet>,
    plan: &EntryPlan,
    compressed: &CompressedPlan,
    cancellation: watch::Receiver<bool>,
) -> SeekableDecodeSource {
    let volume_set = Arc::clone(archive);
    let packed_range = plan.packed_range.clone();
    let packed_size = packed_range.end - packed_range.start;
    let steps = compressed.steps.clone();
    let prefix_skip = compressed.prefix_skip;
    let decoded_size = plan.decoded_size;
    let password = compressed.password.clone();

    SeekableDecodeSource::new(decoded_size, Box::new(move || {
        let runtime = tokio::runtime::Handle::current();
        let mut reader =
            BlockingArchiveReader::new(Arc::clone(&volume_set), runtime, cancellation.clone());
        reader.seek(SeekFrom::Start(packed_range.start))?;
        let base: Box<dyn Read + Send> = Box::new(reader.take(packed_size));
        let mut decoder = build_chain_decoder(base, &steps, password.as_ref())?;
        if prefix_skip > 0 {
            io::copy(&mut decoder.by_ref().take(prefix_skip), &mut io::sink())?;
        }
        Ok(Box::new(decoder.take(decoded_size)) as Box<dyn Read + Send>)
    }))
}

fn decrypt_blocks(key: &[u8; 32], iv: &[u8; 16], ciphertext: &mut [u8]) -> io::Result<()> {    if !ciphertext.len().is_multiple_of(AES_BLOCK_SIZE as usize) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "AES ciphertext is not 16-byte aligned",
        ));
    }
    Aes256CbcDec::new_from_slices(key, iv)
        .map_err(|_| io::Error::other("invalid AES key/IV size"))?
        .decrypt_padded_mut::<NoPadding>(ciphertext)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "AES decryption failed"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use cbc::cipher::{BlockEncryptMut, KeyIvInit};
    use std::io::{Cursor, Write};
    use zesven::codec::{Lzma2Encoder, Lzma2EncoderOptions};
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
    fn sikistirilmis_7z_cozum_planina_eslenir() {
        let header = header_with(method::LZMA2, Some(vec![0]), 32);
        let plan = plan_from_header(&header, 200, None).unwrap();
        assert_eq!(plan.packed_range, 132..164);
        let PackingPlan::Compressed(compressed) = &plan.packing else {
            panic!("LZMA2 chain must produce a Compressed plan");
        };
        assert_eq!(compressed.prefix_skip, 0);
        assert_eq!(compressed.steps.len(), 1);
        assert_eq!(compressed.steps[0].method_id, method::LZMA2);
        assert_eq!(compressed.steps[0].unpack_size, 32);
    }

    #[test]
    fn solid_folder_on_eki_hesaplanir() {
        // Tek folder, iki dosya: büyük olan (ikinci) seçilir, önek = ilkinin boyutu.
        let mut header = header_with(method::LZMA2, Some(vec![0]), 300);
        header
            .substreams_info
            .as_mut()
            .unwrap()
            .num_unpack_streams_in_folders = vec![2];
        let entries = &mut header.files_info.as_mut().unwrap().entries;
        entries[0].size = 100;
        entries.push(ArchiveEntry {
            name: "movie2.mkv".into(),
            is_directory: false,
            is_anti: false,
            has_stream: true,
            size: 200,
            crc: None,
            ctime: None,
            atime: None,
            mtime: None,
            attributes: None,
        });

        let plan = plan_from_header(&header, 500, None).unwrap();
        assert_eq!(plan.filename, "movie2.mkv");
        assert_eq!(plan.decoded_size, 200);
        let PackingPlan::Compressed(compressed) = &plan.packing else {
            panic!("solid folder must produce a Compressed plan");
        };
        assert_eq!(compressed.prefix_skip, 100);
    }

    #[test]
    fn desteklenmeyen_codec_reddedilir() {
        // BCJ x86 filtresi (0x04) bilinçli olarak destek dışı.
        let header = header_with(&[0x04], Some(vec![0]), 32);
        assert!(matches!(
            plan_from_header(&header, 200, None),
            Err(SevenZipError::UnsupportedCompression)
        ));
    }

    /// Test yardımcısı: LZMA2 ile sıkıştırır (preset 1).
    fn lzma2_compress(data: &[u8]) -> Vec<u8> {
        let mut packed = Vec::new();
        let mut encoder = Lzma2Encoder::new(&mut packed, &Lzma2EncoderOptions::with_preset(1));
        encoder.write_all(data).unwrap();
        encoder.try_finish().unwrap();
        packed
    }

    fn lzma2_properties() -> Vec<u8> {
        Lzma2EncoderOptions::with_preset(1).properties()
    }

    fn lzma2_step(unpack_size: u64) -> CoderStep {
        CoderStep {
            method_id: method::LZMA2.to_vec(),
            properties: lzma2_properties(),
            unpack_size,
        }
    }

    #[test]
    fn lzma2_zinciri_gercek_veriyle_cozulur() {
        let original: Vec<u8> = (0..=251u8).cycle().take(200_000).collect();
        let packed = lzma2_compress(&original);
        assert!(
            packed.len() < original.len() / 2,
            "pattern must actually compress"
        );

        let steps = vec![lzma2_step(original.len() as u64)];
        let base: Box<dyn Read + Send> = Box::new(Cursor::new(packed));
        let mut decoder = build_chain_decoder(base, &steps, None).unwrap();
        let mut decoded = Vec::new();
        decoder.read_to_end(&mut decoded).unwrap();
        assert_eq!(decoded, original);
    }

    #[test]
    fn solid_on_eki_gercek_veriyle_atlanir() {
        // Solid folder simülasyonu: A+B tek pack akışında; hedef B.
        let a: Vec<u8> = (0..=199u8).cycle().take(150_000).collect();
        let b: Vec<u8> = (200..=255u8).cycle().take(90_000).collect();
        let mut combined = a.clone();
        combined.extend_from_slice(&b);
        let packed = lzma2_compress(&combined);

        let steps = vec![lzma2_step(combined.len() as u64)];
        let base: Box<dyn Read + Send> = Box::new(Cursor::new(packed));
        let mut decoder = build_chain_decoder(base, &steps, None).unwrap();
        io::copy(&mut decoder.by_ref().take(a.len() as u64), &mut io::sink()).unwrap();
        let mut decoded = Vec::new();
        decoder
            .take(b.len() as u64)
            .read_to_end(&mut decoded)
            .unwrap();
        assert_eq!(decoded, b);
    }

    #[tokio::test]
    async fn cephe_gercek_lzma2_ile_seek_eder() {
        let original: Vec<u8> = (0..=255u8).cycle().take(600_000).collect();
        let packed = lzma2_compress(&original);
        let decoded_size = original.len() as u64;
        let facade = SeekableDecodeSource::with_window(
            decoded_size,
            64 * 1024,
            Box::new(move || {
                let base: Box<dyn Read + Send> = Box::new(Cursor::new(packed.clone()));
                build_chain_decoder(base, &[lzma2_step(decoded_size)], None)
            }),
        );

        let mut head = Vec::new();
        facade.write_range(0..4096, &mut head).await.unwrap();
        assert_eq!(head, original[..4096]);

        // İleri sıçrama (decoder ileri sarılır).
        let mut middle = Vec::new();
        facade.write_range(500_000..503_000, &mut middle).await.unwrap();
        assert_eq!(middle, original[500_000..503_000]);

        // Pencere öncesi geriye sıçrama (zincir baştan kurulur).
        let mut back = Vec::new();
        facade.write_range(1024..2048, &mut back).await.unwrap();
        assert_eq!(back, original[1024..2048]);
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
            "invalid 7z layout: 7z header expects 172 bytes of physical archive but NZB volumes only provide 140 bytes; set is incomplete"
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
