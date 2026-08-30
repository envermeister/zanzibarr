//! Çok ciltli RAR STORE yayınlarını sanal, seek edilebilir medya dosyasına
//! dönüştürür (RAR5 + RAR4/RAR3).
//!
//! RAR ciltleri diske indirilmez. Her `.partNN.rar` (veya eski usul
//! `.rar`/`.rNN`) dosyası mevcut NNTP+yEnc kaynağıyla açılır, tek bir sanal
//! byte uzayında birleştirilir ve her cildin blok başlıkları o uzaydan tembel
//! olarak okunur. İçerideki medya STORE ise her parçanın veri aralığı doğrudan
//! sunulur; şifreliyse ve NZB parolası biliniyorsa istenen bloklar yerinde
//! çözülür. Sıkıştırılmış (method != STORE) ve solid arşivler, rastgele
//! seek'i bozmamak için açıkça reddedilir. RAR4 STORE desteklenir; RAR4
//! parola koruması (RAR5 -hp'den farklı KDF/AES-128 düzeni) reddedilir.
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

use std::collections::HashMap;
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

// RAR4 blok düzeni sabitleri.
const RAR4_HEAD_TYPE_MAIN: u8 = 0x72;
const RAR4_HEAD_TYPE_FILE: u8 = 0x73;
const RAR4_HEAD_TYPE_ENDARC: u8 = 0x7B;
const RAR4_FLAG_LONG_BLOCK: u16 = 0x8000;
const RAR4_MAIN_FLAG_PASSWORD: u16 = 0x0080;
const RAR4_LHD_SPLIT_BEFORE: u16 = 0x0001;
const RAR4_LHD_SPLIT_AFTER: u16 = 0x0002;
const RAR4_LHD_PASSWORD: u16 = 0x0004;
const RAR4_LHD_SOLID: u16 = 0x0010;
const RAR4_LHD_LARGE: u16 = 0x0100;
const RAR4_LHD_UNICODE: u16 = 0x0200;
const RAR4_METHOD_STORE: u8 = 0x30;

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

/// Şifreli okuma penceresi üst sınırı. Şifreli aralıklar bu boyutta parçalar
/// halinde getirilip çözülüp yazılır; böylece oynatıcı ilk baytı tek parça
/// çekim gecikmesiyle görür (tüm cilt parçasını beklemek yerine) ve bellek
/// kullanımı sabit kalır. Değer 16'nın katı olmalı (CBC blok hizası).
const MAX_CIPHER_WINDOW: u64 = 2 * 1024 * 1024;

#[derive(Debug, Error)]
pub enum RarError {
    #[error("could not prepare RAR volumes: {0}")]
    Io(#[from] io::Error),
    #[error("could not read RAR header: {0}")]
    Header(String),
    #[error("no playable media file in the RAR archive")]
    NoPlayableMedia,
    #[error("RAR archive is compressed; only STORE archives are playable with seeking")]
    UnsupportedCompression,
    #[error("RAR4 password protection is unsupported (outside RAR5 -hp scope); unencrypted or RAR5 set required")]
    UnsupportedRar4Encryption,
    #[error("RAR archive is password-protected and the NZB carries no password")]
    Encrypted,
    #[error("password does not match the RAR archive")]
    WrongPassword,
    #[error("invalid RAR layout: {0}")]
    InvalidLayout(String),
    #[error("RAR prepare task failed to complete: {0}")]
    Task(String),
    #[error("RAR preparation cancelled")]
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

/// Bir (salt, tur) çifti için daha önce türetilmiş KDF çıktısı. Çok ciltli
/// -hp arşivlerde ciltler genellikle aynı salt'ı taşır; KDF (~2^lg2 HMAC
/// turu) cilt başına tekrarlanmaz, bootstrap dakikalardan saniyelere iner.
struct CachedKdf {
    key: Zeroizing<[u8; 32]>,
    psw_check_value: Zeroizing<[u8; 32]>,
}

type KdfCache = HashMap<([u8; SALT_SIZE], u8), CachedKdf>;

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
    ///
    /// Pencereler [`MAX_CIPHER_WINDOW`] ile sınırlanır: tüm cilt parçasını
    /// (yüzlerce MB) tek seferde çekip bellekte çözmek, oynatıcının ilk
    /// baytı dakikalarca görememesine (ffmpeg `network-timeout`, uygulamada
    /// video-detect bekçisi) ve yüksek bellek basıncına yol açar. Küçük
    /// pencerelerle getir→çöz→yaz döngüsü akışkan kalır.
    fn cipher_windows(&self, range: Range<u64>) -> Vec<CipherWindow> {
        let mut out = Vec::new();
        let mut cursor = range.start;
        while cursor < range.end {
            let index = self.starts.partition_point(|&start| start <= cursor) - 1;
            let fragment = self.fragments[index];
            let within = cursor - self.starts[index];
            let take = (range.end - cursor)
                .min(fragment.len - within)
                .min(MAX_CIPHER_WINDOW);

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

    /// PAR2 onarım katmanını cilt kümesine dağıtır.
    pub fn set_overlays(&self, overlay: &crate::engine::repair::RepairOverlay) {
        self.archive.set_overlays(overlay);
    }

    /// Şifreli STORE verisini 16-hizalı pencerelerle okuyup çözer. CBC
    /// zinciri split parçalar arasında kesintisizdir; IV, global ilk blok için
    /// dosyanın InitV'si, diğerlerinde bir önceki şifreli bloktur.
    async fn write_encrypted_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        let crypt = self.map.crypt.as_ref().expect("encrypted read plan present");
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
                    "could not decrypt RAR data",
                ));
            }
            let skip = usize::try_from(window.skip)
                .map_err(|_| io::Error::other("RAR decode offset overflow"))?;
            let take = usize::try_from(window.take)
                .map_err(|_| io::Error::other("RAR decode size overflow"))?;
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
        RarError::Header("volume ended mid-block; set is incomplete".into())
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
                    "vint exceeds u64 range",
                ));
            }
            value |= u64::from(byte[0] & 0x7F) << (7 * index);
            if byte[0] & 0x80 == 0 {
                return Ok(value);
            }
        }
        Err(io::Error::new(io::ErrorKind::InvalidData, "vint too long"))
    }
}

impl<R: Read + Seek> Read for HashingReader<'_, '_, R> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        // VolumeParser::read_exact RarError döndürür; Read uyumu için tek
        // seferde doldurma yerine hatayı io'ya çeviren düz okuma yapılır.
        if buffer.len() as u64 > self.inner.remaining() {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "volume ended mid-block; set is incomplete",
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
        .map_err(|error| io_to_header("could not read HEAD_SIZE", error))?;
    if header_size == 0 || header_size > MAX_BLOCK_HEADER_SIZE {
        return Err(RarError::Header(format!(
            "block header is {header_size} bytes; safe limit {MAX_BLOCK_HEADER_SIZE}"
        )));
    }
    let header_len = usize::try_from(header_size)
        .map_err(|_| RarError::Header("block header does not fit in memory".into()))?;
    let mut header = vec![0u8; header_len];
    hashing
        .read_exact(&mut header)
        .map_err(|error| io_to_header("could not read block header", error))?;
    let actual_crc = hashing.hasher.finalize();
    if actual_crc != expected_crc {
        return Err(RarError::Header(format!(
            "block CRC mismatch: expected {expected_crc:#x}, got {actual_crc:#x}"
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
            "block header is {header_size} bytes; safe limit {MAX_BLOCK_HEADER_SIZE}"
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
        return Err(RarError::Header("could not decrypt block".into()));
    }
    let expected_crc = u32::from_le_bytes([first[0], first[1], first[2], first[3]]);
    let (size_vint_len, header_size) = decrypted_header_len(&first[4..])?;
    let plain_len = 4 + size_vint_len + header_size;
    let encrypted_len = rarcrypt::round_up_block(plain_len)
        .ok_or_else(|| RarError::Header("encrypted block size overflow".into()))?;
    if encrypted_len > parser.remaining() + AES_BLOCK_SIZE {
        return Err(RarError::Header(
            "encrypted block exceeds volume end; set is incomplete or corrupt".into(),
        ));
    }

    let rest_len = usize::try_from(encrypted_len - AES_BLOCK_SIZE)
        .map_err(|_| RarError::Header("encrypted block does not fit in memory".into()))?;
    let mut plain = Vec::with_capacity(encrypted_len as usize);
    plain.extend_from_slice(&first);
    if rest_len > 0 {
        let mut rest = vec![0u8; rest_len];
        parser.read_exact(&mut rest)?;
        // CBC zinciri: devam bloklarının IV'si ilk şifreli blok.
        let chain_iv: &[u8; INITV_SIZE] = &first_cipher;
        if !rarcrypt::decrypt_cbc(key, chain_iv, &mut rest) {
            return Err(RarError::Header("could not decrypt block".into()));
        }
        plain.extend_from_slice(&rest);
    }
    plain.truncate(plain_len as usize);

    let actual_crc = crc32fast::hash(&plain[4..]);
    if actual_crc != expected_crc {
        return Err(RarError::Header(format!(
            "encrypted block CRC mismatch: expected {expected_crc:#x}, got {actual_crc:#x}"
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
    kdf_cache: &mut KdfCache,
) -> Result<Vec<FileEntry>, RarError> {
    let mut parser = VolumeParser {
        reader,
        position: volume_start,
        end: volume_end,
    };

    let mut signature = [0u8; 7];
    parser.read_exact(&mut signature)?;
    if signature == *RAR4_SIGNATURE {
        return parse_volume_rar4(&mut parser, volume_start);
    }
    let mut version_byte = [0u8; 1];
    parser.read_exact(&mut version_byte)?;
    if signature.as_slice() != &RAR5_SIGNATURE[..7] || version_byte[0] != RAR5_SIGNATURE[7] {
        return Err(RarError::Header("RAR signature not found".into()));
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
                        "ENCRYPTION block may only be the volume's first block".into(),
                    ));
                }
                let password = password.ok_or(RarError::Encrypted)?;
                let cache_key = (encryption.salt, encryption.lg2_count);
                let cached = match kdf_cache.get(&cache_key) {
                    Some(cached) => CachedKdf {
                        key: cached.key.clone(),
                        psw_check_value: cached.psw_check_value.clone(),
                    },
                    None => {
                        let derived = rarcrypt::kdf5(
                            password.as_bytes(),
                            &encryption.salt,
                            encryption.lg2_count,
                        )
                        .ok_or_else(|| {
                            RarError::Header(format!(
                                "RAR KDF round count (2^{}) exceeds the safe limit",
                                encryption.lg2_count
                            ))
                        })?;
                        let fresh = CachedKdf {
                            key: derived.key,
                            psw_check_value: derived.psw_check_value,
                        };
                        kdf_cache.insert(
                            cache_key,
                            CachedKdf {
                                key: fresh.key.clone(),
                                psw_check_value: fresh.psw_check_value.clone(),
                            },
                        );
                        fresh
                    }
                };
                if let Some(expected) = encryption.psw_check {
                    if rarcrypt::psw_check_fold(&cached.psw_check_value) != expected {
                        return Err(RarError::WrongPassword);
                    }
                }
                header_key = Some(cached.key);
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
                        "unknown required block type: {head_type}"
                    )));
                }
                parser.skip(data_size)?;
            }
        }
    }
    Ok(entries)
}

/// RAR4/RAR3 cildini blok blok okuyup STORE parça adaylarını toplar.
///
/// Blok düzeni: HEAD_CRC(2, HEAD_TYPE..başlık sonu CRC32'sinin alt 16 bit'i),
/// HEAD_TYPE(1), HEAD_FLAGS(2), HEAD_SIZE(2), [ADD_SIZE(4) — bayrak 0x8000].
/// Veri şifrelemesi (LHD_PASSWORD) ve başlık şifrelemesi (MHD_PASSWORD/-hp)
/// RAR5'ten farklı bir KDF/AES-128 düzeni gerektirdiğinden açıkça reddedilir;
/// sıkıştırılmış girdiler (method != 0x30) RAR5'te olduğu gibi kurulum
/// aşamasında elenir.
fn parse_volume_rar4<R: Read + Seek>(
    parser: &mut VolumeParser<'_, R>,
    volume_start: u64,
) -> Result<Vec<FileEntry>, RarError> {
    let mut entries = Vec::new();
    loop {
        // En küçük blok 7 bayt; kalan artık cilt sonu dolgusu sayılır.
        if parser.remaining() < 7 {
            break;
        }
        let mut head = [0u8; 7];
        parser.read_exact(&mut head)?;
        let expected_crc = u16::from_le_bytes([head[0], head[1]]);
        let head_type = head[2];
        let head_flags = u16::from_le_bytes([head[3], head[4]]);
        let head_size = u64::from(u16::from_le_bytes([head[5], head[6]]));
        if head_size < 7 {
            return Err(RarError::InvalidLayout(format!(
                "RAR4 block size {head_size} is invalid"
            )));
        }
        if head_size - 7 > parser.remaining() {
            return Err(parser.unexpected_eof());
        }

        let long_block = head_flags & RAR4_FLAG_LONG_BLOCK != 0;
        // CRC, HEAD_TYPE baytından başlık sonuna kadar hesaplanır.
        let mut crc_input = head[2..].to_vec();
        let add_size = if long_block {
            let mut add = [0u8; 4];
            parser.read_exact(&mut add)?;
            crc_input.extend_from_slice(&add);
            u64::from(u32::from_le_bytes(add))
        } else {
            0
        };
        let body_len = head_size - 7 - if long_block { 4 } else { 0 };
        let mut body = vec![0u8; body_len as usize];
        parser.read_exact(&mut body)?;
        crc_input.extend_from_slice(&body);
        if crc32fast::hash(&crc_input) as u16 != expected_crc {
            return Err(RarError::Header("RAR4 block CRC mismatch".into()));
        }

        match head_type {
            RAR4_HEAD_TYPE_MAIN => {
                if head_flags & RAR4_MAIN_FLAG_PASSWORD != 0 {
                    return Err(RarError::UnsupportedRar4Encryption);
                }
                parser.skip(add_size)?;
            }
            RAR4_HEAD_TYPE_FILE => {
                let mut entry = parse_rar4_file_body(&body, head_flags)?;
                if entry.data_size != add_size {
                    return Err(RarError::InvalidLayout(format!(
                        "RAR4 FILE header pack size {} does not match ADD_SIZE {add_size}",
                        entry.data_size
                    )));
                }
                entry.data_offset = parser.position - volume_start;
                parser.skip(add_size)?;
                entries.push(entry);
            }
            RAR4_HEAD_TYPE_ENDARC => break,
            // COMM/AV/NEWSUB vb. veri alanıyla birlikte atlanır.
            _ => parser.skip(add_size)?,
        }
    }
    Ok(entries)
}

/// RAR4 FILE_HEAD gövdesini (ADD_SIZE sonrası alanlar) [`FileEntry`]'ye çevirir.
/// `data_offset` çağıran tarafından doldurulur.
fn parse_rar4_file_body(body: &[u8], head_flags: u16) -> Result<FileEntry, RarError> {
    // pack(4) unp(4) host_os(1) file_crc(4) ftime(4) unp_ver(1) method(1)
    // name_size(2) attr(4) = 25 bayt sabit bölüm.
    if body.len() < 25 {
        return Err(RarError::Header("RAR4 FILE header is short".into()));
    }
    if head_flags & RAR4_LHD_PASSWORD != 0 {
        return Err(RarError::UnsupportedRar4Encryption);
    }
    let pack_low = u64::from(u32::from_le_bytes(body[0..4].try_into().expect("4 bayt")));
    let unp_low = u64::from(u32::from_le_bytes(body[4..8].try_into().expect("4 bayt")));
    let host_os = body[8];
    let method = body[18];
    let name_size = usize::from(u16::from_le_bytes([body[19], body[20]]));
    let attr = u32::from_le_bytes(body[21..25].try_into().expect("4 bayt"));

    let mut position = 25;
    let (pack_size, unpacked_size) = if head_flags & RAR4_LHD_LARGE != 0 {
        if body.len() < position + 8 {
            return Err(RarError::Header("RAR4 LARGE fields are short".into()));
        }
        let high_pack = u64::from(u32::from_le_bytes(
            body[position..position + 4].try_into().expect("4 bayt"),
        ));
        let high_unp = u64::from(u32::from_le_bytes(
            body[position + 4..position + 8].try_into().expect("4 bayt"),
        ));
        position += 8;
        (pack_low | (high_pack << 32), unp_low | (high_unp << 32))
    } else {
        (pack_low, unp_low)
    };

    if body.len() < position + name_size {
        return Err(RarError::Header("RAR4 filename header overflow".into()));
    }
    let name = decode_rar4_name(&body[position..position + name_size], head_flags);
    if name.is_empty() {
        return Err(RarError::Header("could not decode RAR4 filename".into()));
    }
    // RAR4'te dizin bayrağı yok; host özniteliği veya ad sondan anlaşılır.
    let is_dir = (host_os == 3 && attr & 0x10 != 0)
        || name.ends_with('/')
        || name.ends_with('\\');

    Ok(FileEntry {
        name,
        unpacked_size,
        data_size: pack_size,
        data_offset: 0,
        split_before: head_flags & RAR4_LHD_SPLIT_BEFORE != 0,
        split_after: head_flags & RAR4_LHD_SPLIT_AFTER != 0,
        store: method == RAR4_METHOD_STORE,
        solid: head_flags & RAR4_LHD_SOLID != 0,
        crypt: None,
        is_dir,
    })
}

/// RAR4 ad alanını çözer. LHD_UNICODE'da tam Unicode rekonstrüksiyonu
/// yapılmaz; ilk NUL'a kadar olan düz kısım kullanılır (sahne adlandırması
/// pratikte ASCII düz kısımla eşleşir).
fn decode_rar4_name(name_bytes: &[u8], head_flags: u16) -> String {
    let plain = if head_flags & RAR4_LHD_UNICODE != 0 {
        name_bytes
            .split(|byte| *byte == 0)
            .next()
            .unwrap_or_default()
    } else {
        name_bytes
    };
    String::from_utf8_lossy(plain).into_owned()
}

enum Block {
    Main,
    Service,    Encryption(EncryptionHead),
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
            "unsupported RAR encryption version: {crypt_version}"
        )));
    }
    let crypt_flags = read_vint_slice(cursor)?;
    let mut lg2_count = [0u8; 1];
    read_slice(cursor, &mut lg2_count, "KDF round count")?;
    let mut salt = [0u8; SALT_SIZE];
    read_slice(cursor, &mut salt, "encryption salt")?;

    let psw_check = if crypt_flags & 0x01 != 0 {
        let mut check = [0u8; PSW_CHECK_SIZE];
        read_slice(cursor, &mut check, "password verification value")?;
        let mut csum = [0u8; 4];
        read_slice(cursor, &mut csum, "password verification checksum")?;
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
        .map_err(|_| RarError::Header(format!("{label} field exceeds end of header")))
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
        .ok_or_else(|| RarError::Header("extra field exceeds header size".into()))?;
    if name_size > extra_start.saturating_sub(cursor.position()) {
        return Err(RarError::Header("filename exceeds header limit".into()));
    }
    let name_len = usize::try_from(name_size)
        .map_err(|_| RarError::Header("filename does not fit in memory".into()))?;
    let name_start = cursor.position() as usize;
    let name_bytes = &cursor.get_ref()[name_start..name_start + name_len];
    let name = String::from_utf8(name_bytes.to_vec())
        .map_err(|_| RarError::Header("filename is not valid UTF-8".into()))?;
    cursor.set_position(cursor.position() + name_size);
    if cursor.position() > extra_start {
        return Err(RarError::Header("file header fields overlap".into()));
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
            .ok_or_else(|| RarError::Header("invalid extra record size".into()))?;
        if record_id == EXTRA_RECORD_CRYPT {
            if crypt.is_some() {
                return Err(RarError::Header("multiple crypt extra records".into()));
            }
            let payload_len = usize::try_from(payload)
                .map_err(|_| RarError::Header("crypt extra record does not fit in memory".into()))?;
            let payload_start = cursor.position() as usize;
            if payload_start + payload_len > cursor.get_ref().len() {
                return Err(RarError::Header("crypt extra record exceeds end of header".into()));
            }
            let mut record_cursor = io::Cursor::new(
                &cursor.get_ref()[payload_start..payload_start + payload_len],
            );
            crypt = Some(parse_crypt_record(&mut record_cursor)?);
        }
        skip_slice(cursor, payload, "extra record data")?;
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
            "unsupported file encryption version: {enc_version}"
        )));
    }
    let flags = read_vint_slice(cursor)?;
    let mut lg2_count = [0u8; 1];
    read_slice(cursor, &mut lg2_count, "KDF round count")?;
    let mut salt = [0u8; SALT_SIZE];
    read_slice(cursor, &mut salt, "file encryption salt")?;
    let mut initv = [0u8; INITV_SIZE];
    read_slice(cursor, &mut initv, "file initialization vector")?;

    let psw_check = if flags & 0x01 != 0 {
        let mut check = [0u8; PSW_CHECK_SIZE];
        read_slice(cursor, &mut check, "password verification value")?;
        let mut csum = [0u8; 4];
        read_slice(cursor, &mut csum, "password verification checksum")?;
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
            .map_err(|_| RarError::Header("vint exceeds end of header".into()))?;
        if index == 9 && byte[0] & 0x7E != 0 {
            return Err(RarError::Header("vint exceeds u64 range".into()));
        }
        value |= u64::from(byte[0] & 0x7F) << (7 * index);
        if byte[0] & 0x80 == 0 {
            return Ok(value);
        }
    }
    Err(RarError::Header("vint too long".into()))
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
        .ok_or_else(|| RarError::Header(format!("{label} field exceeds end of header")))?;
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
    let parts = collect_playable_parts(reader, volumes, password)?;
    validate_and_build(&parts, password)
}

/// Tüm ciltlerin başlıklarını yürüyüp oynatılabilir en büyük dosyanın parça
/// grubunu döndürür. Sıkıştırma/parola denetimi YAPMAZ; STORE doğrulaması
/// `validate_and_build`'e, sıkıştırılmış yolun plan çıkarımı
/// [`probe_compressed_plan`]'e aittir.
fn collect_playable_parts<R: Read + Seek>(
    reader: &mut R,
    volumes: &[(u64, u64)],
    password: Option<&str>,
) -> Result<Vec<FragmentPart>, RarError> {
    // (küçük harf ad) -> parça listesi; ekleme sırası korunur.
    let mut groups: Vec<(String, Vec<FragmentPart>)> = Vec::new();
    // Ciltler arası KDF önbelleği: aynı salt'ı taşıyan -hp ciltlerinde pahalı
    // anahtar türetimi bir kez çalışır.
    let mut kdf_cache = KdfCache::new();

    for (volume_index, &(volume_start, volume_len)) in volumes.iter().enumerate() {
        let volume_end = volume_start
            .checked_add(volume_len)
            .ok_or_else(|| RarError::InvalidLayout("volume offset overflow".into()))?;
        reader.seek(SeekFrom::Start(volume_start))?;
        for entry in parse_volume(reader, volume_start, volume_end, password, &mut kdf_cache)? {
            if entry.is_dir {
                continue;
            }
            let part = FragmentPart {
                volume_index,
                set_offset: volume_start
                    .checked_add(entry.data_offset)
                    .ok_or_else(|| RarError::InvalidLayout("part offset overflow".into()))?,
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
    let index = groups
        .iter()
        .position(|(_, parts)| is_playable_media_filename(&parts[0].entry.name))
        .and_then(|_| {
            groups
                .iter()
                .enumerate()
                .filter(|(_, (_, parts))| {
                    is_playable_media_filename(&parts[0].entry.name)
                })
                .max_by_key(|(_, (_, parts))| parts[0].entry.unpacked_size)
                .map(|(index, _)| index)
        })
        .ok_or(RarError::NoPlayableMedia)?;
    Ok(groups.swap_remove(index).1)
}

/// Sıkıştırılmış (STORE olmayan) bir RAR setinin oynatılacak üyesinin planı.
/// Gerçek çözüm [`super::rarcompressed`] üzerinden yürür.
pub(crate) struct CompressedRarPlan {
    pub(crate) filename: String,
    pub(crate) unpacked_size: u64,
}

/// Sıkıştırılmış setin başlıklarını okuyup plan çıkarır. Yalnız STORE
/// setlerinde `UnsupportedCompression` yerine None döner (çağıran STORE yolunu
/// zaten denemiştir); diğer hatalar aynen yayılır.
pub(crate) async fn probe_compressed_plan(
    pool: Arc<NntpPool<TlsNntpConnector>>,
    files: Vec<NzbFile>,
    password: Option<String>,
    mut cancellation: watch::Receiver<bool>,
) -> Result<Option<(CompressedRarPlan, Arc<NntpVolumeSet>)>, RarError> {
    let archive = Arc::new(NntpVolumeSet::new_cancellable(pool, files, &mut cancellation).await?);
    ensure_not_cancelled(&cancellation)?;
    let layout: Vec<(u64, u64)> = (0..archive.volume_count())
        .map(|index| (archive.volume_start(index), archive.volume_len(index)))
        .collect();
    let archive_for_parser = Arc::clone(&archive);
    let runtime = tokio::runtime::Handle::current();

    let archive_for_task = Arc::clone(&archive);
    let parts = run_blocking_cancellable(cancellation, move |reader_cancellation| {
        let mut reader =
            BlockingArchiveReader::new(archive_for_parser, runtime, reader_cancellation);
        collect_playable_parts(&mut reader, &layout, password.as_deref())
    })
    .await?;

    let first = parts.first().expect("playable group is never empty");
    if first.entry.store && !first.entry.solid {
        return Ok(None);
    }
    Ok(Some((
        CompressedRarPlan {
            filename: first.entry.name.clone(),
            unpacked_size: first.entry.unpacked_size,
        },
        archive_for_task,
    )))
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
                "`{}` is partially encrypted, partially not",
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
                "`{}` split parts carry different encryption parameters",
                part.entry.name
            )));
        }
    }

    let password = password.ok_or(RarError::Encrypted)?;
    let derived = rarcrypt::kdf5(password.as_bytes(), &first.salt, first.lg2_count)
        .ok_or_else(|| {
            RarError::Header(format!(
                "RAR KDF round count (2^{}) exceeds the safe limit",
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
                "`{}` is in a single volume but carries a split flag; set is incomplete",
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
                    "`{}` split chain flags are corrupt (part {}/{})",
                    part.entry.name,
                    index + 1,
                    parts.len()
                )));
            }
        }
        for window in parts.windows(2) {
            if window[1].volume_index != window[0].volume_index + 1 {
                return Err(RarError::InvalidLayout(format!(
                    "`{}` split parts are not in consecutive volumes; set is incomplete",
                    window[0].entry.name
                )));
            }
        }
    }

    let cipher_total = parts.iter().try_fold(0u64, |total, part| {
        total
            .checked_add(part.entry.data_size)
            .ok_or_else(|| RarError::InvalidLayout("part size total overflow".into()))
    })?;
    let declared = parts[0].entry.unpacked_size;
    if crypt.is_some() {
        // Şifreli veri 16-hizalıdır: her parça blok katı, toplam şifreli
        // boyut unpacked'ın 16'ya yuvarlısıdır (padding yalnız son parçada).
        for part in parts {
            if part.entry.data_size % AES_BLOCK_SIZE != 0 {
                return Err(RarError::InvalidLayout(format!(
                    "`{}` encrypted part size is not 16-byte aligned; set is corrupt",
                    part.entry.name
                )));
            }
        }
        if cipher_total < declared || cipher_total - declared >= AES_BLOCK_SIZE {
            return Err(RarError::InvalidLayout(format!(
                "`{}` encrypted parts total {cipher_total} bytes but the header declares {declared}; set is incomplete or corrupt",
                parts[0].entry.name
            )));
        }
    } else if cipher_total != declared {
        return Err(RarError::InvalidLayout(format!(
            "`{}` parts total {cipher_total} bytes but the header declares {declared}; set is incomplete or corrupt",
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
    fn rar4_bozuk_blok_reddedilir() {
        let mut bytes = RAR4_SIGNATURE.to_vec();
        bytes.extend_from_slice(&[0u8; 64]);
        let len = bytes.len() as u64;
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &[(0, len)], None),
            Err(RarError::InvalidLayout(_))
        ));
    }

    // -- RAR4 fixture yardımcıları -------------------------------------------

    /// CRC'si doğru hesaplanmış RAR4 bloğu üretir.
    fn rar4_block(head_type: u8, head_flags: u16, body: &[u8], data: &[u8]) -> Vec<u8> {
        let mut flags = head_flags;
        if !data.is_empty() {
            flags |= RAR4_FLAG_LONG_BLOCK;
        }
        let long = flags & RAR4_FLAG_LONG_BLOCK != 0;
        let head_size = (7 + if long { 4 } else { 0 } + body.len()) as u16;

        let mut crc_input = vec![head_type];
        crc_input.extend_from_slice(&flags.to_le_bytes());
        crc_input.extend_from_slice(&head_size.to_le_bytes());
        if long {
            crc_input.extend_from_slice(&(data.len() as u32).to_le_bytes());
        }
        crc_input.extend_from_slice(body);

        let mut out = (crc32fast::hash(&crc_input) as u16).to_le_bytes().to_vec();
        out.extend_from_slice(&crc_input);
        out.extend_from_slice(data);
        out
    }

    fn rar4_main_block() -> Vec<u8> {
        rar4_block(RAR4_HEAD_TYPE_MAIN, 0, &[0u8; 6], &[])
    }

    fn rar4_endarc_block() -> Vec<u8> {
        rar4_block(RAR4_HEAD_TYPE_ENDARC, 0, &[0u8; 6], &[])
    }

    fn rar4_file_block(name: &str, data: &[u8], unp_total: u64, method: u8, flags: u16) -> Vec<u8> {
        let mut body = Vec::new();
        body.extend_from_slice(&(data.len() as u32).to_le_bytes());
        body.extend_from_slice(&(unp_total as u32).to_le_bytes());
        body.push(3); // host_os: win32
        body.extend_from_slice(&crc32fast::hash(data).to_le_bytes());
        body.extend_from_slice(&[0u8; 4]); // ftime
        body.push(20); // unp_ver: 2.0
        body.push(method);
        body.extend_from_slice(&(name.len() as u16).to_le_bytes());
        body.extend_from_slice(&[0u8; 4]); // attr
        body.extend_from_slice(name.as_bytes());
        rar4_block(RAR4_HEAD_TYPE_FILE, flags, &body, data)
    }

    fn rar4_volume(blocks: &[Vec<u8>]) -> Vec<u8> {
        let mut out = RAR4_SIGNATURE.to_vec();
        for block in blocks {
            out.extend_from_slice(block);
        }
        out
    }

    #[test]
    fn rar4_store_tek_cilt_okunur() {
        let data: Vec<u8> = (0..=251u8).cycle().take(5000).collect();
        let bytes = rar4_volume(&[
            rar4_main_block(),
            rar4_file_block("movie.mkv", &data, 5000, RAR4_METHOD_STORE, 0),
            rar4_endarc_block(),
        ]);
        let len = bytes.len() as u64;
        let map = build_fragment_map(&mut Cursor::new(bytes), &[(0, len)], None).unwrap();
        assert_eq!(map.total_len, 5000);
        assert_eq!(map.filename, "movie.mkv");
        assert_eq!(map.fragments.len(), 1);
        assert!(map.crypt.is_none());
    }

    #[test]
    fn rar4_split_zinciri_birlesir() {
        let part1: Vec<u8> = vec![0xAA; 3000];
        let part2: Vec<u8> = vec![0xBB; 5000];
        let volume1 = rar4_volume(&[
            rar4_main_block(),
            rar4_file_block("movie.mkv", &part1, 8000, RAR4_METHOD_STORE, RAR4_LHD_SPLIT_AFTER),
            rar4_endarc_block(),
        ]);
        let volume2 = rar4_volume(&[
            rar4_main_block(),
            rar4_file_block("movie.mkv", &part2, 8000, RAR4_METHOD_STORE, RAR4_LHD_SPLIT_BEFORE),
            rar4_endarc_block(),
        ]);
        let len1 = volume1.len() as u64;
        let len2 = volume2.len() as u64;
        let mut bytes = volume1;
        bytes.extend_from_slice(&volume2);

        let map = build_fragment_map(
            &mut Cursor::new(bytes),
            &[(0, len1), (len1, len2)],
            None,
        )
        .unwrap();
        assert_eq!(map.total_len, 8000);
        assert_eq!(map.fragments.len(), 2);
        // Çözülmüş uzayın ikinci yarısı ikinci cilde denk gelmeli.
        let slices = map.slices(3000..8000);
        assert_eq!(slices.len(), 1);
        assert_eq!(slices[0].end - slices[0].start, 5000);
    }

    #[test]
    fn rar4_sikistirilmis_girdi_reddedilir() {
        let data = vec![0u8; 100];
        let bytes = rar4_volume(&[
            rar4_main_block(),
            rar4_file_block("movie.mkv", &data, 100, 0x33, 0),
            rar4_endarc_block(),
        ]);
        let len = bytes.len() as u64;
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &[(0, len)], None),
            Err(RarError::UnsupportedCompression)
        ));
    }

    #[test]
    fn rar4_sifreli_girdi_reddedilir() {
        let data = vec![0u8; 100];
        let bytes = rar4_volume(&[
            rar4_main_block(),
            rar4_file_block("movie.mkv", &data, 100, RAR4_METHOD_STORE, RAR4_LHD_PASSWORD),
            rar4_endarc_block(),
        ]);
        let len = bytes.len() as u64;
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &[(0, len)], None),
            Err(RarError::UnsupportedRar4Encryption)
        ));
    }

    #[test]
    fn rar4_bozuk_crc_reddedilir() {
        let data = vec![0u8; 100];
        let mut bytes = rar4_volume(&[
            rar4_main_block(),
            rar4_file_block("movie.mkv", &data, 100, RAR4_METHOD_STORE, 0),
            rar4_endarc_block(),
        ]);
        // FILE bloğunun gövdesinde bir bayt bozulur: CRC uyuşmaz.
        let corrupt_at = RAR4_SIGNATURE.len() + rar4_main_block().len() + 12;
        bytes[corrupt_at] ^= 0xFF;
        let len = bytes.len() as u64;
        assert!(matches!(
            build_fragment_map(&mut Cursor::new(bytes), &[(0, len)], None),
            Err(RarError::Header(message)) if message.contains("CRC")
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
        assert!(error.to_string().contains("password-protected and the NZB carries no password"));
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
        assert!(error.to_string().contains("password does not match the RAR archive"));
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
    fn cipher_windows_buyuk_parcalari_akiskan_pencereye_boler() {
        // Regresyon: pencereler bir zamanlar cilt parçası boyundaydı; tam GET
        // isteğinde ilk bayt ancak ~yüz MB'lık parça çekilip çözüldükten sonra
        // yazılıyor, oynatıcı ağ zaman aşımına düşüyordu. Artık her pencere
        // MAX_CIPHER_WINDOW ile sınırlı ve CBC zinciri pencereler arası doğru.
        let total = 3 * MAX_CIPHER_WINDOW + 123;
        let map = FragmentMap {
            fragments: vec![Fragment {
                set_offset: 4096,
                len: total,
                // Gerçek şifreli parça boyu her zaman 16'nın katıdır (son
                // düz baytlar sıfır padding ile bloğa tamamlanır).
                cipher_len: 3 * MAX_CIPHER_WINDOW + 128,
            }],
            starts: vec![0],
            total_len: total,
            filename: "film.mkv".into(),
            crypt: None,
        };

        let windows = map.cipher_windows(0..total);
        assert_eq!(windows.len(), 4, "3 full windows + 123 bytes remainder");
        assert!(windows.iter().all(|w| w.take <= MAX_CIPHER_WINDOW));
        // Her pencerenin şifreli okuma aralığı 16 hizalı ve zincir IV'si bir
        // önceki şifreli bloğa işaret eder.
        for window in &windows {
            assert_eq!(window.data.start % AES_BLOCK_SIZE, 0);
            assert_eq!((window.data.end - window.data.start) % AES_BLOCK_SIZE, 0);
        }
        assert_eq!(windows[0].iv, None, "first window uses InitV");
        for pair in windows.windows(2) {
            let expected_iv = (pair[0].data.end - AES_BLOCK_SIZE)..pair[0].data.end;
            assert_eq!(pair[1].iv, Some(expected_iv));
        }
        // Pencereler çözülmüş uzayı eksiksiz ve sıralı kapsar.
        let covered: u64 = windows.iter().map(|w| w.take).sum();
        assert_eq!(covered, total);
    }

    #[test]
    fn sifreli_buyuk_veri_pencere_sinirlari_arasi_dogru_cozulur() {
        // MAX_CIPHER_WINDOW'dan büyük gerçek şifreli fixture: pencere ve cilt
        // sınırlarını aşan CBC zinciri uçtan uca doğrulanır.
        let plain: Vec<u8> = (0..(MAX_CIPHER_WINDOW as usize + 700_123))
            .map(|i| ((i * 31 + i / 7) % 256) as u8)
            .collect();
        let split_at = (MAX_CIPHER_WINDOW as usize) / 2;
        let fixture = build_encrypted_fixture("nzbsifresi", &plain, split_at);
        let bytes = concat(&fixture.volumes);
        let map = build_fragment_map(
            &mut Cursor::new(bytes.clone()),
            &layout(&fixture.volumes),
            Some(&fixture.password),
        )
        .unwrap();

        let windows = map.cipher_windows(0..map.total_len);
        assert!(
            windows.len() >= 2,
            "a large read must split across windows"
        );
        assert!(windows.iter().all(|w| w.take <= MAX_CIPHER_WINDOW));

        let out = read_decrypted_range(&map, &bytes, 0..map.total_len);
        assert_eq!(out, plain);
        // Ortadan rasgele bir aralık da pencere sınırına denk gelecek biçimde.
        let mid = MAX_CIPHER_WINDOW - 40_000;
        let out = read_decrypted_range(&map, &bytes, mid..mid + 100_000);
        assert_eq!(out, plain[mid as usize..(mid + 100_000) as usize]);
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
                .unwrap_or_else(|error| panic!("could not read fixture ({name}): {error}"))
        }

        /// Ciltleri sanal set uzayında birleştirip parça eşlemini kurar.
        fn open_set(volume_names: &[&str], password: Option<&str>) -> (Vec<u8>, FragmentMap) {
            let volumes: Vec<Vec<u8>> = volume_names.iter().map(|name| read_fixture(name)).collect();
            let bytes = concat(&volumes);
            let map = build_fragment_map(&mut Cursor::new(bytes.clone()), &layout(&volumes), password)
                .unwrap_or_else(|error| panic!("could not open fixture set: {error}"));
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
                "RAR archive is password-protected and the NZB carries no password"
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
