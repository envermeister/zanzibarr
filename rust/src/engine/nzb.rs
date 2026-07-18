//! NZB parser: XML → dosya listesi → segment (message-ID) listesi.
//!
//! NZB, bir binari yayınının hangi Usenet article'larından (segmentlerden)
//! oluştuğunu tarif eder. Buradaki `bytes` değerleri yEnc-KODLU article
//! boyutlarıdır; çözülmüş dosya içi ofsetler yEnc başlıklarından
//! (`=ypart begin/end`) gelir — byte-range eşleyici o bilgiyi kullanır.

use std::{collections::BTreeMap, fmt};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum NzbError {
    #[error("XML okuma hatası: {0}")]
    Xml(#[from] quick_xml::Error),
    #[error("bozuk NZB: {0}")]
    Malformed(String),
    #[error("NZB kök öğesi (<nzb>) bulunamadı")]
    NotAnNzb,
}

/// NZB içeriğinden oynatılacak dosyayı seçme ve arşiv setlerini
/// doğrulama hataları.
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum NzbContentError {
    #[error("NZB'de doğrudan oynatılabilir medya dosyası yok")]
    NoPlayableMedia,
    #[error("`{filename}` dosyasında segment {missing} eksik veya sırası bozuk")]
    NonContiguousSegments { filename: String, missing: u32 },
    #[error("`{filename}` dosyası {declared} segment bildiriyor, NZB'de {actual} segment var")]
    DeclaredSegmentCountMismatch {
        filename: String,
        declared: u32,
        actual: u32,
    },
    #[error(
        "bölünmüş 7z seti `{archive_name}` için volume {expected:03} beklenirken {found:03} bulundu"
    )]
    Split7zVolumeGap {
        archive_name: String,
        expected: u32,
        found: u32,
    },
    #[error("bölünmüş 7z seti `{archive_name}` içinde volume {number:03} birden fazla kez var")]
    DuplicateSplit7zVolume { archive_name: String, number: u32 },
    #[error("bölünmüş RAR seti `{archive_name}` için volume {expected} beklenirken {found} bulundu")]
    SplitRarVolumeGap {
        archive_name: String,
        expected: u32,
        found: u32,
    },
    #[error("bölünmüş RAR seti `{archive_name}` içinde volume {number} birden fazla kez var")]
    DuplicateSplitRarVolume { archive_name: String, number: u32 },
}

/// Sayısal volume sırasıyla bir 7z parçası.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Split7zVolume<'a> {
    pub number: u32,
    pub file: &'a NzbFile,
}

/// Aynı `.7z` taban adına ait, `001`'den başlayan kesintisiz volume seti.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Split7zSet<'a> {
    pub archive_name: String,
    pub volumes: Vec<Split7zVolume<'a>>,
}

/// Sayısal volume sırasıyla bir RAR parçası.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SplitRarVolume<'a> {
    pub number: u32,
    pub file: &'a NzbFile,
}

/// Aynı taban ada ait, `1`'den başlayan kesintisiz RAR volume seti.
/// Modern `partNN.rar` ve eski usul `.rar` + `.rNN` adlandırma desteklenir.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SplitRarSet<'a> {
    pub archive_name: String,
    pub volumes: Vec<SplitRarVolume<'a>>,
}

#[derive(Clone, PartialEq, Eq)]
pub struct Nzb {
    /// `<head><meta type="...">` çiftleri (ör. title, password).
    pub meta: Vec<(String, String)>,
    pub files: Vec<NzbFile>,
}

/// Meta değerleri arasında arşiv parolası bulunabilir. `Debug`, yalnızca
/// anahtar adlarını göstererek bu değerlerin loglara sızmasını engeller.
impl fmt::Debug for Nzb {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let meta_keys = self
            .meta
            .iter()
            .map(|(key, _)| key.as_str())
            .collect::<Vec<_>>();

        formatter
            .debug_struct("Nzb")
            .field("meta_keys", &meta_keys)
            .field("files", &self.files)
            .finish()
    }
}

impl Nzb {
    pub fn meta_value(&self, key: &str) -> Option<&str> {
        self.meta
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(key))
            .map(|(_, v)| v.as_str())
    }

    /// Tüm dosyaların kodlu (yEnc) boyut toplamı.
    pub fn total_encoded_bytes(&self) -> u64 {
        self.files.iter().fold(0u64, |total, file| {
            total.saturating_add(file.encoded_bytes())
        })
    }

    /// Doğrudan oynatılabilir dosyalar arasından kodlu boyutu en büyük
    /// olanı seçer. PAR2 veya arşiv volume'ları segment sayıları yüzünden
    /// yanlışlıkla medya olarak seçilemez.
    pub fn select_playable_media(&self) -> Result<&NzbFile, NzbContentError> {
        let file = self
            .files
            .iter()
            .filter(|file| file.is_playable_media())
            .max_by_key(|file| file.encoded_bytes())
            .ok_or(NzbContentError::NoPlayableMedia)?;
        file.validate_segments()?;
        Ok(file)
    }

    /// NZB'deki bölünmüş 7z volume'larını taban ada göre gruplar,
    /// sayısal sıraya koyar ve her setin `001`'den kesintisiz ilerlediğini
    /// doğrular.
    pub fn split_7z_sets(&self) -> Result<Vec<Split7zSet<'_>>, NzbContentError> {
        let mut groups: BTreeMap<String, (String, Vec<Split7zVolume<'_>>)> = BTreeMap::new();

        for file in &self.files {
            let Some(filename) = file.filename() else {
                continue;
            };
            let Some((archive_name, number)) = split_7z_volume_name(filename) else {
                continue;
            };
            file.validate_segments()?;

            let entry = groups
                .entry(archive_name.to_ascii_lowercase())
                .or_insert_with(|| (archive_name.to_string(), Vec::new()));
            entry.1.push(Split7zVolume { number, file });
        }

        let mut sets = Vec::with_capacity(groups.len());
        for (_, (archive_name, mut volumes)) in groups {
            volumes.sort_by_key(|volume| volume.number);

            let mut expected = 1;
            for volume in &volumes {
                if volume.number < expected {
                    return Err(NzbContentError::DuplicateSplit7zVolume {
                        archive_name,
                        number: volume.number,
                    });
                }
                if volume.number != expected {
                    return Err(NzbContentError::Split7zVolumeGap {
                        archive_name,
                        expected,
                        found: volume.number,
                    });
                }
                expected = expected.saturating_add(1);
            }

            sets.push(Split7zSet {
                archive_name,
                volumes,
            });
        }
        Ok(sets)
    }

    /// NZB'deki bölünmüş RAR volume'larını taban ada göre gruplar, sayısal
    /// sıraya koyar ve her setin `1`'den kesintisiz ilerlediğini doğrular.
    /// Modern `partNN.rar` ve eski usul `.rar` + `.rNN` adlandırma aynı
    /// taban ad altında birleşir.
    pub fn split_rar_sets(&self) -> Result<Vec<SplitRarSet<'_>>, NzbContentError> {
        let mut groups: BTreeMap<String, (String, Vec<SplitRarVolume<'_>>)> = BTreeMap::new();

        for file in &self.files {
            let Some(filename) = file.filename() else {
                continue;
            };
            let Some((archive_name, number)) = split_rar_volume_name(filename) else {
                continue;
            };
            file.validate_segments()?;

            let entry = groups
                .entry(archive_name.to_ascii_lowercase())
                .or_insert_with(|| (archive_name.to_string(), Vec::new()));
            entry.1.push(SplitRarVolume { number, file });
        }

        let mut sets = Vec::with_capacity(groups.len());
        for (_, (archive_name, mut volumes)) in groups {
            volumes.sort_by_key(|volume| volume.number);

            let mut expected = 1;
            for volume in &volumes {
                if volume.number < expected {
                    return Err(NzbContentError::DuplicateSplitRarVolume {
                        archive_name,
                        number: volume.number,
                    });
                }
                if volume.number != expected {
                    return Err(NzbContentError::SplitRarVolumeGap {
                        archive_name,
                        expected,
                        found: volume.number,
                    });
                }
                expected = expected.saturating_add(1);
            }

            sets.push(SplitRarSet {
                archive_name,
                volumes,
            });
        }
        Ok(sets)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NzbFile {
    pub poster: String,
    /// Unix zaman damgası (saniye); NZB'de yoksa veya bozuksa None.
    pub date: Option<u64>,
    pub subject: String,
    pub groups: Vec<String>,
    /// Numaraya göre sıralı; aynı numaranın tekrarı ayıklanmış (ilki kalır).
    pub segments: Vec<NzbSegment>,
}

impl NzbFile {
    /// Subject'ten dosya adını çıkarır. İki yaygın biçimi de destekler:
    /// - Tırnaklı: `[1/2] - "ad.mkv" yEnc (1/3)` → tırnak içi alınır.
    /// - Tırnaksız: `ad.mkv (1/0)` → parça soneki temizlenip kalan alınır.
    ///
    /// Döndürülen dilim `subject`'e ödünç bağlıdır; bu yüzden `String` değil
    /// `&str`'tir (kopyasız).
    pub fn filename(&self) -> Option<&str> {
        // 1) Çift tırnaklı blok.
        if let Some(start) = self.subject.find('"') {
            let start = start + 1;
            if let Some(rel_end) = self.subject[start..].find('"') {
                let name = self.subject[start..start + rel_end].trim();
                if !name.is_empty() {
                    return Some(name);
                }
            }
        }

        // 2) Tırnaksız: sondaki " yEnc"/" (n/m)" gibi ekleri kırp.
        let mut name = self.subject.trim();
        // Baştaki "[n/m] - " toplu-gönderi öneki.
        if let Some(pos) = name.find("] - ") {
            if name.starts_with('[') {
                name = name[pos + 4..].trim_start();
            }
        }
        // " yEnc" ve sonrasını at.
        if let Some(pos) = name.find(" yEnc") {
            name = name[..pos].trim_end();
        }
        // Sondaki " (n/m)" parça göstergesini at.
        if name.ends_with(')') {
            if let Some(pos) = name.rfind(" (") {
                if name[pos + 2..name.len() - 1]
                    .split_once('/')
                    .is_some_and(|(a, b)| {
                        !a.is_empty()
                            && a.bytes().all(|c| c.is_ascii_digit())
                            && b.bytes().all(|c| c.is_ascii_digit())
                    })
                {
                    name = name[..pos].trim_end();
                }
            }
        }
        // Anlamlı bir dosya adı ancak bir uzantı içerirse kabul edilir;
        // aksi halde subject serbest metindir.
        (!name.is_empty() && name.contains('.')).then_some(name)
    }

    pub fn encoded_bytes(&self) -> u64 {
        // Bu değer yalnız seçim/ilerleme tahmini içindir; çözülmüş ofsetlerde
        // kullanılmaz. Bozuk bir NZB'nin u64 toplamını taşırıp panic üretmesine
        // izin vermek yerine en büyük tahmin değerine doyurulur.
        self.segments
            .iter()
            .fold(0u64, |total, segment| total.saturating_add(segment.bytes))
    }

    /// Dosya adı libmpv'ye doğrudan verilebilen yaygın bir video kabı mı?
    pub fn is_playable_media(&self) -> bool {
        self.filename().is_some_and(is_playable_media_filename)
    }

    /// Subject'in sonundaki `(parça/toplam)` bilgisinden ilan edilen segment
    /// sayısını okur. Bazı poster'lar `(1/0)` yazar; sıfır bilinmeyen toplam
    /// olarak kabul edilir.
    pub fn declared_segment_count(&self) -> Option<u32> {
        let end = self.subject.rfind(')')?;
        let start = self.subject[..end].rfind('(')?;
        let (_, total) = self.subject[start + 1..end].split_once('/')?;
        let total = total.trim();
        if total.is_empty() || !total.bytes().all(|byte| byte.is_ascii_digit()) {
            return None;
        }
        total.parse::<u32>().ok().filter(|count| *count > 0)
    }

    /// Segment listesinin 1'den başlayıp kesintisiz ilerlediğini ve subject
    /// bir toplam bildiriyorsa bu toplamla uyuştuğunu doğrular.
    pub fn validate_segments(&self) -> Result<(), NzbContentError> {
        let filename = self.filename().unwrap_or("adı bilinmeyen dosya");
        let mut expected = 1_u32;
        for segment in &self.segments {
            if segment.number != expected {
                return Err(NzbContentError::NonContiguousSegments {
                    filename: filename.to_string(),
                    missing: expected,
                });
            }
            expected = expected.saturating_add(1);
        }

        if self.segments.is_empty() {
            return Err(NzbContentError::NonContiguousSegments {
                filename: filename.to_string(),
                missing: 1,
            });
        }

        if let Some(declared) = self.declared_segment_count() {
            let actual = self.segments.len().min(u32::MAX as usize) as u32;
            if actual < declared {
                return Err(NzbContentError::NonContiguousSegments {
                    filename: filename.to_string(),
                    missing: actual.saturating_add(1),
                });
            }
            if actual != declared {
                return Err(NzbContentError::DeclaredSegmentCountMismatch {
                    filename: filename.to_string(),
                    declared,
                    actual,
                });
            }
        }

        Ok(())
    }

    /// Segment numaraları 1'den n'e kesintisiz mi? (eksik segment kontrolü)
    pub fn is_contiguous(&self) -> bool {
        !self.segments.is_empty()
            && self
                .segments
                .iter()
                .enumerate()
                .all(|(i, s)| s.number == i as u32 + 1)
    }
}

/// libmpv/FFmpeg'e arşiv açmadan doğrudan verilebilen yaygın video kabı ve
/// elementary stream uzantıları. Liste `server::content_type_for` ile birlikte
/// tutulur; server testi her uzantının açık bir MIME eşlemesi olduğunu doğrular.
pub(crate) const PLAYABLE_VIDEO_EXTENSIONS: &[&str] = &[
    "264", "265", "3g2", "3gp", "amv", "asf", "av1", "avc", "avi", "bik", "bk2", "divx", "dv",
    "dvr-ms", "evo", "f4v", "flv", "gxf", "h261", "h263", "h264", "h265", "hevc", "ivf", "m1v",
    "m2t", "m2ts", "m2v", "m4v", "mj2", "mjpeg", "mjpg", "mjp2", "mk3d", "mkv", "mov", "mp4",
    "mpeg", "mpg", "mpv", "mts", "mxf", "nsv", "nut", "obu", "ogm", "ogv", "qt", "rm", "rmvb",
    "roq", "tp", "trp", "ts", "vc1", "vob", "vro", "webm", "wmv", "wtv", "y4m",
];

/// Karşılaştırma ASCII büyük/küçük harf duyarsızdır. Son uzantıdan sonra ek
/// taşıyan (`video.mp4.exe`) veya arşiv/kurtarma dosyaları kabul edilmez.
pub fn is_playable_media_filename(filename: &str) -> bool {
    let Some((_, extension)) = filename.rsplit_once('.') else {
        return false;
    };
    PLAYABLE_VIDEO_EXTENSIONS
        .iter()
        .any(|candidate| extension.eq_ignore_ascii_case(candidate))
}

/// `film.7z.001` biçimindeki bir adı `(film.7z, 1)` olarak ayırır.
/// Yalnızca tamamı rakam olan son ekler volume kabul edilir.
pub fn split_7z_volume_name(filename: &str) -> Option<(&str, u32)> {
    let lowercase = filename.to_ascii_lowercase();
    let marker = lowercase.rfind(".7z.")?;
    if marker == 0 {
        return None;
    }

    let digits = &filename[marker + 4..];
    if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let number = digits.parse::<u32>().ok()?;
    Some((&filename[..marker + 3], number))
}

/// RAR volume adını `(taban ad, 1'den başlayan numara)` olarak çözer:
/// - Modern: `film.part03.rar` → `(film, 3)`; tek `film.rar` → `(film, 1)`.
/// - Eski usul: `film.rar` ilk cilttir, `film.r00` → 2, `film.r01` → 3, ...
///
/// Yalnızca tamamı rakam olan ekler volume kabul edilir; `rar` kelimesini
/// rastgele içeren adlar (ör. `filrarr`) ve `.rev` kurtarma ciltleri elenir.
pub fn split_rar_volume_name(filename: &str) -> Option<(&str, u32)> {
    let lowercase = filename.to_ascii_lowercase();

    if let Some(stem) = lowercase.strip_suffix(".rar") {
        if let Some(marker) = stem.rfind(".part") {
            let digits = &stem[marker + 5..];
            if marker > 0
                && !digits.is_empty()
                && digits.bytes().all(|byte| byte.is_ascii_digit())
            {
                let number = digits.parse::<u32>().ok().filter(|number| *number >= 1)?;
                return Some((&filename[..marker], number));
            }
        }
        // Tek başına `.rar`: eski usul ilk cilt veya tek ciltlik arşiv.
        // `.partNN.rar` tabansız kalmışsa (gizli dosya benzeri) geçersizdir.
        if !stem.is_empty() && !stem.starts_with(".part") {
            return Some((&filename[..filename.len() - 4], 1));
        }
        return None;
    }

    // Eski usul devam ciltleri: `.r00`, `.r01`, ...
    let (stem, extension) = lowercase.rsplit_once('.')?;
    if extension.len() >= 2
        && extension.starts_with('r')
        && extension[1..].bytes().all(|byte| byte.is_ascii_digit())
    {
        let number = extension[1..].parse::<u32>().ok()?;
        // `.r00` ikinci cilttir; `.rar` her zaman 1 sayılır.
        return Some((&filename[..stem.len()], number.checked_add(2)?));
    }
    None
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NzbSegment {
    pub number: u32,
    /// yEnc-kodlu article boyutu (çözülmüş boyut DEĞİL).
    pub bytes: u64,
    /// Açılı ayraçsız message-ID; NNTP isterken `<...>` eklenir.
    pub message_id: String,
}

pub fn parse_nzb(xml: &str) -> Result<Nzb, NzbError> {
    use quick_xml::events::Event;

    let mut reader = quick_xml::Reader::from_str(xml);
    let mut nzb = Nzb {
        meta: Vec::new(),
        files: Vec::new(),
    };
    let mut saw_root = false;

    // Anlık durum: içinde bulunulan öğeler ve biriken metin.
    let mut current_file: Option<NzbFile> = None;
    let mut current_segment: Option<NzbSegment> = None;
    let mut current_meta_type: Option<String> = None;
    let mut text = String::new();

    loop {
        match reader.read_event().map_err(NzbError::Xml)? {
            // Kendinden kapanan öğeler End üretmez; içerik taşıyamayacakları
            // için yalnızca anlamlı olanlar ele alınır.
            Event::Empty(e) => match e.local_name().as_ref() {
                b"nzb" => saw_root = true,
                b"segment" => {
                    return Err(NzbError::Malformed(
                        "boş <segment/> öğesi: message-ID yok".into(),
                    ));
                }
                b"file" => nzb.files.push(NzbFile {
                    poster: attr_value(&e, b"poster")?.unwrap_or_default(),
                    date: attr_value(&e, b"date")?.and_then(|v| v.trim().parse().ok()),
                    subject: attr_value(&e, b"subject")?.unwrap_or_default(),
                    groups: Vec::new(),
                    segments: Vec::new(),
                }),
                _ => {}
            },
            Event::Start(e) => {
                text.clear();
                match e.local_name().as_ref() {
                    b"nzb" => saw_root = true,
                    b"meta" => {
                        current_meta_type = attr_value(&e, b"type")?;
                    }
                    b"file" => {
                        current_file = Some(NzbFile {
                            poster: attr_value(&e, b"poster")?.unwrap_or_default(),
                            date: attr_value(&e, b"date")?.and_then(|v| v.trim().parse().ok()),
                            subject: attr_value(&e, b"subject")?.unwrap_or_default(),
                            groups: Vec::new(),
                            segments: Vec::new(),
                        });
                    }
                    b"segment" => {
                        let number = attr_value(&e, b"number")?
                            .and_then(|v| v.trim().parse().ok())
                            .ok_or_else(|| NzbError::Malformed("segmentte number yok".into()))?;
                        let bytes = attr_value(&e, b"bytes")?
                            .and_then(|v| v.trim().parse().ok())
                            .unwrap_or(0);
                        current_segment = Some(NzbSegment {
                            number,
                            bytes,
                            message_id: String::new(),
                        });
                    }
                    _ => {}
                }
            }
            Event::Text(t) => {
                let piece = t
                    .xml10_content()
                    .map_err(|err| NzbError::Malformed(err.to_string()))?;
                text.push_str(&piece);
            }
            Event::CData(c) => {
                text.push_str(&String::from_utf8_lossy(&c));
            }
            Event::End(e) => {
                match e.local_name().as_ref() {
                    b"meta" => {
                        if let Some(key) = current_meta_type.take() {
                            nzb.meta.push((key, text.trim().to_string()));
                        }
                    }
                    b"group" => {
                        if let Some(file) = current_file.as_mut() {
                            let group = text.trim().to_string();
                            if !group.is_empty() {
                                file.groups.push(group);
                            }
                        }
                    }
                    b"segment" => {
                        if let (Some(file), Some(mut seg)) =
                            (current_file.as_mut(), current_segment.take())
                        {
                            seg.message_id = normalize_message_id(&text);
                            if seg.message_id.is_empty() {
                                return Err(NzbError::Malformed(format!(
                                    "segment {} message-ID içermiyor",
                                    seg.number
                                )));
                            }
                            file.segments.push(seg);
                        }
                    }
                    b"file" => {
                        if let Some(mut file) = current_file.take() {
                            file.segments.sort_by_key(|s| s.number);
                            file.segments.dedup_by_key(|s| s.number);
                            nzb.files.push(file);
                        }
                    }
                    _ => {}
                }
                text.clear();
            }
            Event::Eof => break,
            // DOCTYPE, yorum, PI vb. yok sayılır.
            _ => {}
        }
    }

    if !saw_root {
        return Err(NzbError::NotAnNzb);
    }
    Ok(nzb)
}

/// Öznitelik değerini yerel ada göre bulur (namespace önekinden bağımsız).
fn attr_value(
    e: &quick_xml::events::BytesStart<'_>,
    name: &[u8],
) -> Result<Option<String>, NzbError> {
    for attr in e.attributes() {
        let attr = attr.map_err(|err| NzbError::Malformed(err.to_string()))?;
        if attr.key.local_name().as_ref() == name {
            let value = attr
                .normalized_value(quick_xml::XmlVersion::Implicit1_0)
                .map_err(|err| NzbError::Malformed(err.to_string()))?;
            return Ok(Some(value.into_owned()));
        }
    }
    Ok(None)
}

/// Message-ID'yi açılı ayraçsız kanonik biçime indirger.
fn normalize_message_id(raw: &str) -> String {
    raw.trim()
        .trim_start_matches('<')
        .trim_end_matches('>')
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(name: &str, segment_numbers: &[u32], bytes_per_segment: u64) -> NzbFile {
        let declared = segment_numbers.iter().copied().max().unwrap_or(0);
        NzbFile {
            poster: "poster@example.test".into(),
            date: None,
            subject: format!("\"{name}\" yEnc (1/{declared})"),
            groups: vec!["alt.binaries.test".into()],
            segments: segment_numbers
                .iter()
                .map(|number| NzbSegment {
                    number: *number,
                    bytes: bytes_per_segment,
                    message_id: format!("{name}-{number}@example.test"),
                })
                .collect(),
        }
    }

    const SAMPLE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE nzb PUBLIC "-//newzBin//DTD NZB 1.1//EN" "http://www.newzbin.com/DTD/nzb/nzb-1.1.dtd">
<nzb xmlns="http://www.newzbin.com/DTD/2003/nzb">
  <head>
    <meta type="title">Ornek Video</meta>
    <meta type="password">s3cret</meta>
  </head>
  <file poster="poster@example.com (Poster)" date="1710000000" subject="[1/2] - &quot;video.mkv&quot; yEnc (1/3)">
    <groups>
      <group>alt.binaries.example</group>
      <group>alt.binaries.test</group>
    </groups>
    <segments>
      <segment bytes="700" number="2">seg2@news.example.com</segment>
      <segment bytes="750" number="1">&lt;seg1@news.example.com&gt;</segment>
      <segment bytes="700" number="2">dup-seg2@news.example.com</segment>
      <segment bytes="300" number="3">seg3@news.example.com</segment>
    </segments>
  </file>
  <file poster="poster@example.com (Poster)" date="1710000100" subject="[2/2] - &quot;video.nfo&quot; yEnc (1/1)">
    <groups><group>alt.binaries.example</group></groups>
    <segments>
      <segment bytes="120" number="1">nfo1@news.example.com</segment>
    </segments>
  </file>
</nzb>
"#;

    #[test]
    fn sample_nzb_dosya_ve_segmentleri_cozumlenir() {
        let nzb = parse_nzb(SAMPLE).unwrap();

        assert_eq!(nzb.meta_value("title"), Some("Ornek Video"));
        assert_eq!(nzb.meta_value("password"), Some("s3cret"));
        assert_eq!(nzb.files.len(), 2);

        let video = &nzb.files[0];
        assert_eq!(video.poster, "poster@example.com (Poster)");
        assert_eq!(video.date, Some(1710000000));
        assert_eq!(video.filename(), Some("video.mkv"));
        assert_eq!(
            video.groups,
            vec!["alt.binaries.example", "alt.binaries.test"]
        );

        // Sıralı, tekrarsız; ayraçlı message-ID normalize edilmiş.
        let numbers: Vec<u32> = video.segments.iter().map(|s| s.number).collect();
        assert_eq!(numbers, vec![1, 2, 3]);
        assert_eq!(video.segments[0].message_id, "seg1@news.example.com");
        assert_eq!(video.segments[1].message_id, "seg2@news.example.com");
        assert_eq!(video.encoded_bytes(), 750 + 700 + 300);
        assert!(video.is_contiguous());

        assert_eq!(nzb.files[1].filename(), Some("video.nfo"));
        assert_eq!(nzb.total_encoded_bytes(), 1750 + 120);
    }

    #[test]
    fn eksik_segment_kesintisizligi_bozar() {
        let xml = r#"<nzb><file subject='"a.bin"'>
            <segments>
              <segment bytes="10" number="1">a@x</segment>
              <segment bytes="10" number="3">c@x</segment>
            </segments></file></nzb>"#;
        let nzb = parse_nzb(xml).unwrap();
        assert!(!nzb.files[0].is_contiguous());
    }

    #[test]
    fn nzb_olmayan_xml_reddedilir() {
        assert!(matches!(
            parse_nzb("<html><body/></html>"),
            Err(NzbError::NotAnNzb)
        ));
    }

    #[test]
    fn bozuk_xml_hata_dondurur() {
        assert!(parse_nzb("<nzb><file></nzb>").is_err());
    }

    #[test]
    fn message_id_siz_segment_reddedilir() {
        let xml = r#"<nzb><file subject='"a"'><segments>
            <segment bytes="1" number="1">  </segment>
            </segments></file></nzb>"#;
        assert!(matches!(parse_nzb(xml), Err(NzbError::Malformed(_))));
    }

    #[test]
    fn tirnaksiz_uzantisiz_subject_dosya_adi_vermez() {
        let xml = r#"<nzb><file subject="tirnak yok"><segments>
            <segment bytes="1" number="1">a@x</segment>
            </segments></file></nzb>"#;
        let nzb = parse_nzb(xml).unwrap();
        assert_eq!(nzb.files[0].filename(), None);
    }

    #[test]
    fn tirnaksiz_parca_sonekli_subject_cozulur() {
        // Kullanıcının gerçek NZB'sindeki biçim.
        let xml = r#"<nzb><file subject="A.Very.Harold.mkv (1/0)"><segments>
            <segment bytes="1" number="1">a@x</segment>
            </segments></file></nzb>"#;
        let nzb = parse_nzb(xml).unwrap();
        assert_eq!(nzb.files[0].filename(), Some("A.Very.Harold.mkv"));
    }

    #[test]
    fn tirnaksiz_yenc_onekli_subject_cozulur() {
        let xml = r#"<nzb><file subject="[1/2] - film.part01.rar yEnc (1/50)"><segments>
            <segment bytes="1" number="1">a@x</segment>
            </segments></file></nzb>"#;
        let nzb = parse_nzb(xml).unwrap();
        assert_eq!(nzb.files[0].filename(), Some("film.part01.rar"));
    }

    #[test]
    fn debug_meta_degerlerini_gizler() {
        let nzb = Nzb {
            meta: vec![
                ("title".into(), "gizli-baslik-degeri".into()),
                ("password".into(), "asla-debuga-girmemeli".into()),
            ],
            files: Vec::new(),
        };

        let debug = format!("{nzb:?}");
        assert!(debug.contains("title"));
        assert!(debug.contains("password"));
        assert!(!debug.contains("gizli-baslik-degeri"));
        assert!(!debug.contains("asla-debuga-girmemeli"));
    }

    #[test]
    fn oynatilabilir_uzantilar_buyuk_kucuk_harf_duyarsizdir() {
        assert!(is_playable_media_filename("film.mkv"));
        assert!(is_playable_media_filename("FILM.MP4"));
        assert!(is_playable_media_filename("kayit.M2TS"));
        assert!(is_playable_media_filename("telefon.3GP"));
        assert!(is_playable_media_filename("kurgu.MXF"));
        assert!(is_playable_media_filename("arsiv.RMVB"));
        assert!(is_playable_media_filename("ham.H264"));
        assert!(is_playable_media_filename("kamera.HEVC"));
        assert!(is_playable_media_filename("animasyon.AV1"));
        assert!(is_playable_media_filename("yayın.WTV"));
        assert!(is_playable_media_filename("stereo.MK3D"));
        assert!(is_playable_media_filename("acik.OGV"));
        assert!(!is_playable_media_filename("film.7z.001"));
        assert!(!is_playable_media_filename("film.vol00+01.par2"));
        assert!(!is_playable_media_filename("film.nfo"));
        assert!(!is_playable_media_filename("film.mp4.exe"));
        assert!(!is_playable_media_filename("altyazi.srt"));
        assert!(!is_playable_media_filename("kapak.jpg"));
    }

    #[test]
    fn genisletilmis_ffmpeg_uzantilari_secici_tarafindan_medya_kabul_edilir() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![
                file("recovery.par2", &[1, 2, 3], 10_000),
                file("master.mxf", &[1, 2], 1_000),
            ],
        };

        assert_eq!(
            nzb.select_playable_media().unwrap().filename(),
            Some("master.mxf")
        );
    }

    #[test]
    fn secici_segment_sayisi_yerine_medya_uzantisi_ve_boyutu_kullanir() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![
                file("recovery.vol00+01.par2", &[1, 2, 3, 4], 10_000),
                file("sample.mkv", &[1], 100),
                file("movie.mp4", &[1, 2], 1_000),
                file("archive.7z.001", &[1, 2, 3, 4, 5], 10_000),
            ],
        };

        assert_eq!(
            nzb.select_playable_media().unwrap().filename(),
            Some("movie.mp4")
        );
    }

    #[test]
    fn kodlu_boyut_tahmini_tasmada_panik_yerine_doyar() {
        let first = file("first.mkv", &[1, 2], u64::MAX);
        let second = file("second.mkv", &[1], 1);
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![first, second],
        };

        assert_eq!(nzb.files[0].encoded_bytes(), u64::MAX);
        assert_eq!(nzb.total_encoded_bytes(), u64::MAX);
    }

    #[test]
    fn secici_dogrudan_medya_yoksa_acik_hata_verir() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![file("archive.7z.001", &[1], 100)],
        };

        assert_eq!(
            nzb.select_playable_media(),
            Err(NzbContentError::NoPlayableMedia)
        );
    }

    #[test]
    fn secici_medya_segment_boslugunu_reddeder() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![file("movie.mkv", &[1, 3], 100)],
        };

        assert!(matches!(
            nzb.select_playable_media(),
            Err(NzbContentError::NonContiguousSegments { missing: 2, .. })
        ));
    }

    #[test]
    fn ilan_edilen_sondaki_eksik_segment_reddedilir() {
        let mut media = file("movie.mkv", &[1, 2], 100);
        media.subject = "\"movie.mkv\" yEnc (1/3)".into();

        assert!(matches!(
            media.validate_segments(),
            Err(NzbContentError::NonContiguousSegments { missing: 3, .. })
        ));
    }

    #[test]
    fn split_7z_adi_ve_volume_numarasi_cozulur() {
        assert_eq!(split_7z_volume_name("Film.7Z.001"), Some(("Film.7Z", 1)));
        assert_eq!(split_7z_volume_name("film.7z.120"), Some(("film.7z", 120)));
        assert_eq!(split_7z_volume_name("film.7z"), None);
        assert_eq!(split_7z_volume_name("film.7z.001.tmp"), None);
    }

    #[test]
    fn split_7z_setleri_sayisal_siraya_koyar_ve_gruplar() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![
                file("movie.7z.3", &[1], 100),
                file("extras.7z.1", &[1], 100),
                file("movie.7z.1", &[1], 100),
                file("movie.7z.2", &[1], 100),
            ],
        };

        let sets = nzb.split_7z_sets().unwrap();
        assert_eq!(sets.len(), 2);
        assert_eq!(sets[0].archive_name, "extras.7z");
        assert_eq!(sets[1].archive_name, "movie.7z");
        assert_eq!(
            sets[1]
                .volumes
                .iter()
                .map(|volume| volume.number)
                .collect::<Vec<_>>(),
            vec![1, 2, 3]
        );
    }

    #[test]
    fn split_7z_volume_boslugunu_reddeder() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![
                file("movie.7z.001", &[1], 100),
                file("movie.7z.003", &[1], 100),
            ],
        };

        assert!(matches!(
            nzb.split_7z_sets(),
            Err(NzbContentError::Split7zVolumeGap {
                expected: 2,
                found: 3,
                ..
            })
        ));
    }

    #[test]
    fn split_7z_duplicate_volume_reddedilir() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![
                file("movie.7z.001", &[1], 100),
                file("movie.7Z.001", &[1], 100),
            ],
        };

        assert!(matches!(
            nzb.split_7z_sets(),
            Err(NzbContentError::DuplicateSplit7zVolume { number: 1, .. })
        ));
    }

    #[test]
    fn split_7z_segment_boslugunu_reddeder() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![file("movie.7z.001", &[1, 3], 100)],
        };

        assert!(matches!(
            nzb.split_7z_sets(),
            Err(NzbContentError::NonContiguousSegments { missing: 2, .. })
        ));
    }

    #[test]
    fn split_rar_modern_ve_eski_usul_adlar_cozulur() {
        assert_eq!(
            split_rar_volume_name("Film.Part03.RAR"),
            Some(("Film", 3))
        );
        assert_eq!(split_rar_volume_name("film.part1.rar"), Some(("film", 1)));
        assert_eq!(split_rar_volume_name("film.rar"), Some(("film", 1)));
        assert_eq!(split_rar_volume_name("film.R00"), Some(("film", 2)));
        assert_eq!(split_rar_volume_name("film.r09"), Some(("film", 11)));
        // Video uzantıları ve rastgele adlar volume sayılmaz.
        assert_eq!(split_rar_volume_name("film.rmvb"), None);
        assert_eq!(split_rar_volume_name("film.r"), None);
        // `.part` eki rakamsızsa ad, düz `.rar` kuralına düşer.
        assert_eq!(
            split_rar_volume_name("film.partx.rar"),
            Some(("film.partx", 1))
        );
        assert_eq!(split_rar_volume_name("film.part00.rar"), None);
        assert_eq!(split_rar_volume_name(".part01.rar"), None);
        assert_eq!(split_rar_volume_name(".rar"), None);
    }

    #[test]
    fn split_rar_setleri_sayisal_siraya_koyar_ve_gruplar() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![
                file("movie.part02.rar", &[1], 100),
                file("extras.rar", &[1], 100),
                file("movie.part01.rar", &[1], 100),
                file("extras.r00", &[1], 100),
            ],
        };

        let sets = nzb.split_rar_sets().unwrap();
        assert_eq!(sets.len(), 2);
        assert_eq!(sets[0].archive_name, "extras");
        assert_eq!(sets[1].archive_name, "movie");
        assert_eq!(
            sets[0]
                .volumes
                .iter()
                .map(|volume| volume.number)
                .collect::<Vec<_>>(),
            vec![1, 2]
        );
        assert_eq!(
            sets[1]
                .volumes
                .iter()
                .map(|volume| volume.number)
                .collect::<Vec<_>>(),
            vec![1, 2]
        );
    }

    #[test]
    fn split_rar_volume_boslugunu_reddeder() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![
                file("movie.part01.rar", &[1], 100),
                file("movie.part03.rar", &[1], 100),
            ],
        };

        assert!(matches!(
            nzb.split_rar_sets(),
            Err(NzbContentError::SplitRarVolumeGap {
                expected: 2,
                found: 3,
                ..
            })
        ));
    }

    #[test]
    fn split_rar_duplicate_volume_reddedilir() {
        let nzb = Nzb {
            meta: Vec::new(),
            files: vec![
                file("movie.part01.rar", &[1], 100),
                file("movie.PART01.RAR", &[1], 100),
            ],
        };

        assert!(matches!(
            nzb.split_rar_sets(),
            Err(NzbContentError::DuplicateSplitRarVolume { number: 1, .. })
        ));
    }
}
