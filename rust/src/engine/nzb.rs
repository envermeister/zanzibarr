//! NZB parser: XML → dosya listesi → segment (message-ID) listesi.
//!
//! NZB, bir binari yayınının hangi Usenet article'larından (segmentlerden)
//! oluştuğunu tarif eder. Buradaki `bytes` değerleri yEnc-KODLU article
//! boyutlarıdır; çözülmüş dosya içi ofsetler yEnc başlıklarından
//! (`=ypart begin/end`) gelir — byte-range eşleyici o bilgiyi kullanır.

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Nzb {
    /// `<head><meta type="...">` çiftleri (ör. title, password).
    pub meta: Vec<(String, String)>,
    pub files: Vec<NzbFile>,
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
        self.files.iter().map(NzbFile::encoded_bytes).sum()
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
        self.segments.iter().map(|s| s.bytes).sum()
    }

    /// Segment numaraları 1'den n'e kesintisiz mi? (eksik segment kontrolü)
    pub fn is_contiguous(&self) -> bool {
        self.segments
            .iter()
            .enumerate()
            .all(|(i, s)| s.number == i as u32 + 1)
    }
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
    let mut nzb = Nzb { meta: Vec::new(), files: Vec::new() };
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
                    date: attr_value(&e, b"date")?
                        .and_then(|v| v.trim().parse().ok()),
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
                            date: attr_value(&e, b"date")?
                                .and_then(|v| v.trim().parse().ok()),
                            subject: attr_value(&e, b"subject")?.unwrap_or_default(),
                            groups: Vec::new(),
                            segments: Vec::new(),
                        });
                    }
                    b"segment" => {
                        let number = attr_value(&e, b"number")?
                            .and_then(|v| v.trim().parse().ok())
                            .ok_or_else(|| {
                                NzbError::Malformed("segmentte number yok".into())
                            })?;
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
}
