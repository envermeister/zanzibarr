//! Çok ciltli RAR5 STORE yayınlarını sanal, seek edilebilir medya dosyasına
//! dönüştürür.
//!
//! RAR ciltleri diske indirilmez. Her `.partNN.rar` (veya eski usul
//! `.rar`/`.rNN`) dosyası mevcut NNTP+yEnc kaynağıyla açılır, tek bir sanal
//! byte uzayında birleştirilir ve her cildin blok başlıkları o uzaydan tembel
//! olarak okunur. İçerideki medya STORE ise her parçanın veri aralığı doğrudan
//! sunulur; şifreliyse ve NZB parolası biliniyorsa istenen bloklar yerinde
//! çözülür. Sıkıştırılmış (method != STORE) ve solid arşivler, rastgele
//! seek'i bozmamak için açıkça reddedilir. RAR4 ve eski biçim desteklenmez:
//! blok düzeni farklıdır ve gerçek bir örnek olmadan parser'ı doğrulamak
//! mümkün değildir.
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
//!
//! Başlık-şifreli (`-hp`) arşivler: imza sonrası ilk blok ENCRYPTION (düz)
//! olup tuz ve KDF tur sayısını taşır; sonraki HER blok `[IV(16)][şifreli:
//! CRC(4)+HEAD_SIZE(vint)+gövde, 16'ya yuvarlı]` biçimindedir. Dosya verisi
//! ayrı bir anahtarla (dosya crypt extra kaydındaki tuz/InitV) AES-256-CBC'dir
//! ve CBC zinciri split parçalar arasında kesintisiz devam eder (unrar
//! `arcread.cpp`/`crypt5.cpp` + gerçek `-hp` arşivleriyle doğrulandı). Parola
//! NZB `password` metasından gelir; PswCheck eşleşmesi parolayı doğrular.

use std::fmt;
use std::io::{self, Read, Seek, SeekFrom};
use std::ops::Range;
use std::sync::Arc;

use thiserror::Error;
use tokio::io::{AsyncWrite, AsyncWriteExt};
use tokio::sync::watch;
use zeroize::Zeroizing;

use super::archive::{
    cancellation_requested, run_blocking_cancellable, validate_range, BlockingArchiveReader,
    BlockingTaskError, NntpVolumeSet, VolumeSetError,
};
use super::nntp::{NntpPool, TlsNntpConnector};
use super::nzb::{is_playable_media_filename, NzbFile};
use super::rarcrypt::{
    self, AES_BLOCK_SIZE, INITV_SIZE, PSW_CHECK_SIZE, SALT_SIZE,
};
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
    #[error("RAR arşivi parola korumalı ve NZB parola içermiyor")]
    Encrypted,
    #[error("NZB'deki parola RAR arşivine uymuyor")]
    WrongPassword,
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

/// ENCRYPTION bloğundan okunan arşiv şifreleme parametreleri.
#[derive(Debug, Clone)]
struct EncryptionHead {
    salt: [u8; SALT_SIZE],
    lg2_count: u8,
    /// PswCheck + sağlaması (SHA256'nın ilk 4 baytı) geçerliyse Some;
    /// sağlama bozuksa unrar'ın yaptığı gibi yok sayılır.
    psw_check: Option<[u8; PSW_CHECK_SIZE]>,
}

/// Dosya başlığındaki crypt extra kaydından (FHEXTRA_CRYPT) okunan veri
/// şifreleme parametreleri. Tüm split parçalar aynı değerleri taşır.
#[derive(Debug, Clone, PartialEq, Eq)]
struct FileCrypt {
    salt: [u8; SALT_SIZE],
    initv: [u8; INITV_SIZE],
    lg2_count: u8,
    psw_check: Option<[u8; PSW_CHECK_SIZE]>,
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
    crypt: Option<FileCrypt>,
    is_dir: bool,
}

/// Sanal set uzayında bir medya parçası.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Fragment {
    set_offset: u64,
    /// Çözülmüş akıştaki uzunluk (son parçada padding hariç).
    len: u64,
    /// Set uzayındaki şifreli uzunluk; şifresizde `len` ile aynı.
    cipher_len: u64,
}

/// Seçilen dosyanın veri çözümü için türetilmiş anahtar ve başlatma vektörü.
struct DataCrypt {
    key: Zeroizing<[u8; 32]>,
    initv: [u8; INITV_SIZE],
}

/// Anahtarın log/Debug çıktısına sızmasını engeller.
impl fmt::Debug for DataCrypt {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.debug_struct("DataCrypt").finish_non_exhaustive()
    }
}

/// Çözülmüş medya byte uzayını sanal set uzayındaki parça aralıklarına eşler.
#[derive(Debug)]
struct FragmentMap {
    fragments: Vec<Fragment>,
    /// Her parçanın çözülmüş uzaydaki başlangıcı (prefix toplamı).
    starts: Vec<u64>,
    total_len: u64,
    filename: String,
    crypt: Option<DataCrypt>,
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

    /// Şifreli bir parça grubu için `range`'i (çözülmüş uzay) okuma
    /// pencerelerine çevirir. CBC zinciri parçalar arasında kesintisiz
    /// ilerlediğinden her pencerenin IV'si ya dosyanın InitV'si (global ilk
    /// blok) ya da mantıksal şifreli akışın bir önceki bloğudur.
    fn cipher_windows(&self, range: Range<u64>) -> Vec<CipherWindow> {
        let mut out = Vec::new();
        let mut cursor = range.start;
        while cursor < range.end {
            let index = self.starts.partition_point(|&start| start <= cursor) - 1;
            let fragment = self.fragments[index];
            let within = cursor - self.starts[index];
            let take = (range.end - cursor).min(fragment.len - within);

            let aligned = within / AES_BLOCK_SIZE * AES_BLOCK_SIZE;
            let end = rarcrypt::round_up_block(within + take)
                .unwrap_or(fragment.cipher_len)
                .min(fragment.cipher_len);
            let iv = if aligned > 0 {
                // IV, aynı parçanın bir önceki şifreli bloğu.
                Some((fragment.set_offset + aligned - AES_BLOCK_SIZE)..(fragment.set_offset + aligned))
            } else if index > 0 {
                // Parça başı: zincir bir önceki parçanın son bloğundan gelir.
                let previous = self.fragments[index - 1];
                Some(
                    (previous.set_offset + previous.cipher_len - AES_BLOCK_SIZE)
                        ..(previous.set_offset + previous.cipher_len),
                )
            } else {
                None // Global ilk blok: dosyanın InitV'si.
            };
            out.push(CipherWindow {
                data: (fragment.set_offset + aligned)..(fragment.set_offset + end),
                iv,
                skip: within - aligned,
                take,
            });
            cursor += take;
        }
        out
    }
}

/// Şifreli veriden okunacak tek bir 16-hizalı pencere ve çözüm talimatı.
#[derive(Debug, Clone, PartialEq, Eq)]
struct CipherWindow {
    /// Okunacak şifreli baytlar (16 hizalı), set uzayında.
    data: Range<u64>,
    /// IV olarak okunacak 16 bayt; `None` ise dosyanın InitV'si kullanılır.
    iv: Option<Range<u64>>,
    /// Çözülmüş tamponun başından atlanacak bayt sayısı.
    skip: u64,
    /// Çözülmüş tampondan yazılacak bayt sayısı.
    take: u64,
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
        password: Option<String>,
    ) -> Result<Self, RarError> {
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
            build_fragment_map(&mut reader, &layout, password.as_deref())
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

    /// Şifreli STORE verisini 16-hizalı pencerelerle okuyup çözer. CBC
    /// zinciri split parçalar arasında kesintisizdir; IV, global ilk blok için
    /// dosyanın InitV'si, diğerlerinde bir önceki şifreli bloktur.
    async fn write_encrypted_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        let crypt = self.map.crypt.as_ref().expect("şifreli okuma planı mevcut");
        for window in self.map.cipher_windows(range) {
            let iv: [u8; INITV_SIZE] = match window.iv {
                None => crypt.initv,
                Some(iv_range) => self
                    .archive
                    .read_range_bytes(iv_range)
                    .await?
                    .try_into()
                    .map_err(|_| io::Error::other("RAR CBC zinciri bozuk"))?,
            };
            let mut buffer = self.archive.read_range_bytes(window.data).await?;
            if !rarcrypt::decrypt_cbc(&crypt.key, &iv, &mut buffer) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "RAR şifreli veri çözülemedi",
                ));
            }
            let skip = usize::try_from(window.skip)
                .map_err(|_| io::Error::other("RAR çözüm ofseti taştı"))?;
            let take = usize::try_from(window.take)
                .map_err(|_| io::Error::other("RAR çözüm boyutu taştı"))?;
            out.write_all(&buffer[skip..skip + take]).await?;
        }
        out.flush().await
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
        if self.map.crypt.is_some() {
            return self.write_encrypted_range(range, out).await;
        }
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

/// Düz (şifresiz) bir blok başlığını CRC doğrulamalı okur.
fn read_plain_block<R: Read + Seek>(
    parser: &mut VolumeParser<'_, R>,
) -> Result<(Block, u64), RarError> {
    let mut crc_bytes = [0u8; 4];
    parser.read_exact(&mut crc_bytes)?;
    let expected_crc = u32::from_le_bytes(crc_bytes);

    let mut hashing = HashingReader {
        inner: parser,
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
    parse_block_header(&header)
}

/// Çözülmüş `[size_vint][gövde]` tamponundan vint uzunluğunu ve HEAD_SIZE'ı
/// okur; çözülmüş tamponun toplam (şifreli alan hariç) uzunluğunu döndürür.
fn decrypted_header_len(buffer: &[u8]) -> Result<(u64, u64), RarError> {
    let mut cursor = io::Cursor::new(buffer);
    let header_size = read_vint_slice(&mut cursor)?;
    if header_size == 0 || header_size > MAX_BLOCK_HEADER_SIZE {
        return Err(RarError::Header(format!(
            "blok başlığı {header_size} bayt; güvenli sınır {MAX_BLOCK_HEADER_SIZE}"
        )));
    }
    Ok((cursor.position(), header_size))
}

/// Başlık-şifreli (`-hp`) arşivde bir blok başlığını okur: disk düzeni
/// `[IV(16)][şifreli: CRC(4)+HEAD_SIZE(vint)+gövde, 16'ya yuvarlı]`. İlk
/// çözülen bloktan HEAD_SIZE öğrenilir, kalan çözülür ve CRC doğrulanır.
fn read_encrypted_block<R: Read + Seek>(
    parser: &mut VolumeParser<'_, R>,
    key: &[u8; 32],
) -> Result<(Block, u64), RarError> {
    let mut iv = [0u8; INITV_SIZE];
    parser.read_exact(&mut iv)?;

    // İlk 16 bayt: CRC(4) + HEAD_SIZE vint'i (vint en çok 10 bayt; 4+10 ≤ 16).
    let mut first = [0u8; AES_BLOCK_SIZE as usize];
    parser.read_exact(&mut first)?;
    let first_cipher = first;
    if !rarcrypt::decrypt_cbc(key, &iv, &mut first) {
        return Err(RarError::Header("şifreli blok çözülemedi".into()));
    }
    let expected_crc = u32::from_le_bytes([first[0], first[1], first[2], first[3]]);
    let (size_vint_len, header_size) = decrypted_header_len(&first[4..])?;
    let plain_len = 4 + size_vint_len + header_size;
    let encrypted_len = rarcrypt::round_up_block(plain_len)
        .ok_or_else(|| RarError::Header("şifreli blok boyutu taştı".into()))?;
    if encrypted_len > parser.remaining() + AES_BLOCK_SIZE {
        return Err(RarError::Header(
            "şifreli blok cilt sonunu aşıyor; set eksik veya bozuk".into(),
        ));
    }

    let rest_len = usize::try_from(encrypted_len - AES_BLOCK_SIZE)
        .map_err(|_| RarError::Header("şifreli blok belleğe sığmıyor".into()))?;
    let mut plain = Vec::with_capacity(encrypted_len as usize);
    plain.extend_from_slice(&first);
    if rest_len > 0 {
        let mut rest = vec![0u8; rest_len];
        parser.read_exact(&mut rest)?;
        // CBC zinciri: devam bloklarının IV'si ilk şifreli blok.
        let chain_iv: &[u8; INITV_SIZE] = &first_cipher;
        if !rarcrypt::decrypt_cbc(key, chain_iv, &mut rest) {
            return Err(RarError::Header("şifreli blok çözülemedi".into()));
        }
        plain.extend_from_slice(&rest);
    }
    plain.truncate(plain_len as usize);

    let actual_crc = crc32fast::hash(&plain[4..]);
    if actual_crc != expected_crc {
        return Err(RarError::Header(format!(
            "şifreli blok CRC uyuşmazlığı: beklenen {expected_crc:#x}, bulunan {actual_crc:#x}"
        )));
    }
    parse_block_header(&plain[(4 + size_vint_len) as usize..])
}

/// Tek cildin bloklarını okuyup FILE girdilerini döndürür. `reader`, cildin
/// ilk baytında (imza) konumlanmış olmalı; `volume_start`/`volume_end` sanal
/// set uzayındaki cilt sınırlarıdır. Cilt ENCRYPTION bloğuyla başlıyorsa
/// `password` ile anahtar türetilir ve sonraki bloklar şifreli okunur;
/// parola yoksa [`RarError::Encrypted`], PswCheck tutmazsa
/// [`RarError::WrongPassword`] döner.
fn parse_volume<R: Read + Seek>(
    reader: &mut R,
    volume_start: u64,
    volume_end: u64,
    password: Option<&str>,
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

    let mut header_key: Option<Zeroizing<[u8; 32]>> = None;
    let mut entries = Vec::new();
    loop {
        // ENDARC'ta döngü kırılır; ENDARC yoksa cilt sınırı temiz son sayılır.
        // Kalan baytlar anlamlı bir blok olamayacak kadar kısaysa dur
        // (şifreli blok: 16 IV + en az 16 şifreli bayt).
        let minimum_block = if header_key.is_some() {
            INITV_SIZE as u64 + AES_BLOCK_SIZE
        } else {
            4
        };
        if parser.remaining() < minimum_block {
            break;
        }

        let (block, data_size) = match &header_key {
            None => read_plain_block(&mut parser)?,
            Some(key) => read_encrypted_block(&mut parser, key)?,
        };

        match block {
            Block::Main | Block::Service => {
                parser.skip(data_size)?;
            }
            Block::Encryption(encryption) => {
                if header_key.is_some() {
                    return Err(RarError::InvalidLayout(
                        "ENCRYPTION bloğu yalnız cildin ilk bloğu olabilir".into(),
                    ));
                }
                let password = password.ok_or(RarError::Encrypted)?;
                let derived = rarcrypt::kdf5(password.as_bytes(), &encryption.salt, encryption.lg2_count)
                    .ok_or_else(|| {
                        RarError::Header(format!(
                            "RAR KDF tur sayısı (2^{}) güvenli sınırı aşıyor",
                            encryption.lg2_count
                        ))
                    })?;
                if let Some(expected) = encryption.psw_check {
                    if rarcrypt::psw_check_fold(&derived.psw_check_value) != expected {
                        return Err(RarError::WrongPassword);
                    }
                }
                header_key = Some(derived.key);
            }
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
    Encryption(EncryptionHead),
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
        HEAD_TYPE_ENCRYPTION => Block::Encryption(parse_encryption_header(&mut cursor)?),
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

/// ENCRYPTION bloğunun gövdesini çözer: CryptVersion(vint), CryptFlags(vint),
/// KdfCount(1), Salt(16), [PswCheck(8) + CheckCsum(4)].
fn parse_encryption_header(cursor: &mut io::Cursor<&[u8]>) -> Result<EncryptionHead, RarError> {
    let crypt_version = read_vint_slice(cursor)?;
    if crypt_version != 0 {
        return Err(RarError::Header(format!(
            "desteklenmeyen RAR şifreleme sürümü: {crypt_version}"
        )));
    }
    let crypt_flags = read_vint_slice(cursor)?;
    let mut lg2_count = [0u8; 1];
    read_slice(cursor, &mut lg2_count, "KDF tur sayısı")?;
    let mut salt = [0u8; SALT_SIZE];
    read_slice(cursor, &mut salt, "şifreleme tuzu")?;

    let psw_check = if crypt_flags & 0x01 != 0 {
        let mut check = [0u8; PSW_CHECK_SIZE];
        read_slice(cursor, &mut check, "parola doğrulama değeri")?;
        let mut csum = [0u8; 4];
        read_slice(cursor, &mut csum, "parola doğrulama sağlaması")?;
        // Sağlama bozuksa unrar'ın yaptığı gibi doğrulama değeri yok sayılır;
        // yanlış parola bu durumda başlık CRC hatasıyla yakalanır.
        use sha2::Digest;
        let digest = sha2::Sha256::digest(check);
        (digest[..4] == csum).then_some(check)
    } else {
        None
    };

    Ok(EncryptionHead {
        salt,
        lg2_count: lg2_count[0],
        psw_check,
    })
}

fn read_slice(
    cursor: &mut io::Cursor<&[u8]>,
    buffer: &mut [u8],
    label: &str,
) -> Result<(), RarError> {
    cursor
        .read_exact(buffer)
        .map_err(|_| RarError::Header(format!("{label} alanı başlık sonunu aşıyor")))
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
    let mut crypt = None;
    while cursor.position() < header_len {
        let record_size = read_vint_slice(cursor)?;
        let record_id = read_vint_slice(cursor)?;
        let id_len = vint_len(record_id);
        let payload = record_size
            .checked_sub(id_len)
            .ok_or_else(|| RarError::Header("extra kayıt boyutu geçersiz".into()))?;
        if record_id == EXTRA_RECORD_CRYPT {
            if crypt.is_some() {
                return Err(RarError::Header("birden fazla crypt extra kaydı".into()));
            }
            let payload_len = usize::try_from(payload)
                .map_err(|_| RarError::Header("crypt extra kaydı belleğe sığmıyor".into()))?;
            let payload_start = cursor.position() as usize;
            if payload_start + payload_len > cursor.get_ref().len() {
                return Err(RarError::Header("crypt extra kaydı başlık sonunu aşıyor".into()));
            }
            let mut record_cursor = io::Cursor::new(
                &cursor.get_ref()[payload_start..payload_start + payload_len],
            );
            crypt = Some(parse_crypt_record(&mut record_cursor)?);
        }
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
        crypt,
        is_dir: file_flags & FILE_FLAG_DIRECTORY != 0,
    })
}

/// Dosya başlığındaki crypt extra kaydını (FHEXTRA_CRYPT) çözer:
/// EncVersion(vint), Flags(vint), Lg2Count(1), Salt(16), InitV(16),
/// [PswCheck(8) + CheckCsum(4)].
fn parse_crypt_record(cursor: &mut io::Cursor<&[u8]>) -> Result<FileCrypt, RarError> {
    let enc_version = read_vint_slice(cursor)?;
    if enc_version != 0 {
        return Err(RarError::Header(format!(
            "desteklenmeyen dosya şifreleme sürümü: {enc_version}"
        )));
    }
    let flags = read_vint_slice(cursor)?;
    let mut lg2_count = [0u8; 1];
    read_slice(cursor, &mut lg2_count, "KDF tur sayısı")?;
    let mut salt = [0u8; SALT_SIZE];
    read_slice(cursor, &mut salt, "dosya şifreleme tuzu")?;
    let mut initv = [0u8; INITV_SIZE];
    read_slice(cursor, &mut initv, "dosya başlatma vektörü")?;

    let psw_check = if flags & 0x01 != 0 {
        let mut check = [0u8; PSW_CHECK_SIZE];
        read_slice(cursor, &mut check, "parola doğrulama değeri")?;
        let mut csum = [0u8; 4];
        read_slice(cursor, &mut csum, "parola doğrulama sağlaması")?;
        use sha2::Digest;
        let digest = sha2::Sha256::digest(check);
        (digest[..4] == csum).then_some(check)
    } else {
        None
    };

    Ok(FileCrypt {
        salt,
        initv,
        lg2_count: lg2_count[0],
        psw_check,
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
    password: Option<&str>,
) -> Result<FragmentMap, RarError> {
    // (küçük harf ad) -> parça listesi; ekleme sırası korunur.
    let mut groups: Vec<(String, Vec<FragmentPart>)> = Vec::new();

    for (volume_index, &(volume_start, volume_len)) in volumes.iter().enumerate() {
        let volume_end = volume_start
            .checked_add(volume_len)
            .ok_or_else(|| RarError::InvalidLayout("cilt ofseti taştı".into()))?;
        reader.seek(SeekFrom::Start(volume_start))?;
        for entry in parse_volume(reader, volume_start, volume_end, password)? {
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

    validate_and_build(parts, password)
}

struct FragmentPart {
    volume_index: usize,
    set_offset: u64,
    entry: FileEntry,
}

/// Seçilen parça grubu şifreliyse dosya anahtarını türetir. Parolanın
/// doğruluğu, dosya crypt kaydındaki PswCheck ile (varsa) kanıtlanır.
fn derive_data_crypt(parts: &[FragmentPart], password: Option<&str>) -> Result<Option<DataCrypt>, RarError> {
    let Some(first) = &parts[0].entry.crypt else {
        if parts.iter().any(|part| part.entry.crypt.is_some()) {
            return Err(RarError::InvalidLayout(format!(
                "`{}` parçalarının bir kısmı şifreli, bir kısmı değil",
                parts[0].entry.name
            )));
        }
        return Ok(None);
    };

    // CBC zinciri parçalar arasında kesintisiz ilerlediğinden tüm parçalar
    // aynı tuz/InitV/tur sayısını taşımalı (RAR bunları her parça başlığına
    // aynen yazar).
    for part in parts {
        if part.entry.crypt.as_ref() != Some(first) {
            return Err(RarError::InvalidLayout(format!(
                "`{}` split parçaları farklı şifreleme parametreleri taşıyor",
                part.entry.name
            )));
        }
    }

    let password = password.ok_or(RarError::Encrypted)?;
    let derived = rarcrypt::kdf5(password.as_bytes(), &first.salt, first.lg2_count)
        .ok_or_else(|| {
            RarError::Header(format!(
                "RAR KDF tur sayısı (2^{}) güvenli sınırı aşıyor",
                first.lg2_count
            ))
        })?;
    if let Some(expected) = first.psw_check {
        if rarcrypt::psw_check_fold(&derived.psw_check_value) != expected {
            return Err(RarError::WrongPassword);
        }
    }
    Ok(Some(DataCrypt {
        key: derived.key,
        initv: first.initv,
    }))
}

fn validate_and_build(parts: &[FragmentPart], password: Option<&str>) -> Result<FragmentMap, RarError> {
    // Şifreli + parolasız (Encrypted) ve şifreli + yanlış parola
    // (WrongPassword) kontrolleri sıkıştırma kontrolünden önce gelir: önce
    // şifre çözülür, method kontrolü aynen uygulanır.
    let crypt = derive_data_crypt(parts, password)?;
    for part in parts {
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

    let cipher_total = parts.iter().try_fold(0u64, |total, part| {
        total
            .checked_add(part.entry.data_size)
            .ok_or_else(|| RarError::InvalidLayout("parça boyut toplamı taştı".into()))
    })?;
    let declared = parts[0].entry.unpacked_size;
    if crypt.is_some() {
        // Şifreli veri 16-hizalıdır: her parça blok katı, toplam şifreli
        // boyut unpacked'ın 16'ya yuvarlısıdır (padding yalnız son parçada).
        for part in parts {
            if part.entry.data_size % AES_BLOCK_SIZE != 0 {
                return Err(RarError::InvalidLayout(format!(
                    "`{}` şifreli parça boyutu 16 bayt hizalı değil; set bozuk",
                    part.entry.name
                )));
            }
        }
        if cipher_total < declared || cipher_total - declared >= AES_BLOCK_SIZE {
            return Err(RarError::InvalidLayout(format!(
                "`{}` şifreli parça toplamı {cipher_total} bayt, başlık {declared} bayt bildiriyor; set eksik veya bozuk",
                parts[0].entry.name
            )));
        }
    } else if cipher_total != declared {
        return Err(RarError::InvalidLayout(format!(
            "`{}` parça toplamı {cipher_total} bayt, başlık {declared} bayt bildiriyor; set eksik veya bozuk",
            parts[0].entry.name
        )));
    }

    let mut fragments = Vec::with_capacity(parts.len());
    let mut starts = Vec::with_capacity(parts.len());
    let mut cursor = 0u64;
    for (index, part) in parts.iter().enumerate() {
        let cipher_len = part.entry.data_size;
        // Son parçanın çözülmüş uzunluğu padding hariç tutulur; diğerleri
        // (şifreliyse blok katı olduğundan) tamamen gerçek veridir.
        let len = if crypt.is_some() && index == parts.len() - 1 {
            declared - cursor
        } else {
            cipher_len
        };
        fragments.push(Fragment {
            set_offset: part.set_offset,
            len,
            cipher_len,
        });
        starts.push(cursor);
        cursor += len;
    }

    let total_len = if crypt.is_some() { declared } else { cursor };

    Ok(FragmentMap {
        fragments,
        starts,
        total_len,
        filename: parts[0].entry.name.clone(),
        crypt,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use cbc::cipher::{BlockEncryptMut, KeyIvInit};
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
        crypt_extra: Option<TestCrypt>,
        directory: bool,
    }

    /// Testlerde dosya başlığına yazılan crypt extra parametreleri.
    #[derive(Clone, Copy)]
    struct TestCrypt {
        salt: [u8; SALT_SIZE],
        initv: [u8; INITV_SIZE],
        lg2_count: u8,
        psw_check: Option<[u8; PSW_CHECK_SIZE]>,
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
            crypt_extra: None,
            directory: false,
        }
    }

    /// Geçerli bir crypt extra kaydı gövdesi üretir.
    fn crypt_record(crypt: &TestCrypt) -> Vec<u8> {
        let mut payload = vint(0); // EncVersion
        let flags = if crypt.psw_check.is_some() { 0x01 } else { 0 };
        payload.extend(vint(flags));
        payload.push(crypt.lg2_count);
        payload.extend_from_slice(&crypt.salt);
        payload.extend_from_slice(&crypt.initv);
        if let Some(check) = crypt.psw_check {
            payload.extend_from_slice(&check);
            use sha2::Digest;
            payload.extend_from_slice(&sha2::Sha256::digest(check)[..4]);
        }
        let mut record = vint(EXTRA_RECORD_CRYPT);
        record.extend_from_slice(&payload);
        let mut sized = vint(record.len() as u64);
        sized.append(&mut record);
        sized
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

        let extra = match &spec.crypt_extra {
            Some(crypt) => crypt_record(crypt),
            None => Vec::new(),
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
        let map = build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume]), None).unwrap();

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
        let map = build_fragment_map(&mut Cursor::new(bytes), &layout(&volumes), None).unwrap();

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
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume]), None),
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
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume]), None),
            Err(RarError::UnsupportedCompression)
        ));
    }

    #[test]
    fn rar4_imzasi_reddedilir() {
        let mut bytes = RAR4_SIGNATURE.to_vec();
        bytes.extend_from_slice(&[0u8; 64]);
        let len = bytes.len() as u64;
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &[(0, len)], None),
            Err(RarError::UnsupportedVersion)
        ));
    }

    #[test]
    fn sifreli_girdi_parolasiz_reddedilir() {
        let crypt = TestCrypt {
            salt: [3u8; SALT_SIZE],
            initv: [4u8; INITV_SIZE],
            lg2_count: 4,
            psw_check: None,
        };
        let mut spec = store_spec("film.mkv", 100, &[0u8; 100]);
        spec.crypt_extra = Some(crypt);
        let volume = volume(&[file_block(&spec)]);
        let bytes = concat(std::slice::from_ref(&volume));
        let error = build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume]), None)
            .unwrap_err();
        assert!(matches!(error, RarError::Encrypted));
        assert!(error.to_string().contains("parola korumalı ve NZB parola içermiyor"));
    }

    #[test]
    fn sifreli_girdi_yanlis_parolayi_bildirir() {
        // Dosya crypt kaydındaki PswCheck, doğru parolayla üretilmişken test
        // yanlış parola verir → WrongPassword.
        let password = "dogru-parola";
        let crypt = {
            let derived = rarcrypt::kdf5(password.as_bytes(), &[9u8; SALT_SIZE], 4).unwrap();
            TestCrypt {
                salt: [9u8; SALT_SIZE],
                initv: [8u8; INITV_SIZE],
                lg2_count: 4,
                psw_check: Some(rarcrypt::psw_check_fold(&derived.psw_check_value)),
            }
        };
        let mut spec = store_spec("film.mkv", 100, &[0u8; 100]);
        spec.crypt_extra = Some(crypt);
        let volume = volume(&[file_block(&spec)]);
        let bytes = concat(std::slice::from_ref(&volume));
        let error = build_fragment_map(
            &mut Cursor::new(bytes),
            &layout(&[volume]),
            Some("yanlis-parola"),
        )
        .unwrap_err();
        assert!(matches!(error, RarError::WrongPassword));
        assert!(error.to_string().contains("parola RAR arşivine uymuyor"));
    }

    #[test]
    fn bozuk_crc_reddedilir() {
        let volume = volume(&[file_block(&store_spec("film.mkv", 4, &[1, 2, 3, 4]))]);
        let mut bytes = concat(std::slice::from_ref(&volume));
        // MAIN bloğunun CRC baytını boz (imza 8 bayt).
        bytes[8] ^= 0xFF;
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume]), None),
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
            build_fragment_map(&mut Cursor::new(bytes), &layout(&volumes), None),
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
            build_fragment_map(&mut Cursor::new(bytes), &layout(&volumes), None),
            Err(RarError::InvalidLayout(_))
        ));
    }

    #[test]
    fn medya_olmayan_set_reddedilir() {
        let volume = volume(&[file_block(&store_spec("belge.txt", 10, &[0u8; 10]))]);
        let bytes = concat(std::slice::from_ref(&volume));
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume]), None),
            Err(RarError::NoPlayableMedia)
        ));
    }

    #[test]
    fn endarc_eksikse_cilt_siniri_temiz_son_sayilir() {
        let mut bytes = RAR5_SIGNATURE.to_vec();
        bytes.extend(main_block());
        bytes.extend(file_block(&store_spec("film.mkv", 4, &[9, 9, 9, 9])));
        let len = bytes.len() as u64;
        let map = build_fragment_map(&mut Cursor::new(bytes), &[(0, len)], None).unwrap();
        assert_eq!(map.total_len, 4);
    }

    #[test]
    fn fragment_map_sinir_gecisleri() {
        let map = FragmentMap {
            fragments: vec![
                Fragment { set_offset: 1000, len: 10, cipher_len: 10 },
                Fragment { set_offset: 5000, len: 5, cipher_len: 5 },
            ],
            starts: vec![0, 10],
            total_len: 15,
            filename: "film.mkv".into(),
            crypt: None,
        };
        assert_eq!(map.slices(0..15), vec![1000..1010, 5000..5005]);
        assert_eq!(map.slices(9..11), vec![1009..1010, 5000..5001]);
        assert_eq!(map.slices(12..15), vec![5002..5005]);
    }

    /// -hp başlık şifrelemesiyle üretilmiş sentetik cilt kurar: düz
    /// ENCRYPTION bloğu + şifreli MAIN/FILE/ENDARC blokları + CBC verisi.
    struct EncryptedFixture {
        password: String,
        volumes: Vec<Vec<u8>>,
    }

    fn encrypted_block(key: &[u8; 32], plain_block: &[u8], iv: [u8; 16]) -> Vec<u8> {
        // plain_block = [crc(4)][size_vint][gövde]; 16'ya sıfır padding.
        let mut buffer = plain_block.to_vec();
        let pad = (16 - buffer.len() % 16) % 16;
        buffer.resize(buffer.len() + pad, 0);
        let mut out = iv.to_vec();
        let encryptor = cbc::Encryptor::<aes::Aes256>::new_from_slices(key, &iv).unwrap();
        let len = buffer.len();
        encryptor
            .encrypt_padded_mut::<cbc::cipher::block_padding::NoPadding>(&mut buffer, len)
            .unwrap();
        out.extend_from_slice(&buffer);
        out
    }

    /// Düz blok baytlarını (CRC+size+gövde+veri) şifreli blok düzenine çevirir.
    fn encrypt_plain_block(key: &[u8; 32], block_bytes: &[u8], iv: [u8; 16]) -> (Vec<u8>, usize) {
        // block() çıktısı: [crc(4)][size_vint][payload][data]. Şifreli alan
        // yalnız başlığı kapsar; veri ayrı şifrelenir.
        let mut cursor = io::Cursor::new(block_bytes);
        let mut crc = [0u8; 4];
        cursor.read_exact(&mut crc).unwrap();
        let size = read_vint_slice(&mut cursor).unwrap() as usize;
        let size_len = cursor.position() as usize - 4;
        let header_len = 4 + size_len + size;
        let (header, data) = block_bytes.split_at(header_len);
        let encrypted = encrypted_block(key, header, iv);
        let mut out = encrypted;
        out.extend_from_slice(data);
        (out, data.len())
    }

    fn encryption_block(salt: &[u8; SALT_SIZE], lg2_count: u8, psw_check: Option<[u8; 8]>) -> Vec<u8> {
        let mut body = vint(0); // CryptVersion
        body.extend(vint(if psw_check.is_some() { 1 } else { 0 }));
        body.push(lg2_count);
        body.extend_from_slice(salt);
        if let Some(check) = psw_check {
            body.extend_from_slice(&check);
            use sha2::Digest;
            body.extend_from_slice(&sha2::Sha256::digest(check)[..4]);
        }
        block(HEAD_TYPE_ENCRYPTION, 0, &[], &[], &body)
    }

    /// `password` ile -hp akışını taklit eden çok ciltli arşiv: tek dosya
    /// iki cilde bölünmüş, tüm başlıklar ve veri şifreli.
    fn build_encrypted_fixture(password: &str, plain: &[u8], first_part: usize) -> EncryptedFixture {
        let header_salt = [0x11u8; SALT_SIZE];
        let file_salt = [0x22u8; SALT_SIZE];
        let file_iv = [0x33u8; INITV_SIZE];
        let lg2 = 4;

        let header_kdf = rarcrypt::kdf5(password.as_bytes(), &header_salt, lg2).unwrap();
        let file_kdf = rarcrypt::kdf5(password.as_bytes(), &file_salt, lg2).unwrap();
        let psw_check = Some(rarcrypt::psw_check_fold(&header_kdf.psw_check_value));
        let file_check = Some(rarcrypt::psw_check_fold(&file_kdf.psw_check_value));

        // Veri: tek mantıksal CBC akışı, 16'ya sıfır padding, sonra bölünür.
        let mut padded = plain.to_vec();
        let pad = (16 - padded.len() % 16) % 16;
        padded.resize(padded.len() + pad, 0);
        let mut cipher_data = padded.clone();
        let encryptor = cbc::Encryptor::<aes::Aes256>::new_from_slices(&file_kdf.key[..], &file_iv)
            .unwrap();
        let data_len = cipher_data.len();
        encryptor
            .encrypt_padded_mut::<cbc::cipher::block_padding::NoPadding>(&mut cipher_data, data_len)
            .unwrap();
        let split_at = first_part.min(cipher_data.len() / 16 * 16);
        let (first_data, second_data) = cipher_data.split_at(split_at);

        let crypt = TestCrypt {
            salt: file_salt,
            initv: file_iv,
            lg2_count: lg2,
            psw_check: file_check,
        };
        let mut first_spec = store_spec("film.mkv", plain.len() as u64, first_data);
        first_spec.split_after = true;
        first_spec.crypt_extra = Some(crypt);
        let mut last_spec = store_spec("film.mkv", plain.len() as u64, second_data);
        last_spec.split_before = true;
        last_spec.crypt_extra = Some(crypt);

        let key: &[u8; 32] = &header_kdf.key;
        let mut iv_counter = 0u8;
        let mut next_iv = || {
            iv_counter += 1;
            [iv_counter; INITV_SIZE]
        };
        let make_volume = |specs: &[FileSpec<'_>], next_iv: &mut dyn FnMut() -> [u8; 16]| {
            let mut volume = RAR5_SIGNATURE.to_vec();
            volume.extend(encryption_block(&header_salt, lg2, psw_check));
            let mut encrypted = encrypt_plain_block(key, &main_block(), next_iv()).0;
            volume.append(&mut encrypted);
            for spec in specs {
                let (mut block_bytes, _) = encrypt_plain_block(key, &file_block(spec), next_iv());
                volume.append(&mut block_bytes);
            }
            let mut endarc = encrypt_plain_block(key, &endarc_block(), next_iv()).0;
            volume.append(&mut endarc);
            volume
        };
        let volumes = vec![
            make_volume(&[first_spec], &mut next_iv),
            make_volume(&[last_spec], &mut next_iv),
        ];

        EncryptedFixture {
            password: password.to_string(),
            volumes,
        }
    }

    /// Sanal set baytları üzerinden çözülmüş aralığı okur (NNTP'siz test
    /// akışı; gerçek akışta `RarEntrySource::write_encrypted_range` aynı
    /// pencereleri `NntpVolumeSet`ten okur).
    fn read_decrypted_range(map: &FragmentMap, set_bytes: &[u8], range: Range<u64>) -> Vec<u8> {
        let mut out = Vec::new();
        for window in map.cipher_windows(range) {
            let iv: [u8; 16] = match window.iv {
                None => map.crypt.as_ref().unwrap().initv,
                Some(iv_range) => set_bytes[iv_range.start as usize..iv_range.end as usize]
                    .try_into()
                    .unwrap(),
            };
            let mut buffer =
                set_bytes[window.data.start as usize..window.data.end as usize].to_vec();
            assert!(rarcrypt::decrypt_cbc(&map.crypt.as_ref().unwrap().key, &iv, &mut buffer));
            out.extend_from_slice(
                &buffer[window.skip as usize..(window.skip + window.take) as usize],
            );
        }
        out
    }

    #[test]
    fn baslik_sifreli_cok_ciltli_set_cozulur() {
        let plain: Vec<u8> = (0..1000u32).map(|i| ((i * 7 + i / 13) % 256) as u8).collect();
        let fixture = build_encrypted_fixture("nzbsifresi", &plain, 512);
        let bytes = concat(&fixture.volumes);
        let map = build_fragment_map(
            &mut Cursor::new(bytes.clone()),
            &layout(&fixture.volumes),
            Some(&fixture.password),
        )
        .unwrap();

        assert_eq!(map.filename, "film.mkv");
        assert_eq!(map.total_len, plain.len() as u64);
        assert_eq!(map.fragments.len(), 2);
        assert!(map.crypt.is_some());

        // Farklı ofsetlerden oku: sanal çözülmüş içerik byte-byte eşleşmeli.
        let check_range = |range: Range<u64>| {
            let out = read_decrypted_range(&map, &bytes, range.clone());
            assert_eq!(out, plain[range.start as usize..range.end as usize]);
        };
        check_range(0..plain.len() as u64);
        check_range(0..16);
        check_range(5..37);
        check_range(500..700); // parça sınırını (512) aşıyor
        check_range(512..520); // parça başı: IV önceki parçanın son bloğu
        check_range((plain.len() as u64) - 7..plain.len() as u64);
    }

    #[test]
    fn baslik_sifreli_sette_parolasiz_ve_yanlis_parola() {
        let plain: Vec<u8> = (0..300u32).map(|i| (i % 251) as u8).collect();
        let fixture = build_encrypted_fixture("nzbsifresi", &plain, 256);

        let bytes = concat(&fixture.volumes);
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes.clone()), &layout(&fixture.volumes), None),
            Err(RarError::Encrypted)
        ));
        assert!(matches!(
            build_fragment_map(
                &mut Cursor::new(bytes),
                &layout(&fixture.volumes),
                Some("baska-parola")
            ),
            Err(RarError::WrongPassword)
        ));
    }

    #[test]
    fn baslik_sifreli_sette_sikistirilmis_dosya_yine_reddedilir() {
        let plain: Vec<u8> = (0..300u32).map(|i| (i % 251) as u8).collect();
        let mut fixture = build_encrypted_fixture("nzbsifresi", &plain, 256);
        // Ciltleri yeniden kur: method != STORE ama parola doğru.
        let header_salt = [0x11u8; SALT_SIZE];
        let lg2 = 4;
        let header_kdf = rarcrypt::kdf5(fixture.password.as_bytes(), &header_salt, lg2).unwrap();
        let psw_check = Some(rarcrypt::psw_check_fold(&header_kdf.psw_check_value));
        let key: &[u8; 32] = &header_kdf.key;
        let mut spec = store_spec("film.mkv", 64, &[7u8; 64]);
        spec.method = 3;
        spec.crypt_extra = Some(TestCrypt {
            salt: [0x22u8; SALT_SIZE],
            initv: [0x33u8; INITV_SIZE],
            lg2_count: lg2,
            psw_check: None,
        });
        let mut volume = RAR5_SIGNATURE.to_vec();
        volume.extend(encryption_block(&header_salt, lg2, psw_check));
        volume.append(&mut encrypt_plain_block(key, &main_block(), [1u8; 16]).0);
        volume.append(&mut encrypt_plain_block(key, &file_block(&spec), [2u8; 16]).0);
        volume.append(&mut encrypt_plain_block(key, &endarc_block(), [3u8; 16]).0);
        fixture.volumes = vec![volume];

        let bytes = concat(&fixture.volumes);
        assert!(matches!(
            build_fragment_map(
                &mut Cursor::new(bytes),
                &layout(&fixture.volumes),
                Some(&fixture.password)
            ),
            Err(RarError::UnsupportedCompression)
        ));
    }

    #[test]
    fn sifreli_parca_boyutu_hizasizsa_reddedilir() {
        // Geçerli parolalı crypt extra ama data_size 16'nın katı değil.
        let password = "nzbsifresi";
        let file_salt = [0x22u8; SALT_SIZE];
        let derived = rarcrypt::kdf5(password.as_bytes(), &file_salt, 4).unwrap();
        let mut spec = store_spec("film.mkv", 100, &[0u8; 100]);
        spec.crypt_extra = Some(TestCrypt {
            salt: file_salt,
            initv: [0x33u8; INITV_SIZE],
            lg2_count: 4,
            psw_check: Some(rarcrypt::psw_check_fold(&derived.psw_check_value)),
        });
        let volume = volume(&[file_block(&spec)]);
        let bytes = concat(std::slice::from_ref(&volume));
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &layout(&[volume]), Some(password)),
            Err(RarError::InvalidLayout(_))
        ));
    }

    /// Gerçek `rar` 7.12 ile üretilmiş fixture arşivleri üzerinden uçtan uca
    /// doğrulama. Fixture'lardaki parola yalnız test içindir.
    mod fixtures {
        use super::*;

        const PASSWORD: &str = "TestSifresi-2026";
        const FIXTURE_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/rar5hp");

        /// Fixture üretimindeki deterministik içerik deseni (video.mkv).
        fn expected_payload() -> Vec<u8> {
            (0..150_003u64).map(|i| ((i * 7 + i / 13) % 256) as u8).collect()
        }

        fn read_fixture(name: &str) -> Vec<u8> {
            std::fs::read(format!("{FIXTURE_DIR}/{name}"))
                .unwrap_or_else(|error| panic!("fixture okunamadı ({name}): {error}"))
        }

        /// Ciltleri sanal set uzayında birleştirip parça eşlemini kurar.
        fn open_set(volume_names: &[&str], password: Option<&str>) -> (Vec<u8>, FragmentMap) {
            let volumes: Vec<Vec<u8>> = volume_names.iter().map(|name| read_fixture(name)).collect();
            let bytes = concat(&volumes);
            let map = build_fragment_map(&mut Cursor::new(bytes.clone()), &layout(&volumes), password)
                .unwrap_or_else(|error| panic!("fixture seti açılamadı: {error}"));
            (bytes, map)
        }

        #[test]
        fn gercek_hp_tek_cilt_cozulur() {
            let (bytes, map) = open_set(&["hp_single.rar"], Some(PASSWORD));
            let plain = expected_payload();
            assert_eq!(map.filename, "video.mkv");
            assert_eq!(map.total_len, plain.len() as u64);
            assert!(map.crypt.is_some());

            for range in [
                0..plain.len() as u64,
                0..1,
                13..4099,
                149_999..150_003, // padding'e komşu son baytlar
            ] {
                let out = read_decrypted_range(&map, &bytes, range.clone());
                assert_eq!(out, plain[range.start as usize..range.end as usize]);
            }
        }

        #[test]
        fn gercek_hp_cok_cilt_cozulur() {
            let (bytes, map) = open_set(
                &["hp_multi.part1.rar", "hp_multi.part2.rar"],
                Some(PASSWORD),
            );
            let plain = expected_payload();
            assert_eq!(map.filename, "video.mkv");
            assert_eq!(map.total_len, plain.len() as u64);
            assert_eq!(map.fragments.len(), 2);
            let boundary = map.starts[1]; // parça sınırı (çözülmüş uzay)

            for range in [
                0..plain.len() as u64,
                0..16,
                7..31,
                boundary - 20..boundary + 20, // cilt sınırını aşan okuma
                boundary..boundary + 48,      // ikinci cildin parça başı
                150_000..150_003,
            ] {
                let out = read_decrypted_range(&map, &bytes, range.clone());
                assert_eq!(out, plain[range.start as usize..range.end as usize]);
            }
        }

        #[test]
        fn gercek_hp_arsivde_yanlis_parola_reddedilir() {
            let volumes: Vec<Vec<u8>> = ["hp_multi.part1.rar", "hp_multi.part2.rar"]
                .iter()
                .map(|name| read_fixture(name))
                .collect();
            let bytes = concat(&volumes);
            assert!(matches!(
                build_fragment_map(
                    &mut Cursor::new(bytes),
                    &layout(&volumes),
                    Some("KesinlikleYanlis123")
                ),
                Err(RarError::WrongPassword)
            ));
        }

        #[test]
        fn gercek_hp_arsivde_parolasizlik_reddedilir() {
            let volumes: Vec<Vec<u8>> = ["hp_multi.part1.rar", "hp_multi.part2.rar"]
                .iter()
                .map(|name| read_fixture(name))
                .collect();
            let bytes = concat(&volumes);
            let error =
                build_fragment_map(&mut Cursor::new(bytes), &layout(&volumes), None).unwrap_err();
            assert!(matches!(error, RarError::Encrypted));
            assert_eq!(
                error.to_string(),
                "RAR arşivi parola korumalı ve NZB parola içermiyor"
            );
        }

        #[test]
        fn sifresiz_kontrol_arsivi_acilir() {
            // Şifresiz STORE arşivi parolasız da, parola verildiğinde de
            // (yok sayılır) aynen çalışır — regresyon kontrolü.
            for password in [None, Some(PASSWORD)] {
                let (bytes, map) = open_set(&["plain_single.rar"], password);
                let plain = expected_payload();
                assert_eq!(map.filename, "video.mkv");
                assert_eq!(map.total_len, plain.len() as u64);
                assert!(map.crypt.is_none());
                let slices = map.slices(0..plain.len() as u64);
                assert_eq!(slices.len(), 1);
                assert_eq!(
                    &bytes[slices[0].start as usize..slices[0].end as usize],
                    &plain[..]
                );
            }
        }
    }
}
