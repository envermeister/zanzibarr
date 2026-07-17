//! yEnc decoder: tek article gövdesi → ham baytlar; multipart birleştirme;
//! CRC32 doğrulama.
//!
//! Girdi, NNTP katmanında dot-unstuffing yapılmış (satır başındaki `..` →
//! `.`) ve nokta sonlandırıcısı ayıklanmış article GÖVDESİDİR. `=ybegin`
//! öncesi ve `=yend` sonrası satırlar yok sayılır.
//!
//! Kodlama: her bayt `(b + 42) % 256` ile yazılır; kritik çıktılar
//! (NUL, LF, CR, `=`) `=` + `(out + 64) % 256` olarak kaçırılır. Çözme bunun
//! tersidir ve kaçış genel biçimiyle ele alınır (ör. satır başı `.` kaçışı
//! gibi isteğe bağlı kaçışlar da doğru çözülür).

use thiserror::Error;

#[derive(Debug, Error)]
pub enum YencError {
    #[error("=ybegin satırı bulunamadı")]
    MissingBegin,
    #[error("=yend satırı bulunamadı")]
    MissingEnd,
    #[error("bozuk yEnc: {0}")]
    Malformed(String),
    #[error("satır kaçış karakteriyle (=) bitiyor")]
    TrailingEscape,
    #[error("boyut uyuşmazlığı: beklenen {expected}, çözülen {actual}")]
    SizeMismatch { expected: u64, actual: u64 },
    #[error("CRC32 uyuşmazlığı: beklenen {expected:08x}, hesaplanan {actual:08x}")]
    CrcMismatch { expected: u32, actual: u32 },
    #[error("parçalar kesintisiz değil (beklenen ofset {expected}, gelen {found})")]
    PartsNotContiguous { expected: u64, found: u64 },
    #[error("birleştirilecek parça yok")]
    NoParts,
}

/// Tek bir article'dan çözülmüş yEnc parçası.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct YencPart {
    pub name: String,
    /// Dosyanın TAMAMININ boyutu (`=ybegin size=`).
    pub file_size: u64,
    pub part: Option<u32>,
    pub total: Option<u32>,
    /// Dosya içinde 1 tabanlı ilk bayt (`=ypart begin=`, kapsayıcı).
    pub begin: Option<u64>,
    /// Dosya içinde 1 tabanlı son bayt (`=ypart end=`, kapsayıcı).
    pub end: Option<u64>,
    /// `=yend pcrc32=` (varsa; decode sırasında doğrulanmıştır).
    pub part_crc32: Option<u32>,
    /// `=yend crc32=` — dosyanın tamamının CRC'si (genelde son parçada).
    pub file_crc32: Option<u32>,
    pub data: Vec<u8>,
}

impl YencPart {
    /// Parçanın dosya içindeki 0 tabanlı başlangıç ofseti.
    pub fn offset(&self) -> u64 {
        self.begin.map(|b| b - 1).unwrap_or(0)
    }
}

/// Article gövdesini çözer; `pcrc32` varsa doğrular, tek parçalı dosyada
/// `crc32` varsa onu da doğrular.
pub fn decode(article: &[u8]) -> Result<YencPart, YencError> {
    let mut lines = article.split(|&b| b == b'\n').map(strip_cr);

    // =ybegin'e kadar atla.
    let header = loop {
        match lines.next() {
            Some(line) if line.starts_with(b"=ybegin ") => break line,
            Some(_) => continue,
            None => return Err(YencError::MissingBegin),
        }
    };

    let header = parse_keywords(header, b"=ybegin ")?;
    let file_size = header
        .get_u64("size")?
        .ok_or_else(|| YencError::Malformed("=ybegin'de size yok".into()))?;
    let part_number = header.get_u32("part")?;
    let total = header.get_u32("total")?;
    let mut part = YencPart {
        name: header
            .name
            .ok_or_else(|| YencError::Malformed("=ybegin'de name yok".into()))?,
        file_size,
        part: part_number,
        total,
        begin: None,
        end: None,
        part_crc32: None,
        file_crc32: None,
        data: Vec::new(),
    };

    let mut first_data_line: Option<&[u8]> = None;
    if part.part.is_some() {
        // Multipart'ta =ybegin'i =ypart izler (spec gereği zorunlu; bazı
        // eski kodlayıcılar atlar, o durumda satır veri kabul edilir).
        match lines.next() {
            Some(line) if line.starts_with(b"=ypart ") => {
                let ypart = parse_keywords(line, b"=ypart ")?;
                part.begin = ypart.get_u64("begin")?;
                part.end = ypart.get_u64("end")?;
            }
            Some(line) => first_data_line = Some(line),
            None => return Err(YencError::MissingEnd),
        }
    }

    // Veri satırları → =yend.
    let mut trailer: Option<&[u8]> = None;
    let data_lines = first_data_line.into_iter().chain(&mut lines);
    for line in data_lines {
        if line.starts_with(b"=yend") {
            trailer = Some(line);
            break;
        }
        if line.starts_with(b"=y") {
            return Err(YencError::Malformed(format!(
                "veri içinde beklenmeyen kontrol satırı: {}",
                String::from_utf8_lossy(line)
            )));
        }
        decode_line(line, &mut part.data)?;
    }
    let trailer = trailer.ok_or(YencError::MissingEnd)?;
    let trailer = parse_keywords(trailer, b"=yend")?;

    // Boyut doğrulaması: =yend size, BU parçanın çözülmüş boyutudur.
    if let Some(expected) = trailer.get_u64("size")? {
        let actual = part.data.len() as u64;
        if expected != actual {
            return Err(YencError::SizeMismatch { expected, actual });
        }
    }
    // =ypart varsa aralık uzunluğu da tutmalı.
    if let (Some(begin), Some(end)) = (part.begin, part.end) {
        let expected = end + 1 - begin;
        let actual = part.data.len() as u64;
        if expected != actual {
            return Err(YencError::SizeMismatch { expected, actual });
        }
    }

    part.part_crc32 = trailer.get_crc32("pcrc32")?;
    part.file_crc32 = trailer.get_crc32("crc32")?;

    if let Some(expected) = part.part_crc32 {
        verify_crc(expected, &part.data)?;
    }
    // Tek parçalı dosyada crc32 tüm veriyi doğrular.
    if part.part.is_none() {
        if let Some(expected) = part.file_crc32 {
            verify_crc(expected, &part.data)?;
        }
    }

    Ok(part)
}

/// Çözülmüş parçaları tam dosyaya birleştirir: ofset sırasına dizer,
/// kesintisizliği ve toplam boyutu denetler, `crc32` varsa doğrular.
pub fn assemble(parts: &[YencPart]) -> Result<Vec<u8>, YencError> {
    if parts.is_empty() {
        return Err(YencError::NoParts);
    }

    let mut sorted: Vec<&YencPart> = parts.iter().collect();
    sorted.sort_by_key(|p| p.offset());

    let file_size = sorted[0].file_size;
    let mut out = Vec::with_capacity(file_size as usize);
    for part in &sorted {
        let expected = out.len() as u64;
        let found = part.offset();
        if found != expected {
            return Err(YencError::PartsNotContiguous { expected, found });
        }
        out.extend_from_slice(&part.data);
    }

    if out.len() as u64 != file_size {
        return Err(YencError::SizeMismatch {
            expected: file_size,
            actual: out.len() as u64,
        });
    }
    if let Some(expected) = sorted.iter().find_map(|p| p.file_crc32) {
        verify_crc(expected, &out)?;
    }
    Ok(out)
}

fn verify_crc(expected: u32, data: &[u8]) -> Result<(), YencError> {
    let actual = crc32fast::hash(data);
    if actual != expected {
        return Err(YencError::CrcMismatch { expected, actual });
    }
    Ok(())
}

fn strip_cr(line: &[u8]) -> &[u8] {
    line.strip_suffix(b"\r").unwrap_or(line)
}

/// Tek veri satırını çözüp `out`'a ekler.
fn decode_line(line: &[u8], out: &mut Vec<u8>) -> Result<(), YencError> {
    let mut i = 0;
    while i < line.len() {
        let b = line[i];
        if b == b'=' {
            i += 1;
            let &next = line.get(i).ok_or(YencError::TrailingEscape)?;
            out.push(next.wrapping_sub(64).wrapping_sub(42));
        } else {
            out.push(b.wrapping_sub(42));
        }
        i += 1;
    }
    Ok(())
}

/// `=ybegin`/`=ypart`/`=yend` satırlarındaki `anahtar=değer` çiftleri.
/// `name=` satırın kalanını olduğu gibi alır (boşluk içerebilir).
struct Keywords {
    pairs: Vec<(String, String)>,
    name: Option<String>,
}

impl Keywords {
    fn get(&self, key: &str) -> Option<&str> {
        self.pairs
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }

    fn get_u64(&self, key: &str) -> Result<Option<u64>, YencError> {
        self.get(key)
            .map(|v| {
                v.parse()
                    .map_err(|_| YencError::Malformed(format!("{key}={v} sayı değil")))
            })
            .transpose()
    }

    fn get_u32(&self, key: &str) -> Result<Option<u32>, YencError> {
        Ok(self.get_u64(key)?.map(|v| v as u32))
    }

    fn get_crc32(&self, key: &str) -> Result<Option<u32>, YencError> {
        self.get(key)
            .map(|v| {
                u32::from_str_radix(v.trim(), 16)
                    .map_err(|_| YencError::Malformed(format!("{key}={v} onaltılık değil")))
            })
            .transpose()
    }
}

fn parse_keywords(line: &[u8], prefix: &[u8]) -> Result<Keywords, YencError> {
    let rest = line
        .strip_prefix(prefix)
        .ok_or_else(|| YencError::Malformed("başlık öneki eksik".into()))?;
    // Başlıklar ASCII'dir; name alanı ise gelişigüzel bayt içerebilir.
    let rest = String::from_utf8_lossy(rest);

    let (attrs, name) = match rest.find("name=") {
        Some(pos) => (
            rest[..pos].to_string(),
            Some(rest[pos + 5..].trim_end().to_string()),
        ),
        None => (rest.into_owned(), None),
    };

    let mut pairs = Vec::new();
    for token in attrs.split_ascii_whitespace() {
        let (key, value) = token
            .split_once('=')
            .ok_or_else(|| YencError::Malformed(format!("anahtar=değer değil: {token}")))?;
        pairs.push((key.to_string(), value.to_string()));
    }
    Ok(Keywords { pairs, name })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// "123456789"un IEEE CRC32'si — bağımsız bilinen değer (0xCBF43926).
    /// Baytları +42 kaydırınca '[' ile 'c' arası karakterler çıkar; kaçış
    /// gerekmez. Fixture tümüyle elle yazılmıştır ki decoder kendi kendini
    /// doğrulamasın.
    const SINGLE_PART: &[u8] = b"\
=ybegin part=1 total=1 line=128 size=9 name=test.bin\r\n\
=ypart begin=1 end=9\r\n\
[\\]^_`abc\r\n\
=yend size=9 part=1 pcrc32=cbf43926\r\n";

    #[test]
    fn bilinen_tek_parca_cozulur_ve_crc_dogrulanir() {
        let part = decode(SINGLE_PART).unwrap();
        assert_eq!(part.data, b"123456789");
        assert_eq!(part.name, "test.bin");
        assert_eq!(part.file_size, 9);
        assert_eq!(part.part, Some(1));
        assert_eq!(part.begin, Some(1));
        assert_eq!(part.end, Some(9));
        assert_eq!(part.offset(), 0);
        assert_eq!(part.part_crc32, Some(0xCBF43926));
    }

    #[test]
    fn kacis_dizileri_cozulur() {
        // [214, 224, 227, 19] baytları kodlanınca tam da kritik karakterlere
        // (NUL, LF, CR, '=') denk gelir; hepsi kaçışlı yazılmak zorundadır.
        let article = b"\
=ybegin line=128 size=4 name=esc.bin\r\n\
=@=J=M=}\r\n\
=yend size=4\r\n";
        let part = decode(article).unwrap();
        assert_eq!(part.data, vec![214, 224, 227, 19]);
    }

    #[test]
    fn ybegin_oncesi_ve_yend_sonrasi_yok_sayilir() {
        let article = b"\
X-Header-Artigi: bir sey\r\n\
\r\n\
=ybegin line=128 size=9 name=t\r\n\
[\\]^_`abc\r\n\
=yend size=9 crc32=cbf43926\r\n\
sonradan gelen cop\r\n";
        let part = decode(article).unwrap();
        assert_eq!(part.data, b"123456789");
        // Tek parçalı dosyada crc32 da doğrulanmış olmalı.
        assert_eq!(part.file_crc32, Some(0xCBF43926));
    }

    #[test]
    fn multipart_birlestirilir_ve_dosya_crc_dogrulanir() {
        // "123456789" iki parça: "12345" (1-5) + "6789" (6-9).
        let p1 = decode(
            b"=ybegin part=1 total=2 line=128 size=9 name=t\r\n\
=ypart begin=1 end=5\r\n\
[\\]^_\r\n\
=yend size=5 part=1\r\n",
        )
        .unwrap();
        let p2 = decode(
            b"=ybegin part=2 total=2 line=128 size=9 name=t\r\n\
=ypart begin=6 end=9\r\n\
`abc\r\n\
=yend size=4 part=2 crc32=cbf43926\r\n",
        )
        .unwrap();

        // Sıra bağımsız: ters verilse de doğru birleşmeli.
        let file = assemble(&[p2, p1]).unwrap();
        assert_eq!(file, b"123456789");
    }

    #[test]
    fn eksik_parca_kesintisizlik_hatasi_verir() {
        let p1 = decode(
            b"=ybegin part=1 total=3 line=128 size=9 name=t\r\n\
=ypart begin=1 end=5\r\n\
[\\]^_\r\n\
=yend size=5 part=1\r\n",
        )
        .unwrap();
        let p3 = decode(
            b"=ybegin part=3 total=3 line=128 size=9 name=t\r\n\
=ypart begin=8 end=9\r\n\
bc\r\n\
=yend size=2 part=3\r\n",
        )
        .unwrap();
        assert!(matches!(
            assemble(&[p1, p3]),
            Err(YencError::PartsNotContiguous {
                expected: 5,
                found: 7
            })
        ));
    }

    #[test]
    fn yanlis_pcrc32_reddedilir() {
        let article = b"\
=ybegin line=128 size=9 name=t\r\n\
[\\]^_`abc\r\n\
=yend size=9 pcrc32=deadbeef\r\n";
        assert!(matches!(
            decode(article),
            Err(YencError::CrcMismatch {
                expected: 0xDEADBEEF,
                ..
            })
        ));
    }

    #[test]
    fn yanlis_boyut_reddedilir() {
        let article = b"\
=ybegin line=128 size=9 name=t\r\n\
[\\]^_`abc\r\n\
=yend size=8\r\n";
        assert!(matches!(
            decode(article),
            Err(YencError::SizeMismatch {
                expected: 8,
                actual: 9
            })
        ));
    }

    #[test]
    fn yend_yoksa_hata() {
        let article = b"=ybegin line=128 size=9 name=t\r\n[\\]^_`abc\r\n";
        assert!(matches!(decode(article), Err(YencError::MissingEnd)));
    }

    #[test]
    fn ybegin_yoksa_hata() {
        assert!(matches!(
            decode(b"rastgele icerik\r\n"),
            Err(YencError::MissingBegin)
        ));
    }

    #[test]
    fn satir_sonundaki_kacis_hata_verir() {
        let article = b"=ybegin line=128 size=1 name=t\r\nx=\r\n=yend size=1\r\n";
        assert!(matches!(decode(article), Err(YencError::TrailingEscape)));
    }

    #[test]
    fn rastgele_baytlar_gidis_donus_korunur() {
        // Test-içi minik kodlayıcı: decoder'ın tersini üretir; 0..=255 tüm
        // bayt değerlerini kapsayan girdiyle gidiş-dönüş doğrulanır.
        let data: Vec<u8> = (0u8..=255).chain(255u8..=255).collect();
        let mut body = Vec::new();
        for (i, &b) in data.iter().enumerate() {
            let out = b.wrapping_add(42);
            match out {
                0 | b'\n' | b'\r' | b'=' => {
                    body.push(b'=');
                    body.push(out.wrapping_add(64));
                }
                _ => body.push(out),
            }
            if i % 64 == 63 {
                body.extend_from_slice(b"\r\n");
            }
        }
        body.extend_from_slice(b"\r\n");

        let mut article =
            format!("=ybegin line=64 size={} name=roundtrip.bin\r\n", data.len()).into_bytes();
        article.extend_from_slice(&body);
        article.extend_from_slice(
            format!(
                "=yend size={} crc32={:08x}\r\n",
                data.len(),
                crc32fast::hash(&data)
            )
            .as_bytes(),
        );

        let part = decode(&article).unwrap();
        assert_eq!(part.data, data);
    }
}
