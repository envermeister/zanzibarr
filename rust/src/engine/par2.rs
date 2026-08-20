//! PAR2 (Parchive) — paket ayrıştırma, dilim sağlık denetimi ve
//! Reed-Solomon (GF(2^16)) onarımı.
//!
//! Algoritma PAR 2.0 belirtiminden ve par2cmdline'ın davranışından port
//! edilmiştir (kod kopyalanmamıştır): GF(2^16) üreteci 0x1100B, girdi
//! dilimlerinin taban değerleri 65535 ile aralarında asal logaritmaların
//! antilog'ları, kurtarma dilimi katsayıları `taban ^ üs` biçimindedir.
//! Doğrulama, referans uygulamanın ürettiği gerçek arşivlerle (tests/
//! fixtures/par2) birebir bayt karşılaştırmasıyla yapılır.
//!
//! Bu modül ağsızdır; .par2 dosyalarının içeriği bayt dizisi olarak verilir.
//! Motor entegrasyonu (eksik segment onarımı) bu modelin üzerine kurulur.

use std::collections::HashMap;
use std::fmt::Write as _;

use once_cell::sync::Lazy;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum Par2Error {
    #[error("malformed PAR2 packet: {0}")]
    Format(String),
    #[error("PAR2 packet MD5 mismatch")]
    PacketHashMismatch,
    #[error("insufficient recovery slices: {needed} needed, {available} available")]
    NotEnoughRecovery { needed: usize, available: usize },
    #[error("could not solve Reed-Solomon matrix")]
    SingularMatrix,
    #[error("repaired slice checksum mismatch (global slice {0})")]
    RepairMismatch(u64),
}

// ---------------------------------------------------------------------------
// Paket katmanı
// ---------------------------------------------------------------------------

const PACKET_MAGIC: &[u8; 8] = b"PAR2\0PKT";
const TYPE_MAIN: &[u8; 16] = b"PAR 2.0\0Main\0\0\0\0";
const TYPE_FILEDESC: &[u8; 16] = b"PAR 2.0\0FileDesc";
const TYPE_IFSC: &[u8; 16] = b"PAR 2.0\0IFSC\0\0\0\0";
const TYPE_RECVSLIC: &[u8; 16] = b"PAR 2.0\0RecvSlic";
const PACKET_HEADER_SIZE: usize = 64;

struct Packet<'a> {
    packet_type: &'a [u8; 16],
    body: &'a [u8],
}

/// Bayt dizisindeki tüm PAR2 paketlerini sırayla döndürür. Her paketin
/// uzunluk hizası ve gövde MD5'i doğrulanır; bozuk paket tüm dosyayı
/// geçersiz kılar.
fn parse_packets(data: &[u8]) -> Result<Vec<Packet<'_>>, Par2Error> {
    let mut packets = Vec::new();
    let mut cursor = 0usize;
    while cursor < data.len() {
        if data.len() - cursor < PACKET_HEADER_SIZE {
            return Err(Par2Error::Format(format!(
                "fewer than {} bytes left at offset {cursor} for a packet header",
                data.len() - cursor
            )));
        }
        let header = &data[cursor..cursor + PACKET_HEADER_SIZE];
        if &header[..8] != PACKET_MAGIC {
            return Err(Par2Error::Format(format!(
                "no PAR2 signature at offset {cursor}"
            )));
        }
        let length = u64::from_le_bytes(header[8..16].try_into().expect("8 bayt")) as usize;
        if length < PACKET_HEADER_SIZE || !length.is_multiple_of(4) || cursor + length > data.len() {
            return Err(Par2Error::Format(format!(
                "invalid packet size {length} at offset {cursor}"
            )));
        }
        let expected_hash: [u8; 16] = header[16..32].try_into().expect("16 bayt");
        // Paket MD5'i ilk üç alan (magic/length/hash) SONRASINI kapsar:
        // setid + type + gövde.
        let hashed_region = &data[cursor + 32..cursor + length];
        if md5::compute(hashed_region).0 != expected_hash {
            return Err(Par2Error::PacketHashMismatch);
        }
        let packet_type: &[u8; 16] = header[48..64].try_into().expect("16 bayt");
        let body = &data[cursor + PACKET_HEADER_SIZE..cursor + length];
        packets.push(Packet { packet_type, body });
        cursor += length;
    }
    Ok(packets)
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

pub type FileId = [u8; 16];

#[derive(Debug, Clone)]
pub struct FileDesc {
    pub id: FileId,
    pub name: String,
    pub length: u64,
    pub hash_full: [u8; 16],
    pub hash_16k: [u8; 16],
}

#[derive(Debug, Clone, Copy)]
pub struct SliceChecksum {
    pub md5: [u8; 16],
    pub crc32: u32,
}

#[derive(Debug)]
pub struct RecoverySlice {
    pub exponent: u32,
    pub data: Vec<u8>,
}

/// Bir recovery set'i: ana .par2 + tüm vol dosyalarının birleşik görünümü.
#[derive(Debug)]
pub struct Par2Set {
    pub slice_size: u64,
    /// Main paketindeki sırayla dosyalar — global dilim numaralandırması
    /// bu sıraya göredir.
    pub files: Vec<FileDesc>,
    pub checksums: HashMap<FileId, Vec<SliceChecksum>>,
    /// Üs değerine göre artan sıralı kurtarma dilimleri.
    pub recovery: Vec<RecoverySlice>,
}

impl Par2Set {
    /// Tüm .par2 dosyalarının (ana + vol) içeriklerini birleştirir.
    pub fn from_parts(parts: &[&[u8]]) -> Result<Self, Par2Error> {
        let mut slice_size = None;
        let mut file_order: Vec<FileId> = Vec::new();
        let mut files: HashMap<FileId, FileDesc> = HashMap::new();
        let mut checksums: HashMap<FileId, Vec<SliceChecksum>> = HashMap::new();
        let mut recovery = Vec::new();

        for part in parts {
            for packet in parse_packets(part)? {
                match packet.packet_type {
                    t if t == TYPE_MAIN => {
                        if packet.body.len() < 12 {
                            return Err(Par2Error::Format("Main packet is short".into()));
                        }
                        let this_slice_size = u64::from_le_bytes(
                            packet.body[0..8].try_into().expect("8 bayt"),
                        );
                        let count = u32::from_le_bytes(
                            packet.body[8..12].try_into().expect("4 bayt"),
                        ) as usize;
                        if packet.body.len() < 12 + count * 16 {
                            return Err(Par2Error::Format("Main file list is short".into()));
                        }
                        let mut ids = Vec::with_capacity(count);
                        for index in 0..count {
                            ids.push(
                                <FileId>::try_from(
                                    &packet.body[12 + index * 16..12 + (index + 1) * 16],
                                )
                                .expect("16 bayt"),
                            );
                        }
                        // vol dosyaları da Main/FileDesc/IFSC kopyalarını taşır;
                        // ilk Main benimsenir, sonrakiler aynıysa yok sayılır.
                        match &slice_size {
                            None => {
                                slice_size = Some(this_slice_size);
                                file_order = ids;
                            }
                            Some(existing) => {
                                if *existing != this_slice_size || file_order != ids {
                                    return Err(Par2Error::Format(
                                        "conflicting Main packets".into(),
                                    ));
                                }
                            }
                        }
                    }
                    t if t == TYPE_FILEDESC => {
                        if packet.body.len() < 56 {
                            return Err(Par2Error::Format("FileDesc packet is short".into()));
                        }
                        let id: FileId = packet.body[0..16].try_into().expect("16 bayt");
                        let hash_full: [u8; 16] =
                            packet.body[16..32].try_into().expect("16 bayt");
                        let hash_16k: [u8; 16] =
                            packet.body[32..48].try_into().expect("16 bayt");
                        let length = u64::from_le_bytes(
                            packet.body[48..56].try_into().expect("8 bayt"),
                        );
                        let name_bytes = &packet.body[56..];
                        let name_plain = name_bytes
                            .split(|byte| *byte == 0)
                            .next()
                            .unwrap_or_default();
                        let name = String::from_utf8_lossy(name_plain).into_owned();
                        // fileid = MD5(hash16k || length || name); ad, paketteki
                        // hizalama NUL dolgusu OLMADAN hesaplanır.
                        let mut id_input = Vec::with_capacity(24 + name_plain.len());
                        id_input.extend_from_slice(&hash_16k);
                        id_input.extend_from_slice(&length.to_le_bytes());
                        id_input.extend_from_slice(name_plain);
                        if md5::compute(&id_input).0 != id {
                            return Err(Par2Error::Format(format!(
                                "file id of `{name}` does not match its checksum"
                            )));
                        }
                        files.insert(
                            id,
                            FileDesc {
                                id,
                                name,
                                length,
                                hash_full,
                                hash_16k,
                            },
                        );
                    }
                    t if t == TYPE_IFSC => {
                        if packet.body.len() < 16 || (packet.body.len() - 16) % 20 != 0 {
                            return Err(Par2Error::Format("IFSC packet is short/misaligned".into()));
                        }
                        let id: FileId = packet.body[0..16].try_into().expect("16 bayt");
                        // Yinelenen IFSC paketi (vol kopyaları) atlanır.
                        let entry = checksums.entry(id).or_default();
                        if entry.is_empty() {
                            for chunk in packet.body[16..].chunks_exact(20) {
                                entry.push(SliceChecksum {
                                    md5: chunk[0..16].try_into().expect("16 bayt"),
                                    crc32: u32::from_le_bytes(
                                        chunk[16..20].try_into().expect("4 bayt"),
                                    ),
                                });
                            }
                        }
                    }
                    t if t == TYPE_RECVSLIC => {
                        if packet.body.len() < 4 {
                            return Err(Par2Error::Format("RecvSlic packet is short".into()));
                        }
                        recovery.push(RecoverySlice {
                            exponent: u32::from_le_bytes(
                                packet.body[0..4].try_into().expect("4 bayt"),
                            ),
                            data: packet.body[4..].to_vec(),
                        });
                    }
                    _ => {} // Creator vb. önemsiz
                }
            }
        }

        let slice_size = slice_size.ok_or_else(|| Par2Error::Format("Main paketi yok".into()))?;
        if slice_size == 0 || slice_size % 4 != 0 {
            return Err(Par2Error::Format(format!(
                "invalid slice size {slice_size}"
            )));
        }
        for slice in &recovery {
            if slice.data.len() as u64 != slice_size {
                return Err(Par2Error::Format(format!(
                    "kurtarma dilimi {} bayt, dilim boyutu {slice_size}",
                    slice.data.len()
                )));
            }
        }
        recovery.sort_by_key(|slice| slice.exponent);
        recovery.dedup_by(|a, b| a.exponent == b.exponent);

        let mut ordered_files = Vec::with_capacity(file_order.len());
        for id in &file_order {
            let file = files
                .remove(id)
                .ok_or_else(|| Par2Error::Format("no FileDesc for file in Main".into()))?;
            ordered_files.push(file);
        }

        Ok(Self {
            slice_size,
            files: ordered_files,
            checksums,
            recovery,
        })
    }

    /// Dosyanın dilim sayısı (son dilim sıfır dolgulu sayılır).
    pub fn file_slice_count(&self, file: &FileDesc) -> u64 {
        file.length.div_ceil(self.slice_size)
    }

    /// Tüm girdi dilimlerinin toplamı (Main sırasıyla).
    pub fn total_input_slices(&self) -> u64 {
        self.files.iter().map(|file| self.file_slice_count(file)).sum()
    }

    /// Her dosyanın global dilim aralığı: (dosya indeksi, ilk dilim, adet).
    pub fn global_slice_map(&self) -> Vec<(usize, u64, u64)> {
        let mut out = Vec::with_capacity(self.files.len());
        let mut cursor = 0u64;
        for (index, file) in self.files.iter().enumerate() {
            let count = self.file_slice_count(file);
            out.push((index, cursor, count));
            cursor += count;
        }
        out
    }

    /// Dosyanın `slice_index`'li diliminin sağlamasını döndürür.
    pub fn slice_checksum(&self, file: &FileDesc, slice_index: u64) -> Option<SliceChecksum> {
        self.checksums
            .get(&file.id)
            .and_then(|entries| entries.get(slice_index as usize).copied())
    }
}

// ---------------------------------------------------------------------------
// Sağlık denetimi
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SliceHealth {
    Ok,
    /// Veri var ama sağlama uyuşmuyor.
    Damaged,
    /// Veri yok ya da eksik (dosya hiç yok / kısa).
    Missing,
}

/// Tek dosyanın dilim sağlığını denetler. `data` None ise tüm dilimler
/// Missing sayılır. Son dilim sıfır dolguyla tamamlanır.
pub fn check_file(
    set: &Par2Set,
    file: &FileDesc,
    data: Option<&[u8]>,
) -> Vec<SliceHealth> {
    let slice_count = set.file_slice_count(file);
    let mut out = Vec::with_capacity(slice_count as usize);
    let slice_size = set.slice_size as usize;
    let mut padded = vec![0u8; slice_size];

    for index in 0..slice_count {
        let start = index as usize * slice_size;
        let health = match data {
            Some(data) if start < data.len() => {
                let real = (data.len() - start).min(slice_size);
                let slice = if real == slice_size {
                    &data[start..start + slice_size]
                } else {
                    padded[..real].copy_from_slice(&data[start..start + real]);
                    for byte in &mut padded[real..] {
                        *byte = 0;
                    }
                    &padded
                };
                match set.slice_checksum(file, index) {
                    Some(checksum)
                        if md5::compute(slice).0 == checksum.md5
                            && crc32fast::hash(slice) == checksum.crc32 =>
                    {
                        SliceHealth::Ok
                    }
                    _ => SliceHealth::Damaged,
                }
            }
            _ => SliceHealth::Missing,
        };
        out.push(health);
    }
    out
}

// ---------------------------------------------------------------------------
// GF(2^16) — üreteç 0x1100B
// ---------------------------------------------------------------------------

const GF_LIMIT: usize = 65535;

struct Gf16Tables {
    log: Box<[u16; 65536]>,
    alog: Box<[u16; 65536]>,
}

static GF16: Lazy<Gf16Tables> = Lazy::new(|| {
    let mut log = vec![0u16; 65536].into_boxed_slice();
    let mut alog = vec![0u16; 65536].into_boxed_slice();
    let mut b: u32 = 1;
    for l in 0..GF_LIMIT {
        log[b as usize] = l as u16;
        alog[l] = b as u16;
        b <<= 1;
        if b & 65536 != 0 {
            b ^= 0x1100B;
        }
    }
    log[0] = GF_LIMIT as u16;
    alog[GF_LIMIT] = 0;
    Gf16Tables {
        log: log.try_into().expect("65536 eleman"),
        alog: alog.try_into().expect("65536 eleman"),
    }
});

fn gf_mul(a: u16, b: u16) -> u16 {
    if a == 0 || b == 0 {
        return 0;
    }
    let sum = GF16.log[a as usize] as u32 + GF16.log[b as usize] as u32;
    let sum = if sum >= GF_LIMIT as u32 {
        sum - GF_LIMIT as u32
    } else {
        sum
    };
    GF16.alog[sum as usize]
}

fn gf_div(a: u16, b: u16) -> u16 {
    debug_assert!(b != 0);
    if a == 0 {
        return 0;
    }
    let diff = GF16.log[a as usize] as i32 - GF16.log[b as usize] as i32;
    let diff = if diff < 0 { diff + GF_LIMIT as i32 } else { diff };
    GF16.alog[diff as usize]
}

fn gf_pow(base: u16, exponent: u32) -> u16 {
    if exponent == 0 {
        return 1;
    }
    if base == 0 {
        return 0;
    }
    let product = GF16.log[base as usize] as u64 * u64::from(exponent);
    GF16.alog[(product % GF_LIMIT as u64) as usize]
}

/// 65535 = 3·5·17·257; logaritma bu çarpanlara bölünmemeli.
fn gcd_coprime_with_limit(log: u32) -> bool {
    !log.is_multiple_of(3) && !log.is_multiple_of(5) && !log.is_multiple_of(17) && !log.is_multiple_of(257)
}

/// Girdi dilimi tabanları: 65535 ile aralarında asal logaritmaların
/// antilog'ları (par2cmdline SetInput davranışı).
fn input_bases(count: u64) -> Result<Vec<u16>, Par2Error> {
    let mut bases = Vec::with_capacity(count as usize);
    let mut logbase = 1u32;
    while bases.len() < count as usize {
        if gcd_coprime_with_limit(logbase) {
            bases.push(GF16.alog[logbase as usize]);
        }
        logbase += 1;
        if logbase as usize >= GF_LIMIT {
            return Err(Par2Error::Format(
                "input slice count exceeds the Reed-Solomon matrix limit".into(),
            ));
        }
    }
    Ok(bases)
}

// ---------------------------------------------------------------------------
// Reed-Solomon onarımı
// ---------------------------------------------------------------------------

/// Dilimi u16 küçük-enden kelime dizisi olarak görüntüler.
fn words(data: &[u8]) -> impl Iterator<Item = u16> + '_ {
    data.chunks_exact(2)
        .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
}

fn words_to_bytes(out: &[u16]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(out.len() * 2);
    for word in out {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    bytes
}

/// `factor * input` kelime-kelime `out`'a XOR'lar.
fn gf_mul_add(factor: u16, input: &[u8], out: &mut [u16]) {
    match factor {
        0 => {}
        1 => {
            for (slot, word) in out.iter_mut().zip(words(input)) {
                *slot ^= word;
            }
        }
        _ => {
            for (slot, word) in out.iter_mut().zip(words(input)) {
                *slot ^= gf_mul(factor, word);
            }
        }
    }
}

/// Kurtarma dilimi üretir: `R = Σ_j (base_j ^ exponent) · dilim_j`.
/// Doğrulama amaçlıdır; referans arşivlerle birebir karşılaştırılır.
pub fn compute_recovery_slice(
    exponent: u32,
    input_slices: &[&[u8]],
    slice_size: u64,
) -> Result<Vec<u8>, Par2Error> {
    let bases = input_bases(input_slices.len() as u64)?;
    let mut out = vec![0u16; slice_size as usize / 2];
    for (base, slice) in bases.iter().zip(input_slices) {
        gf_mul_add(gf_pow(*base, exponent), slice, &mut out);
    }
    Ok(words_to_bytes(&out))
}

/// Onarım planı: matris çözümünün çıktısı. Akışlı kullanım için veri
/// dilimleri plandan ayrı taşınır (bellekte yalnız katsayılar kalır).
#[derive(Debug)]
pub struct RepairPlan {
    /// Sağlam girdi dilimlerinin global indeksleri (sütun sırasıyla).
    pub present_indices: Vec<u64>,
    /// Onarılacak eksik dilimlerin global indeksleri (satır sırasıyla).
    pub missing_indices: Vec<u64>,
    /// Satır başına katsayılar: [sağlam girdi sütunları | kurtarma sütunları].
    factors: Vec<Vec<u16>>,
    /// `set.recovery` içinde kullanılan dilimlerin indeksleri.
    used_recovery: Vec<usize>,
}

/// Eksik dilimler için RS planı kurar. `missing` boşsa hata değil boş plan
/// döner; kurtarma yetersizse `NotEnoughRecovery`.
pub fn plan_repair(set: &Par2Set, missing: &[u64]) -> Result<RepairPlan, Par2Error> {
    let total = set.total_input_slices();
    let mut missing_sorted = missing.to_vec();
    missing_sorted.sort_unstable();
    missing_sorted.dedup();
    for &index in &missing_sorted {
        if index >= total {
            return Err(Par2Error::Format(format!(
                "missing slice {index} is outside total {total} slices"
            )));
        }
    }
    if missing_sorted.len() > set.recovery.len() {
        return Err(Par2Error::NotEnoughRecovery {
            needed: missing_sorted.len(),
            available: set.recovery.len(),
        });
    }
    let present_indices: Vec<u64> = (0..total)
        .filter(|index| missing_sorted.binary_search(index).is_err())
        .collect();
    if missing_sorted.is_empty() {
        return Ok(RepairPlan {
            present_indices,
            missing_indices: Vec::new(),
            factors: Vec::new(),
            used_recovery: Vec::new(),
        });
    }

    let bases = input_bases(total)?;
    let datapresent = present_indices.len();
    let datamissing = missing_sorted.len();
    let incount = datapresent + datamissing;

    let mut left = vec![0u16; datamissing * incount];
    let mut right = vec![0u16; datamissing * datamissing];
    let used_recovery: Vec<usize> = (0..datamissing).collect();
    for (row, &recovery_index) in used_recovery.iter().enumerate() {
        let exponent = set.recovery[recovery_index].exponent;
        for (col, &present) in present_indices.iter().enumerate() {
            left[row * incount + col] = gf_pow(bases[present as usize], exponent);
        }
        left[row * incount + datapresent + row] = 1;
        for (col, &missing) in missing_sorted.iter().enumerate() {
            right[row * datamissing + col] = gf_pow(bases[missing as usize], exponent);
        }
    }

    gauss_elim(&mut left, incount, &mut right, datamissing)?;

    let factors = left
        .chunks_exact(incount)
        .map(|row| row.to_vec())
        .collect();
    Ok(RepairPlan {
        present_indices,
        missing_indices: missing_sorted,
        factors,
        used_recovery,
    })
}

/// Akışlı onarım akümülatörü: sağlam dilimler birer birer beslenir, bellekte
/// yalnız eksik dilim kadar tampon tutulur. Async sürücüler (NNTP) dilimleri
/// await ile çekip senkron [`Self::add_present`] ile işler.
pub struct RepairAccumulators {
    out: Vec<Vec<u16>>,
    slice_size: u64,
}

impl RepairAccumulators {
    pub fn new(plan: &RepairPlan, slice_size: u64) -> Self {
        Self {
            out: vec![vec![0u16; slice_size as usize / 2]; plan.missing_indices.len()],
            slice_size,
        }
    }

    /// `plan.present_indices[column]` diliminin verisini tüm eksik satırlara
    /// katsayısıyla ekler. Veri tam dilim (sıfır dolgulu) olmalı.
    pub fn add_present(&mut self, plan: &RepairPlan, column: usize, data: &[u8]) {
        debug_assert_eq!(data.len() as u64, self.slice_size);
        for (row, factors) in plan.factors.iter().enumerate() {
            gf_mul_add(factors[column], data, &mut self.out[row]);
        }
    }

    /// Kurtarma dilimlerini de uygulayıp onarılan dilimleri IFSC sağlamasıyla
    /// doğrulanmış olarak döndürür.
    pub fn finish(
        mut self,
        set: &Par2Set,
        plan: &RepairPlan,
    ) -> Result<Vec<(u64, Vec<u8>)>, Par2Error> {
        let datapresent = plan.present_indices.len();
        let map = set.global_slice_map();
        let mut repaired = Vec::with_capacity(plan.missing_indices.len());
        for (row, &missing) in plan.missing_indices.iter().enumerate() {
            for (col, &recovery_index) in plan.used_recovery.iter().enumerate() {
                let factor = plan.factors[row][datapresent + col];
                gf_mul_add(factor, &set.recovery[recovery_index].data, &mut self.out[row]);
            }
            let bytes = words_to_bytes(&self.out[row]);

            let (file_index, first_slice, _) = map
                .iter()
                .find(|(_, first, count)| missing >= *first && missing < first + count)
                .copied()
                .expect("global slice map covers the total");
            let file = &set.files[file_index];
            if let Some(checksum) = set.slice_checksum(file, missing - first_slice) {
                if md5::compute(&bytes).0 != checksum.md5 {
                    return Err(Par2Error::RepairMismatch(missing));
                }
            }
            repaired.push((missing, bytes));
        }
        Ok(repaired)
    }
}

/// Eksik/bozuk girdi dilimlerini Reed-Solomon ile yeniden üretir (bellek-içi
/// kolaylık yolu; büyük setlerde [`plan_repair`] + [`RepairAccumulators`]
/// akışlı yolu kullanılmalıdır).
///
/// `input_slices`: global sırayla her dilim için `Some(veri)` (sağlam) veya
/// `None` (eksik/bozuk). Dönüş: (global indeks, sıfır-dolgulu tam dilim)
/// listesi.
pub fn repair(
    set: &Par2Set,
    input_slices: &[Option<Vec<u8>>],
) -> Result<Vec<(u64, Vec<u8>)>, Par2Error> {
    let total = set.total_input_slices();
    if input_slices.len() as u64 != total {
        return Err(Par2Error::Format(format!(
            "{} girdi dilimi verildi, set {total} dilim bekliyor",
            input_slices.len()
        )));
    }
    let missing: Vec<u64> = (0..total)
        .filter(|&index| input_slices[index as usize].is_none())
        .collect();
    let plan = plan_repair(set, &missing)?;
    let mut accumulators = RepairAccumulators::new(&plan, set.slice_size);
    for (column, &present) in plan.present_indices.iter().enumerate() {
        let data = input_slices[present as usize]
            .as_ref()
            .expect("healthy slice");
        accumulators.add_present(&plan, column, data);
    }
    accumulators.finish(set, &plan)
}

/// [left | right] üzerinde Gauss eliminasyonu; right birim matrise iner.
/// Vandermonde yapı tekil olmadığından pivot araması gerekmez
/// (par2cmdline GaussElim davranışı; GF'de çıkarma = XOR).
fn gauss_elim(
    left: &mut [u16],
    leftcols: usize,
    right: &mut [u16],
    rows: usize,
) -> Result<(), Par2Error> {
    for row in 0..rows {
        let pivot = right[row * rows + row];
        if pivot == 0 {
            return Err(Par2Error::SingularMatrix);
        }
        if pivot != 1 {
            for col in 0..leftcols {
                let value = left[row * leftcols + col];
                if value != 0 {
                    left[row * leftcols + col] = gf_div(value, pivot);
                }
            }
            right[row * rows + row] = 1;
            for col in row + 1..rows {
                let value = right[row * rows + col];
                if value != 0 {
                    right[row * rows + col] = gf_div(value, pivot);
                }
            }
        }

        for row2 in 0..rows {
            if row2 == row {
                continue;
            }
            let scale = right[row2 * rows + row];
            match scale {
                0 => {}
                1 => {
                    for col in 0..leftcols {
                        let value = left[row * leftcols + col];
                        if value != 0 {
                            left[row2 * leftcols + col] ^= value;
                        }
                    }
                    for col in row..rows {
                        let value = right[row * rows + col];
                        if value != 0 {
                            right[row2 * rows + col] ^= value;
                        }
                    }
                }
                _ => {
                    for col in 0..leftcols {
                        let value = left[row * leftcols + col];
                        if value != 0 {
                            left[row2 * leftcols + col] ^= gf_mul(value, scale);
                        }
                    }
                    for col in row..rows {
                        let value = right[row * rows + col];
                        if value != 0 {
                            right[row2 * rows + col] ^= gf_mul(value, scale);
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

/// Hata ayıklama için set özetini metne döker (sır içermez).
pub fn describe(set: &Par2Set) -> String {
    let mut out = String::new();
    let _ = write!(
        out,
        "PAR2 seti: {} dosya, dilim {} bayt, {} kurtarma dilimi",
        set.files.len(),
        set.slice_size,
        set.recovery.len()
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    const FIXTURE_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/par2");

    fn fixture(name: &str) -> Vec<u8> {
        std::fs::read(PathBuf::from(FIXTURE_DIR).join(name))
            .unwrap_or_else(|error| panic!("could not read fixture ({name}): {error}"))
    }

    /// Referans flatdata seti: testdata.par2 + tüm vol dosyaları.
    fn reference_set() -> Par2Set {
        let index = fixture("testdata.par2");
        let vols: Vec<Vec<u8>> = [
            "testdata.vol00+01.par2",
            "testdata.vol01+02.par2",
            "testdata.vol03+04.par2",
            "testdata.vol07+08.par2",
            "testdata.vol15+16.par2",
            "testdata.vol31+29.par2",
        ]
        .into_iter()
        .map(fixture)
        .collect();
        let mut parts: Vec<&[u8]> = vec![index.as_slice()];
        parts.extend(vols.iter().map(Vec::as_slice));
        Par2Set::from_parts(&parts).expect("reference set must parse")
    }

    fn reference_files(set: &Par2Set) -> Vec<Vec<u8>> {
        set.files
            .iter()
            .map(|file| fixture(&file.name))
            .collect()
    }

    /// Dosya baytlarını global dilim dizisine (sıfır dolgulu) çevirir.
    fn global_slices(set: &Par2Set, files: &[Vec<u8>]) -> Vec<Vec<u8>> {
        let slice_size = set.slice_size as usize;
        let mut out = Vec::new();
        for (file, data) in set.files.iter().zip(files) {
            for index in 0..set.file_slice_count(file) {
                let start = index as usize * slice_size;
                let mut slice = vec![0u8; slice_size];
                let real = (data.len() - start).min(slice_size);
                slice[..real].copy_from_slice(&data[start..start + real]);
                out.push(slice);
            }
        }
        out
    }

    #[test]
    fn referans_set_ayrisir() {
        let set = reference_set();
        assert_eq!(set.files.len(), 10);
        assert_eq!(set.slice_size, 5376);
        assert_eq!(set.recovery.len(), 60);
        // Main paketindeki sıralama alfabetik olmak zorunda değil; küme
        // olarak tüm dosyalar bulunmalı ve her birinin IFSC girdisi dilim
        // sayısıyla birebir olmalı.
        let mut names: Vec<&str> = set.files.iter().map(|f| f.name.as_str()).collect();
        names.sort_unstable();
        assert_eq!(
            names,
            (0..10)
                .map(|index| format!("test-{index}.data"))
                .collect::<Vec<_>>()
                .iter()
                .map(String::as_str)
                .collect::<Vec<_>>()
        );
        for file in &set.files {
            assert_eq!(
                set.checksums[&file.id].len() as u64,
                set.file_slice_count(file)
            );
        }
    }

    #[test]
    fn saglik_denetimi_temiz_set() {
        let set = reference_set();
        let files = reference_files(&set);
        for (file, data) in set.files.iter().zip(&files) {
            let health = check_file(&set, file, Some(data));
            assert!(
                health.iter().all(|h| *h == SliceHealth::Ok),
                "`{}` should parse cleanly: {:?}",
                file.name,
                health
            );
        }
    }

    #[test]
    fn bozuk_dilim_yakalanir() {
        let set = reference_set();
        let files = reference_files(&set);
        let file = &set.files[0];
        let mut damaged = files[0].clone();
        // 3. dilimin ortasına zarar ver.
        damaged[3 * set.slice_size as usize + 100] ^= 0xFF;
        let health = check_file(&set, file, Some(&damaged));
        assert_eq!(health[3], SliceHealth::Damaged);
        assert!(health[..3].iter().all(|h| *h == SliceHealth::Ok));
    }

    #[test]
    fn kurtarma_dilimleri_referansla_birebir() {
        // Interop kanıtı: referans veriden kurtarma dilimlerini yeniden
        // üretip par2cmdline'ın vol dosyalarıyla bayt birebir karşılaştır.
        let set = reference_set();
        let files = reference_files(&set);
        let slices = global_slices(&set, &files);
        let refs: Vec<&[u8]> = slices.iter().map(Vec::as_slice).collect();

        for (position, expected) in set.recovery.iter().enumerate() {
            let computed = compute_recovery_slice(expected.exponent, &refs, set.slice_size)
                .expect("recovery slice must be producible");
            assert_eq!(
                computed,
                expected.data,
                "{}. recovery slice (exponent {}) does not match the reference",
                position,
                expected.exponent
            );
        }
    }

    #[test]
    fn tek_bozuk_dilim_onarilir() {
        let set = reference_set();
        let files = reference_files(&set);
        let mut slices = global_slices(&set, &files);

        // test-0.data'nın 5. dilimini boz (set.slice_size=4000, 17 dilim).
        let damaged_global = 5u64;
        slices[damaged_global as usize][123] ^= 0xA5;
        let original = {
            let files = reference_files(&set);
            global_slices(&set, &files)[damaged_global as usize].clone()
        };

        let input: Vec<Option<Vec<u8>>> = slices
            .iter()
            .enumerate()
            .map(|(index, slice)| (index as u64 != damaged_global).then(|| slice.clone()))
            .collect();
        let repaired = repair(&set, &input).expect("a single slice must be repairable");
        assert_eq!(repaired.len(), 1);
        assert_eq!(repaired[0].0, damaged_global);
        assert_eq!(repaired[0].1, original);
    }

    #[test]
    fn eksik_dosya_butunuyle_onarilir() {
        let set = reference_set();
        let files = reference_files(&set);
        let slices = global_slices(&set, &files);
        let map = set.global_slice_map();
        // test-3.data'nın Main sırasındaki yerini bul (sıralama alfabetik
        // olmak zorunda değil).
        let (file_index, first, count) = map
            .iter()
            .find(|(index, _, _)| set.files[*index].name == "test-3.data")
            .copied()
            .expect("test-3.data set içinde");
        assert_eq!(count, 27);

        let input: Vec<Option<Vec<u8>>> = slices
            .iter()
            .enumerate()
            .map(|(index, slice)| {
                let global = index as u64;
                (!(global >= first && global < first + count)).then(|| slice.clone())
            })
            .collect();
        let repaired = repair(&set, &input).expect("file must be repairable");
        assert_eq!(repaired.len() as u64, count);

        // Dosyayı yeniden kur ve orijinaliyle karşılaştır.
        let slice_size = set.slice_size as usize;
        let mut rebuilt = Vec::with_capacity(set.files[file_index].length as usize);
        for (global, data) in &repaired {
            assert!(*global >= first && *global < first + count);
            rebuilt.extend_from_slice(data);
        }
        rebuilt.truncate(set.files[file_index].length as usize);
        assert_eq!(rebuilt, files[file_index]);
        let _ = slice_size;
    }

    #[test]
    fn yetersiz_kurtarma_reddedilir() {
        let set = reference_set();
        let files = reference_files(&set);
        let slices = global_slices(&set, &files);
        // 61 dilim eksik: 60 kurtarma dilimini aşıyor.
        let input: Vec<Option<Vec<u8>>> = slices
            .iter()
            .enumerate()
            .map(|(index, slice)| (index >= 61).then(|| slice.clone()))
            .collect();
        assert!(matches!(
            repair(&set, &input),
            Err(Par2Error::NotEnoughRecovery {
                needed: 61,
                available: 60
            })
        ));
    }

    #[test]
    fn gf_aritmetigi_temel_ozellikler() {
        // Çarpma birimi ve tersi.
        for &a in &[1u16, 2, 7, 0x1234, 0xBEEF, 0xFFFF] {
            assert_eq!(gf_mul(a, 1), a);
            let inverse = gf_div(1, a);
            assert_eq!(gf_mul(a, inverse), 1);
        }
        // pow tutarlılığı: a^2 = a·a.
        assert_eq!(gf_pow(0x1234, 2), gf_mul(0x1234, 0x1234));
        assert_eq!(gf_pow(5, 0), 1);
    }
}
