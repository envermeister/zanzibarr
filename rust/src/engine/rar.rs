//! Çok ciltli RAR5 STORE yayınlarını sanal, seek edilebilir medya dosyasına
//! dönüştürür.
//!
//! RAR ciltleri diske indirilmez. Her `.partNN.rar` (veya eski usul
//! `.rar`/`.rNN`) dosyası mevcut NNTP+yEnc kaynağıyla açılır, tek bir sanal
//! byte uzayında birleştirilir ve her cildin blok başlıkları o uzaydan tembel
//! olarak okunur. İçerideki medya STORE ise her parçanın veri aralığı doğrudan
//! sunulur. Sıkıştırılmış (method != STORE), solid veya şifreli arşivler,
//! rastgele seek'i bozmamak için açıkça reddedilir. RAR4 ve eski biçim
//! desteklenmez: blok düzeni farklıdır ve gerçek bir örnek olmadan parser'ı
//! doğrulamak mümkün değildir.
//!
//! Başlık düzeni (RAR5, libarchive rar5 okuyucusuyla çapraz doğrulandı):
//! imza `52 61 72 21 1A 07 01 00`; ardından bloklar. Her blok:
//! HEAD_CRC(4, HEAD_SIZE vint'inin ilk baytından başlık sonuna kadar CRC32),
//! HEAD_SIZE(vint, kendi vint'i HARİÇ), HEAD_TYPE(vint), HEAD_FLAGS(vint),
//! [EXTRA_SIZE(vint) bayrak 0x01], [DATA_SIZE(vint) bayrak 0x02],
//! tip-özel alanlar, extra kayıtları, [veri]. HEAD_FLAGS 0x08/0x10
//! SPLIT_BEFORE/SPLIT_AFTER; tipler 1=MAIN 2=FILE 3=SERVICE 4=ENCRYPTION
//! 5=ENDARC. Gerçek ciltler veri sonunda bir SERVICE (QuickOpen) ve ENDARC
//! bloğu taşır; ikisi de atlanır/durdurur.

use std::io::{self, Read, Seek, SeekFrom};
use std::ops::Range;
use std::sync::Arc;

use thiserror::Error;
use tokio::io::{AsyncWrite, AsyncWriteExt};
use tokio::sync::watch;

use super::archive::{
    cancellation_requested, run_blocking_cancellable, validate_range, BlockingArchiveReader,
    BlockingTaskError, NntpVolumeSet, VolumeSetError,
};
use super::nntp::{NntpPool, TlsNntpConnector};
use super::nzb::{is_playable_media_filename, NzbFile};
use super::server::{content_type_for, RangeSource};

const RAR5_SIGNATURE: &[u8; 8] = b"Rar!\x1A\x07\x01\x00";
const RAR4_SIGNATURE: &[u8; 7] = b"Rar!\x1A\x07\x00";

const HEAD_TYPE_MAIN: u64 = 1;
const HEAD_TYPE_FILE: u64 = 2;
const HEAD_TYPE_SERVICE: u64 = 3;
const HEAD_TYPE_ENCRYPTION: u64 = 4;
const HEAD_TYPE_ENDARC: u64 = 5;

const HEAD_FLAG_SKIP_IF_UNKNOWN: u64 = 0x04;
const HEAD_FLAG_SPLIT_BEFORE: u64 = 0x08;
const HEAD_FLAG_SPLIT_AFTER: u64 = 0x10;

const FILE_FLAG_DIRECTORY: u64 = 0x01;
const FILE_FLAG_UTIME: u64 = 0x02;
const FILE_FLAG_CRC32: u64 = 0x04;

/// Extra alanındaki şifreleme kaydının tür kimliği (EX_CRYPT).
const EXTRA_RECORD_CRYPT: u64 = 1;

/// Tek bir blok başlığı için güvenli üst sınır (vint alanları + dosya adı +
/// extra). Gerçek başlıklar birkaç yüz bayttır; sınır yalnız bozuk bir NZB'nin
/// belleği şişirmesini engeller.
const MAX_BLOCK_HEADER_SIZE: u64 = 16 * 1024 * 1024;

#[derive(Debug, Error)]
pub enum RarError {
    #[error("RAR ciltleri hazırlanamadı: {0}")]
    Io(#[from] io::Error),
    #[error("RAR başlığı okunamadı: {0}")]
    Header(String),
    #[error("RAR arşivinde oynatılabilir medya dosyası yok")]
    NoPlayableMedia,
    #[error("RAR arşivi sıkıştırılmış; yalnız STORE arşivleri seek edilerek oynatılabilir")]
    UnsupportedCompression,
    #[error("RAR4 ve daha eski arşivler desteklenmiyor; RAR5 STORE seti gerekli")]
    UnsupportedVersion,
    #[error("RAR arşivi şifreli; parola korumalı RAR setleri oynatılamaz")]
    Encrypted,
    #[error("geçersiz RAR yerleşimi: {0}")]
    InvalidLayout(String),
    #[error("RAR hazırlama görevi tamamlanamadı: {0}")]
    Task(String),
    #[error("RAR hazırlama iptal edildi")]
    Cancelled,
}

impl From<VolumeSetError> for RarError {
    fn from(error: VolumeSetError) -> Self {
        match error {
            VolumeSetError::Io(error) => Self::Io(error),
            VolumeSetError::InvalidLayout(message) => Self::InvalidLayout(message),
            VolumeSetError::Cancelled => Self::Cancelled,
        }
    }
}

impl From<BlockingTaskError> for RarError {
    fn from(error: BlockingTaskError) -> Self {
        match error {
            BlockingTaskError::Task(message) => Self::Task(message),
            BlockingTaskError::Cancelled => Self::Cancelled,
        }
    }
}

fn ensure_not_cancelled(cancellation: &watch::Receiver<bool>) -> Result<(), RarError> {
    if cancellation_requested(cancellation) {
        Err(RarError::Cancelled)
    } else {
        Ok(())
    }
}

/// Bir RAR5 cildinden çıkarılan tek dosya girdisi (STORE parçası adayı).
#[derive(Debug, Clone)]
struct FileEntry {
    name: String,
    unpacked_size: u64,
    data_size: u64,
    /// Cilt-içi mutlak veri ofseti (imzanın ilk baytından itibaren).
    data_offset: u64,
    split_before: bool,
    split_after: bool,
    store: bool,
    solid: bool,
    encrypted: bool,
    is_dir: bool,
}

/// Sanal set uzayında bir medya parçası.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Fragment {
    set_offset: u64,
    len: u64,
}

/// Çözülmüş medya byte uzayını sanal set uzayındaki parça aralıklarına eşler.
#[derive(Debug, Clone)]
struct FragmentMap {
    fragments: Vec<Fragment>,
    /// Her parçanın çözülmüş uzaydaki başlangıcı (prefix toplamı).
    starts: Vec<u64>,
    total_len: u64,
    filename: String,
}

impl FragmentMap {
    /// Çözülmüş uzaydaki `range`'i set uzayındaki ardışık dilimlere çevirir.
    /// `range`, `total_len` içinde doğrulanmış olmalı.
    fn slices(&self, range: Range<u64>) -> Vec<Range<u64>> {
        let mut out = Vec::new();
        let mut cursor = range.start;
        while cursor < range.end {
            let index = self.starts.partition_point(|&start| start <= cursor) - 1;
            let fragment = self.fragments[index];
            let within = cursor - self.starts[index];
            let take = (range.end - cursor).min(fragment.len - within);
            out.push((fragment.set_offset + within)..(fragment.set_offset + within + take));
            cursor += take;
        }
        out
    }
}

/// Oynatıcıya doğrudan medya dosyası gibi görünen RAR5 STORE içeriği.
pub struct RarEntrySource {
    archive: Arc<NntpVolumeSet>,
    map: FragmentMap,
    content_type: &'static str,
}

impl RarEntrySource {
    pub async fn new(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        files: Vec<NzbFile>,
    ) -> Result<Self, RarError> {
        // CLI/test çağrılarında iptal sahibi yoktur; sender bu await boyunca
        // canlı tutularak receiver'ın kapanması yanlış iptal sayılmaz.
        let (_cancellation_guard, cancellation) = watch::channel(false);
        Self::new_cancellable(pool, files, cancellation).await
    }

    pub async fn new_cancellable(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        files: Vec<NzbFile>,
        mut cancellation: watch::Receiver<bool>,
    ) -> Result<Self, RarError> {
        let archive =
            Arc::new(NntpVolumeSet::new_cancellable(pool, files, &mut cancellation).await?);
        ensure_not_cancelled(&cancellation)?;
        let layout: Vec<(u64, u64)> = (0..archive.volume_count())
            .map(|index| (archive.volume_start(index), archive.volume_len(index)))
            .collect();
        let archive_for_parser = Arc::clone(&archive);
        let runtime = tokio::runtime::Handle::current();

        let map = run_blocking_cancellable(cancellation, move |reader_cancellation| {
            let mut reader =
                BlockingArchiveReader::new(archive_for_parser, runtime, reader_cancellation);
            build_fragment_map(&mut reader, &layout)
        })
        .await?;

        let content_type = content_type_for(&map.filename);
        Ok(Self {
            archive,
            map,
            content_type,
        })
    }

    pub fn filename(&self) -> &str {
        &self.map.filename
    }

    pub fn segment_count(&self) -> usize {
        self.archive.segment_count()
    }
}

impl RangeSource for RarEntrySource {
    fn total_len(&self) -> u64 {
        self.map.total_len
    }

    fn content_type(&self) -> &str {
        self.content_type
    }

    async fn write_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        validate_range(range.clone(), self.map.total_len)?;
        // Parça parça, tembel akış: oynatıcı durursa server da durur.
        for slice in self.map.slices(range) {
            self.archive.write_range(slice, &mut *out).await?;
        }
        out.flush().await
    }
}

/// Cilt sınırı bilen, ileri-seek destekli sınırlı okuyucu. Parser yalnız bu
/// sarmalayıcı üzerinden okur; böylece bir cildin baytları asla bir sonraki
/// cilde taşmaz.
struct VolumeParser<'a, R> {
    reader: &'a mut R,
    position: u64,
    end: u64,
}

impl<R: Read + Seek> VolumeParser<'_, R> {
    fn remaining(&self) -> u64 {
        self.end - self.position
    }

    fn unexpected_eof(&self) -> RarError {
        RarError::Header("cilt sonu blok ortasında bitti; set eksik".into())
    }

    fn map_io(error: io::Error) -> RarError {
        if error.kind() == io::ErrorKind::Interrupted {
            // BlockingArchiveReader iptali yalnız Interrupted ile bildirir.
            RarError::Cancelled
        } else {
            RarError::Io(error)
        }
    }

    fn read_exact(&mut self, buffer: &mut [u8]) -> Result<(), RarError> {
        if buffer.len() as u64 > self.remaining() {
            return Err(self.unexpected_eof());
        }
        self.reader.read_exact(buffer).map_err(Self::map_io)?;
        self.position += buffer.len() as u64;
        Ok(())
    }

    fn skip(&mut self, count: u64) -> Result<(), RarError> {
        if count > self.remaining() {
            return Err(self.unexpected_eof());
        }
        self.reader
            .seek(SeekFrom::Current(count as i64))
            .map_err(Self::map_io)?;
        self.position += count;
        Ok(())
    }
}

/// Okunan her baytı CRC32'ye besleyen sarmalayıcı.
struct HashingReader<'p, 'v, R> {
    inner: &'p mut VolumeParser<'v, R>,
    hasher: crc32fast::Hasher,
}

impl<R: Read + Seek> HashingReader<'_, '_, R> {
    fn read_vint(&mut self) -> io::Result<u64> {
        let mut value = 0u64;
        for index in 0..10u32 {
            let mut byte = [0u8; 1];
            self.read_exact(&mut byte)?;
            if index == 9 && byte[0] & 0x7E != 0 {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "vint u64 sınırını aşıyor",
                ));
            }
            value |= u64::from(byte[0] & 0x7F) << (7 * index);
            if byte[0] & 0x80 == 0 {
                return Ok(value);
            }
        }
        Err(io::Error::new(io::ErrorKind::InvalidData, "vint çok uzun"))
    }
}

impl<R: Read + Seek> Read for HashingReader<'_, '_, R> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        // VolumeParser::read_exact RarError döndürür; Read uyumu için tek
        // seferde doldurma yerine hatayı io'ya çeviren düz okuma yapılır.
        if buffer.len() as u64 > self.inner.remaining() {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "cilt sonu blok ortasında bitti; set eksik",
            ));
        }
        let count = self.inner.reader.read(buffer)?;
        self.hasher.update(&buffer[..count]);
        self.inner.position += count as u64;
        Ok(count)
    }
}

fn io_to_header(context: &str, error: io::Error) -> RarError {
    if error.kind() == io::ErrorKind::Interrupted {
        // BlockingArchiveReader iptali yalnız Interrupted ile bildirir.
        RarError::Cancelled
    } else {
        RarError::Header(format!("{context}: {error}"))
    }
}

/// Tek cildin bloklarını okuyup FILE girdilerini döndürür. `reader`, cildin
/// ilk baytında (imza) konumlanmış olmalı; `volume_start`/`volume_end` sanal
/// set uzayındaki cilt sınırlarıdır.
fn parse_volume<R: Read + Seek>(
    reader: &mut R,
    volume_start: u64,
    volume_end: u64,
) -> Result<Vec<FileEntry>, RarError> {
    let mut parser = VolumeParser {
        reader,
        position: volume_start,
        end: volume_end,
    };

    let mut signature = [0u8; 8];
    parser.read_exact(&mut signature)?;
    if signature[..7] == RAR4_SIGNATURE[..] {
        return Err(RarError::UnsupportedVersion);
    }
    if &signature != RAR5_SIGNATURE {
        return Err(RarError::Header("RAR imzası bulunamadı".into()));
    }

    let mut entries = Vec::new();
    loop {
        // ENDARC'ta döngü kırılır; ENDARC yoksa cilt sınırı temiz son sayılır.
        // Cilt sonuna 4 bayttan az kalmışsa kalanlar anlamlı blok olamaz.
        if parser.remaining() < 4 {
            break;
        }

        let mut crc_bytes = [0u8; 4];
        parser.read_exact(&mut crc_bytes)?;
        let expected_crc = u32::from_le_bytes(crc_bytes);

        let (block, data_size) = {
            let mut hashing = HashingReader {
                inner: &mut parser,
                hasher: crc32fast::Hasher::new(),
            };
            let header_size = hashing
                .read_vint()
                .map_err(|error| io_to_header("HEAD_SIZE okunamadı", error))?;
            if header_size == 0 || header_size > MAX_BLOCK_HEADER_SIZE {
                return Err(RarError::Header(format!(
                    "blok başlığı {header_size} bayt; güvenli sınır {MAX_BLOCK_HEADER_SIZE}"
                )));
            }
            let header_len = usize::try_from(header_size)
                .map_err(|_| RarError::Header("blok başlığı belleğe sığmıyor".into()))?;
            let mut header = vec![0u8; header_len];
            hashing
                .read_exact(&mut header)
                .map_err(|error| io_to_header("blok başlığı okunamadı", error))?;
            let actual_crc = hashing.hasher.finalize();
            if actual_crc != expected_crc {
                return Err(RarError::Header(format!(
                    "blok CRC uyuşmazlığı: beklenen {expected_crc:#x}, bulunan {actual_crc:#x}"
                )));
            }
            parse_block_header(&header)?
        };

        match block {
            Block::Main | Block::Service => {
                parser.skip(data_size)?;
            }
            Block::Encryption => return Err(RarError::Encrypted),
            Block::EndArchive => break,
            Block::File(mut entry) => {
                entry.data_offset = parser.position - volume_start;
                entry.data_size = data_size;
                parser.skip(data_size)?;
                entries.push(entry);
            }
            Block::Unknown { head_type, skippable } => {
                if !skippable {
                    return Err(RarError::Header(format!(
                        "bilinmeyen zorunlu blok türü: {head_type}"
                    )));
                }
                parser.skip(data_size)?;
            }
        }
    }
    Ok(entries)
}

enum Block {
    Main,
    Service,
    Encryption,
    EndArchive,
    File(FileEntry),
    Unknown { head_type: u64, skippable: bool },
}

/// CRC'si doğrulanmış blok başlığı gövdesini (HEAD_TYPE'tan başlayan) çözer.
fn parse_block_header(header: &[u8]) -> Result<(Block, u64), RarError> {
    let mut cursor = io::Cursor::new(header);
    let head_type = read_vint_slice(&mut cursor)?;
    let head_flags = read_vint_slice(&mut cursor)?;
    let extra_size = if head_flags & 0x01 != 0 {
        read_vint_slice(&mut cursor)?
    } else {
        0
    };
    let data_size = if head_flags & 0x02 != 0 {
        read_vint_slice(&mut cursor)?
    } else {
        0
    };

    let block = match head_type {
        HEAD_TYPE_MAIN => Block::Main,
        HEAD_TYPE_ENCRYPTION => Block::Encryption,
        HEAD_TYPE_ENDARC => Block::EndArchive,
        HEAD_TYPE_FILE => Block::File(parse_file_header(
            &mut cursor,
            extra_size,
            head_flags,
            header.len() as u64,
        )?),
        // SERVICE (3) ve diğerleri içerik olarak ilgilenilmiyor.
        HEAD_TYPE_SERVICE => Block::Service,
        other => Block::Unknown {
            head_type: other,
            skippable: head_flags & HEAD_FLAG_SKIP_IF_UNKNOWN != 0,
        },
    };
    Ok((block, data_size))
}

fn parse_file_header(
    cursor: &mut io::Cursor<&[u8]>,
    extra_size: u64,
    head_flags: u64,
    header_len: u64,
) -> Result<FileEntry, RarError> {
    let file_flags = read_vint_slice(cursor)?;
    let unpacked_size = read_vint_slice(cursor)?;
    let _attributes = read_vint_slice(cursor)?;
    if file_flags & FILE_FLAG_UTIME != 0 {
        skip_slice(cursor, 4, "mtime")?;
    }
    if file_flags & FILE_FLAG_CRC32 != 0 {
        skip_slice(cursor, 4, "dosya CRC32")?;
    }
    let compression_info = read_vint_slice(cursor)?;
    let _host_os = read_vint_slice(cursor)?;
    let name_size = read_vint_slice(cursor)?;

    let extra_start = header_len
        .checked_sub(extra_size)
        .ok_or_else(|| RarError::Header("extra alanı başlık boyutunu aşıyor".into()))?;
    if name_size > extra_start.saturating_sub(cursor.position()) {
        return Err(RarError::Header("dosya adı başlık sınırını aşıyor".into()));
    }
    let name_len = usize::try_from(name_size)
        .map_err(|_| RarError::Header("dosya adı belleğe sığmıyor".into()))?;
    let name_start = cursor.position() as usize;
    let name_bytes = &cursor.get_ref()[name_start..name_start + name_len];
    let name = String::from_utf8(name_bytes.to_vec())
        .map_err(|_| RarError::Header("dosya adı geçerli UTF-8 değil".into()))?;
    cursor.set_position(cursor.position() + name_size);
    if cursor.position() > extra_start {
        return Err(RarError::Header("dosya başlığı alanları çakışıyor".into()));
    }

    // Extra kayıtları başlığın sonundadır: SIZE(vint, ID vint'i + DATA),
    // ID(vint), DATA.
    cursor.set_position(extra_start);
    let mut encrypted = false;
    while cursor.position() < header_len {
        let record_size = read_vint_slice(cursor)?;
        let record_id = read_vint_slice(cursor)?;
        if record_id == EXTRA_RECORD_CRYPT {
            encrypted = true;
        }
        let id_len = vint_len(record_id);
        let payload = record_size
            .checked_sub(id_len)
            .ok_or_else(|| RarError::Header("extra kayıt boyutu geçersiz".into()))?;
        skip_slice(cursor, payload, "extra kayıt verisi")?;
    }

    Ok(FileEntry {
        name,
        unpacked_size,
        data_size: 0, // çağıran HEAD_FLAGS'taki DATA_SIZE ile doldurur
        data_offset: 0,
        split_before: head_flags & HEAD_FLAG_SPLIT_BEFORE != 0,
        split_after: head_flags & HEAD_FLAG_SPLIT_AFTER != 0,
        store: (compression_info >> 7) & 0x7 == 0,
        solid: compression_info & 0x40 != 0,
        encrypted,
        is_dir: file_flags & FILE_FLAG_DIRECTORY != 0,
    })
}

/// Bellek içi dilim üzerinde RAR5 vint okur (başlık gövdesi zaten RAM'de).
fn read_vint_slice(cursor: &mut io::Cursor<&[u8]>) -> Result<u64, RarError> {
    let mut value = 0u64;
    for index in 0..10u32 {
        let mut byte = [0u8; 1];
        cursor
            .read_exact(&mut byte)
            .map_err(|_| RarError::Header("vint başlık sonunu aşıyor".into()))?;
        if index == 9 && byte[0] & 0x7E != 0 {
            return Err(RarError::Header("vint u64 sınırını aşıyor".into()));
        }
        value |= u64::from(byte[0] & 0x7F) << (7 * index);
        if byte[0] & 0x80 == 0 {
            return Ok(value);
        }
    }
    Err(RarError::Header("vint çok uzun".into()))
}

fn vint_len(mut value: u64) -> u64 {
    let mut len = 1;
    while value >= 0x80 {
        value >>= 7;
        len += 1;
    }
    len
}

fn skip_slice(cursor: &mut io::Cursor<&[u8]>, count: u64, label: &str) -> Result<(), RarError> {
    let target = cursor
        .position()
        .checked_add(count)
        .filter(|&target| target <= cursor.get_ref().len() as u64)
        .ok_or_else(|| RarError::Header(format!("{label} alanı başlık sonunu aşıyor")))?;
    cursor.set_position(target);
    Ok(())
}

/// Cilt düzeni verilen sanal kaynaktan oynatma planını kurar: her cildi
/// tarar, aynı isimli split parçalarını zincirler, en büyük oynatılabilir
/// medyayı seçer ve parça eşlemini doğrular.
fn build_fragment_map<R: Read + Seek>(
    reader: &mut R,
    volumes: &[(u64, u64)],
) -> Result<FragmentMap, RarError> {
    // (küçük harf ad) -> parça listesi; ekleme sırası korunur.
    let mut groups: Vec<(String, Vec<FragmentPart>)> = Vec::new();

    for (volume_index, &(volume_start, volume_len)) in volumes.iter().enumerate() {
        let volume_end = volume_start
            .checked_add(volume_len)
            .ok_or_else(|| RarError::InvalidLayout("cilt ofseti taştı".into()))?;
        reader.seek(SeekFrom::Start(volume_start))?;
        for entry in parse_volume(reader, volume_start, volume_end)? {
            if entry.is_dir {
                continue;
            }
            let part = FragmentPart {
                volume_index,
                set_offset: volume_start
                    .checked_add(entry.data_offset)
                    .ok_or_else(|| RarError::InvalidLayout("parça ofseti taştı".into()))?,
                entry,
            };
            let key = part.entry.name.to_ascii_lowercase();
            if part.entry.split_before || part.entry.split_after {
                match groups.iter_mut().find(|(name, _)| *name == key) {
                    Some((_, parts)) => parts.push(part),
                    None => groups.push((key, vec![part])),
                }
            } else {
                // Tek ciltlik dosyalar kendi grubudur; aynı isimli bir split
                // zinciriyle karıştırılmaz.
                groups.push((key, vec![part]));
            }
        }
    }

    // Oynatılabilir gruplar arasından en büyüğü seç. unpacked_size her
    // parçanın başlığında toplam dosya boyutunu taşır.
    let (_, parts) = groups
        .iter()
        .filter(|(_, parts)| is_playable_media_filename(&parts[0].entry.name))
        .max_by_key(|(_, parts)| parts[0].entry.unpacked_size)
        .ok_or(RarError::NoPlayableMedia)?;

    validate_and_build(parts)
}

struct FragmentPart {
    volume_index: usize,
    set_offset: u64,
    entry: FileEntry,
}

fn validate_and_build(parts: &[FragmentPart]) -> Result<FragmentMap, RarError> {
    for part in parts {
        if part.entry.encrypted {
            return Err(RarError::Encrypted);
        }
        if !part.entry.store || part.entry.solid {
            return Err(RarError::UnsupportedCompression);
        }
    }

    if parts.len() == 1 {
        let entry = &parts[0].entry;
        if entry.split_before || entry.split_after {
            return Err(RarError::InvalidLayout(format!(
                "`{}` tek ciltte ama split bayrağı taşıyor; set eksik",
                entry.name
            )));
        }
    } else {
        for (index, part) in parts.iter().enumerate() {
            let first = index == 0;
            let last = index == parts.len() - 1;
            let flags_ok = if first {
                !part.entry.split_before && part.entry.split_after
            } else if last {
                part.entry.split_before && !part.entry.split_after
            } else {
                part.entry.split_before && part.entry.split_after
            };
            if !flags_ok {
                return Err(RarError::InvalidLayout(format!(
                    "`{}` split zinciri bayrakları bozuk (parça {}/{})",
                    part.entry.name,
                    index + 1,
                    parts.len()
                )));
            }
        }
        for window in parts.windows(2) {
            if window[1].volume_index != window[0].volume_index + 1 {
                return Err(RarError::InvalidLayout(format!(
                    "`{}` split parçaları ardışık ciltlerde değil; set eksik",
                    window[0].entry.name
                )));
            }
        }
    }

    let total_len = parts.iter().try_fold(0u64, |total, part| {
        total
            .checked_add(part.entry.data_size)
            .ok_or_else(|| RarError::InvalidLayout("parça boyut toplamı taştı".into()))
    })?;
    let declared = parts[0].entry.unpacked_size;
    if total_len != declared {
        return Err(RarError::InvalidLayout(format!(
            "`{}` parça toplamı {total_len} bayt, başlık {declared} bayt bildiriyor; set eksik veya bozuk",
            parts[0].entry.name
        )));
    }

    let mut fragments = Vec::with_capacity(parts.len());
    let mut starts = Vec::with_capacity(parts.len());
    let mut cursor = 0u64;
    for part in parts {
        fragments.push(Fragment {
            set_offset: part.set_offset,
            len: part.entry.data_size,
        });
        starts.push(cursor);
        cursor += part.entry.data_size;
    }

    Ok(FragmentMap {
        fragments,
        starts,
        total_len,
        filename: parts[0].entry.name.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn vint(mut value: u64) -> Vec<u8> {
        let mut out = Vec::new();
        loop {
            let mut byte = (value & 0x7F) as u8;
            value >>= 7;
            if value != 0 {
                byte |= 0x80;
            }
            out.push(byte);
            if value == 0 {
                break;
            }
        }
        out
    }

    struct FileSpec<'a> {
        name: &'a str,
        unpacked: u64,
        data: &'a [u8],
        split_before: bool,
        split_after: bool,
        method: u64,
        solid: bool,
        crc: bool,
        crypt_extra: bool,
        directory: bool,
    }

    fn store_spec<'a>(name: &'a str, unpacked: u64, data: &'a [u8]) -> FileSpec<'a> {
        FileSpec {
            name,
            unpacked,
            data,
            split_before: false,
            split_after: false,
            method: 0,
            solid: false,
            crc: false,
            crypt_extra: false,
            directory: false,
        }
    }

    /// HEAD_SIZE vint'i + gövde + CRC'si doğru hesaplanmış RAR5 bloğu üretir.
    fn block(head_type: u64, head_flags: u64, extra: &[u8], data: &[u8], body: &[u8]) -> Vec<u8> {
        let mut flags = head_flags;
        if !extra.is_empty() {
            flags |= 0x01;
        }
        if !data.is_empty() {
            flags |= 0x02;
        }
        let mut payload = vint(head_type);
        payload.extend(vint(flags));
        if !extra.is_empty() {
            payload.extend(vint(extra.len() as u64));
        }
        if !data.is_empty() {
            payload.extend(vint(data.len() as u64));
        }
        payload.extend_from_slice(body);
        payload.extend_from_slice(extra);

        let size_vint = vint(payload.len() as u64);
        let mut crc_input = size_vint.clone();
        crc_input.extend_from_slice(&payload);

        let mut out = crc32fast::hash(&crc_input).to_le_bytes().to_vec();
        out.extend(size_vint);
        out.extend(payload);
        out.extend_from_slice(data);
        out
    }

    fn main_block() -> Vec<u8> {
        block(HEAD_TYPE_MAIN, 0, &[], &[], &vint(0))
    }

    fn endarc_block() -> Vec<u8> {
        block(HEAD_TYPE_ENDARC, 0, &[], &[], &vint(0))
    }

    fn file_block(spec: &FileSpec<'_>) -> Vec<u8> {
        let mut flags = 0u64;
        if spec.split_before {
            flags |= HEAD_FLAG_SPLIT_BEFORE;
        }
        if spec.split_after {
            flags |= HEAD_FLAG_SPLIT_AFTER;
        }
        let mut file_flags = 0u64;
        if spec.directory {
            file_flags |= FILE_FLAG_DIRECTORY;
        }
        if spec.crc {
            file_flags |= FILE_FLAG_CRC32;
        }
        let mut body = vint(file_flags);
        body.extend(vint(spec.unpacked));
        body.extend(vint(0)); // attributes
        if spec.crc {
            body.extend_from_slice(&crc32fast::hash(spec.data).to_le_bytes());
        }
        let mut compression_info = spec.method << 7;
        if spec.solid {
            compression_info |= 0x40;
        }
        body.extend(vint(compression_info));
        body.extend(vint(1)); // host os: unix
        body.extend(vint(spec.name.len() as u64));
        body.extend_from_slice(spec.name.as_bytes());

        let extra = if spec.crypt_extra {
            let mut record = vint(EXTRA_RECORD_CRYPT);
            let mut sized = vint(record.len() as u64);
            sized.append(&mut record);
            sized
        } else {
            Vec::new()
        };
        block(HEAD_TYPE_FILE, flags, &extra, spec.data, &body)
    }

    fn volume(blocks: &[Vec<u8>]) -> Vec<u8> {
        let mut out = RAR5_SIGNATURE.to_vec();
        out.extend(main_block());
        for bytes in blocks {
            out.extend_from_slice(bytes);
        }
        out.extend(endarc_block());
        out
    }

    fn layout(volumes: &[Vec<u8>]) -> Vec<(u64, u64)> {
        let mut out = Vec::with_capacity(volumes.len());
        let mut cursor = 0u64;
        for volume in volumes {
            out.push((cursor, volume.len() as u64));
            cursor += volume.len() as u64;
        }
        out
    }

    fn concat(volumes: &[Vec<u8>]) -> Vec<u8> {
        let mut out = Vec::new();
        for volume in volumes {
            out.extend_from_slice(volume);
        }
        out
    }

    #[test]
    fn tek_ciltli_store_dosya_eslenir() {
        let data: Vec<u8> = (0..500u32).map(|i| (i % 251) as u8).collect();
        let volume = volume(&[file_block(&store_spec("film.mkv", 500, &data))]);
        let bytes = concat(std::slice::from_ref(&volume));
        let map = build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume])).unwrap();

        assert_eq!(map.filename, "film.mkv");
        assert_eq!(map.total_len, 500);
        assert_eq!(map.fragments.len(), 1);
        // Veri, imza + MAIN + FILE başlığından sonra başlar.
        let slice = &map.slices(0..500);
        assert_eq!(slice.len(), 1);
        assert_eq!(slice[0].end - slice[0].start, 500);
    }

    #[test]
    fn uc_ciltli_split_set_zincirlenir() {
        let a: Vec<u8> = (0..100u32).map(|i| i as u8).collect();
        let b: Vec<u8> = (0..120u32).map(|i| (255 - i) as u8).collect();
        let c: Vec<u8> = (0..80u32).map(|i| (i * 3) as u8).collect();
        let total = (a.len() + b.len() + c.len()) as u64;

        let jpg = store_spec("ornek.jpg", 50, &[7u8; 50]);
        let mut first = store_spec("film.mkv", total, &a);
        first.split_after = true;
        let mut middle = store_spec("film.mkv", total, &b);
        middle.split_before = true;
        middle.split_after = true;
        let mut last = store_spec("film.mkv", total, &c);
        last.split_before = true;

        let volumes = vec![
            volume(&[file_block(&jpg), file_block(&first)]),
            volume(&[file_block(&middle)]),
            volume(&[file_block(&last)]),
        ];
        let bytes = concat(&volumes);
        let map = build_fragment_map(&mut Cursor::new(bytes), &layout(&volumes)).unwrap();

        assert_eq!(map.filename, "film.mkv");
        assert_eq!(map.total_len, total);
        assert_eq!(map.fragments.len(), 3);

        // Ortadaki parçayı kesen bir aralık iki dilime bölünmeli.
        let slices = map.slices(90..130);
        assert_eq!(slices.len(), 2);
        assert_eq!(slices[0].end - slices[0].start, 10);
        assert_eq!(slices[1].end - slices[1].start, 30);

        // Tüm aralık parça sınırlarını doğru sırayla geçmeli.
        let full = map.slices(0..total);
        assert_eq!(full.len(), 3);
        let reconstructed: Vec<u8> = full
            .iter()
            .flat_map(|range| {
                let bytes = concat(&volumes);
                bytes[range.start as usize..range.end as usize].to_vec()
            })
            .collect();
        let mut expected = a.clone();
        expected.extend_from_slice(&b);
        expected.extend_from_slice(&c);
        assert_eq!(reconstructed, expected);
    }

    #[test]
    fn sikistirilmis_girdi_reddedilir() {
        let mut spec = store_spec("film.mkv", 100, &[0u8; 100]);
        spec.method = 3;
        let volume = volume(&[file_block(&spec)]);
        let bytes = concat(std::slice::from_ref(&volume));
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume])),
            Err(RarError::UnsupportedCompression)
        ));
    }

    #[test]
    fn solid_girdi_reddedilir() {
        let mut spec = store_spec("film.mkv", 100, &[0u8; 100]);
        spec.solid = true;
        let volume = volume(&[file_block(&spec)]);
        let bytes = concat(std::slice::from_ref(&volume));
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume])),
            Err(RarError::UnsupportedCompression)
        ));
    }

    #[test]
    fn rar4_imzasi_reddedilir() {
        let mut bytes = RAR4_SIGNATURE.to_vec();
        bytes.extend_from_slice(&[0u8; 64]);
        let len = bytes.len() as u64;
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &[(0, len)]),
            Err(RarError::UnsupportedVersion)
        ));
    }

    #[test]
    fn sifreli_girdi_reddedilir() {
        let mut spec = store_spec("film.mkv", 100, &[0u8; 100]);
        spec.crypt_extra = true;
        let volume = volume(&[file_block(&spec)]);
        let bytes = concat(std::slice::from_ref(&volume));
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume])),
            Err(RarError::Encrypted)
        ));
    }

    #[test]
    fn bozuk_crc_reddedilir() {
        let volume = volume(&[file_block(&store_spec("film.mkv", 4, &[1, 2, 3, 4]))]);
        let mut bytes = concat(std::slice::from_ref(&volume));
        // MAIN bloğunun CRC baytını boz (imza 8 bayt).
        bytes[8] ^= 0xFF;
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume])),
            Err(RarError::Header(_))
        ));
    }

    #[test]
    fn boyut_toplami_tutmazsa_reddedilir() {
        let mut first = store_spec("film.mkv", 999, &[0u8; 100]);
        first.split_after = true;
        let mut last = store_spec("film.mkv", 999, &[0u8; 100]);
        last.split_before = true;
        let volumes = vec![
            volume(&[file_block(&first)]),
            volume(&[file_block(&last)]),
        ];
        let bytes = concat(&volumes);
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&volumes)),
            Err(RarError::InvalidLayout(_))
        ));
    }

    #[test]
    fn zincir_bayragi_bozuksa_reddedilir() {
        // Son parçada split_before eksik.
        let mut first = store_spec("film.mkv", 200, &[0u8; 100]);
        first.split_after = true;
        let last = store_spec("film.mkv", 200, &[0u8; 100]);
        let volumes = vec![
            volume(&[file_block(&first)]),
            volume(&[file_block(&last)]),
        ];
        let bytes = concat(&volumes);
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&volumes)),
            Err(RarError::InvalidLayout(_))
        ));
    }

    #[test]
    fn medya_olmayan_set_reddedilir() {
        let volume = volume(&[file_block(&store_spec("belge.txt", 10, &[0u8; 10]))]);
        let bytes = concat(std::slice::from_ref(&volume));
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume])),
            Err(RarError::NoPlayableMedia)
        ));
    }

    #[test]
    fn endarc_eksikse_cilt_siniri_temiz_son_sayilir() {
        let mut bytes = RAR5_SIGNATURE.to_vec();
        bytes.extend(main_block());
        bytes.extend(file_block(&store_spec("film.mkv", 4, &[9, 9, 9, 9])));
        let len = bytes.len() as u64;
        let map = build_fragment_map(&mut Cursor::new(bytes), &[(0, len)]).unwrap();
        assert_eq!(map.total_len, 4);
    }

    #[test]
    fn fragment_map_sinir_gecisleri() {
        let map = FragmentMap {
            fragments: vec![
                Fragment { set_offset: 1000, len: 10 },
                Fragment { set_offset: 5000, len: 5 },
            ],
            starts: vec![0, 10],
            total_len: 15,
            filename: "film.mkv".into(),
        };
        assert_eq!(map.slices(0..15), vec![1000..1010, 5000..5005]);
        assert_eq!(map.slices(9..11), vec![1009..1010, 5000..5001]);
        assert_eq!(map.slices(12..15), vec![5002..5005]);
    }
}
