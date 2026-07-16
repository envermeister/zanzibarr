//! Segment ↔ byte-range eşleyici — seek'in kalbi.
//!
//! Player, çözülmüş dosya içinde bir byte aralığı ister (HTTP Range). Bu
//! modül o aralığı, aralığı kapsayan segmentlere ve her segmentin çözülmüş
//! verisi içindeki alt-aralığa çevirir.
//!
//! **Temel kural:** Çözülmüş ofsetler YALNIZCA yEnc başlıklarından
//! (`=ypart begin/end`, [`record_part`]) gelir. NZB'deki `bytes` değeri
//! yEnc-KODLU article boyutudur (kodlama/kaçış nedeniyle çözülmüş boyuttan
//! büyüktür) ve ofset hesabında ASLA kullanılmaz — yalnızca indirme planlama
//! ve ilerleme göstergesi içindir.
//!
//! Bir segmentin çözülmüş konumu ancak article çözülünce kesinleşir. Akış
//! şöyledir: [`resolve`] kesin dilim veremezse hangi segmentlerin gerektiğini
//! ([`LocatorError::NeedSegments`]) bildirir; çağıran onları çekip çözer,
//! [`record_part`] ile konumlarını kaydeder ve `resolve`'u yeniden dener.
//! Henüz kaydı olmayan bölgede hangi segmentlerin gerektiği, tek tip parça
//! boyutu (ilk tam parçadan öğrenilen) varsayımıyla TAHMİN edilir; tahminle
//! çekilen her parçanın gerçek `begin/end`'i kaydedilince eşleme kesinleşir.
//!
//! [`record_part`]: SegmentLocator::record_part
//! [`resolve`]: SegmentLocator::resolve

use std::ops::Range;

use thiserror::Error;

use super::nzb::NzbFile;
use super::yenc::YencPart;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum LocatorError {
    #[error("boş byte aralığı")]
    EmptyRange,
    #[error("aralık dosya sınırının dışında (istenen {requested:?}, dosya boyutu {file_size:?})")]
    OutOfBounds {
        requested: Range<u64>,
        file_size: Option<u64>,
    },
    /// Aralığı çözmek için önce bu segmentlerin çekilip [`SegmentLocator::record_part`]
    /// ile kaydedilmesi gerekir (NZB sırasındaki indeksler).
    #[error("önce şu segmentlerin konumu öğrenilmeli: {0:?}")]
    NeedSegments(Vec<usize>),
    #[error("segment indeksi aralık dışında: {0}")]
    BadIndex(usize),
    #[error("kaydedilen parça dosya boyutu ({new}) öncekiyle ({existing}) çelişiyor")]
    FileSizeConflict { existing: u64, new: u64 },
}

/// Bir segmentin çözülmüş dosya içindeki yeri; yEnc `begin/end`'ten gelir.
/// `start` 0 tabanlı, `[start, start+len)` yarı açık aralık.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DecodedSpan {
    pub start: u64,
    pub len: u64,
}

impl DecodedSpan {
    fn end(&self) -> u64 {
        self.start + self.len
    }
}

#[derive(Debug, Clone)]
struct SegmentEntry {
    message_id: String,
    /// NZB'deki kodlu boyut — yalnız planlama/ilerleme; ofset için KULLANILMAZ.
    encoded_bytes: u64,
    /// yEnc'ten öğrenilen çözülmüş konum; öğrenilene dek `None`.
    decoded: Option<DecodedSpan>,
}

/// Verilen byte aralığının tek bir segmentten okunacak parçası.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SegmentSlice {
    /// NZB sırasındaki segment indeksi.
    pub index: usize,
    pub message_id: String,
    /// Segmentin ÇÖZÜLMÜŞ verisi içinde okunacak alt-aralık (0 tabanlı).
    pub within_segment: Range<u64>,
    /// Bu dilimin dosya içindeki mutlak konumu (0 tabanlı).
    pub file_range: Range<u64>,
}

pub struct SegmentLocator {
    segments: Vec<SegmentEntry>,
    /// yEnc `size=`'ten dosyanın tam boyutu; ilk kayıtta öğrenilir.
    file_size: Option<u64>,
    /// İlk tam (son olmayan) parçadan öğrenilen tek tip çözülmüş parça boyutu.
    uniform_part_size: Option<u64>,
}

impl SegmentLocator {
    /// NZB dosyasının segmentlerinden (sıralı) eşleyici kurar.
    pub fn from_nzb_file(file: &NzbFile) -> Self {
        let segments = file
            .segments
            .iter()
            .map(|s| SegmentEntry {
                message_id: s.message_id.clone(),
                encoded_bytes: s.bytes,
                decoded: None,
            })
            .collect();
        SegmentLocator {
            segments,
            file_size: None,
            uniform_part_size: None,
        }
    }

    pub fn segment_count(&self) -> usize {
        self.segments.len()
    }

    /// Dosya boyutu bilinene dek `None`.
    pub fn file_size(&self) -> Option<u64> {
        self.file_size
    }

    pub fn message_id(&self, index: usize) -> Option<&str> {
        self.segments.get(index).map(|s| s.message_id.as_str())
    }

    /// Bir segmentin NZB'deki kodlu (yEnc) boyutu. İndirme planlama ve
    /// ilerleme göstergesi içindir; ofset hesabında KULLANILMAZ.
    pub fn encoded_bytes(&self, index: usize) -> Option<u64> {
        self.segments.get(index).map(|s| s.encoded_bytes)
    }

    /// Tüm segmentlerin kodlu boyut toplamı (indirilecek yaklaşık veri).
    pub fn total_encoded_bytes(&self) -> u64 {
        self.segments.iter().map(|s| s.encoded_bytes).sum()
    }

    /// Bir segment için çözülmüş konumun kaydı var mı?
    pub fn is_located(&self, index: usize) -> bool {
        self.segments
            .get(index)
            .is_some_and(|s| s.decoded.is_some())
    }

    /// Çözülmüş bir article'ın konumunu kaydeder.
    ///
    /// `begin/end` yoksa (nadir, tek parçalı yEnc) parça tüm dosyayı kapsar
    /// kabul edilir: `[0, size)`. Dosya boyutu ilk kayıtta sabitlenir; sonraki
    /// kayıt çelişirse hata döner.
    pub fn record_part(
        &mut self,
        index: usize,
        part: &YencPart,
    ) -> Result<(), LocatorError> {
        if index >= self.segments.len() {
            return Err(LocatorError::BadIndex(index));
        }

        match self.file_size {
            None => self.file_size = Some(part.file_size),
            Some(existing) if existing != part.file_size => {
                return Err(LocatorError::FileSizeConflict {
                    existing,
                    new: part.file_size,
                });
            }
            Some(_) => {}
        }

        let span = match (part.begin, part.end) {
            (Some(begin), Some(end)) => DecodedSpan {
                start: begin - 1, // 1 tabanlı kapsayıcı → 0 tabanlı
                len: end + 1 - begin,
            },
            // begin/end yoksa: tek parça, tüm dosya.
            _ => DecodedSpan {
                start: 0,
                len: part.file_size,
            },
        };
        self.segments[index].decoded = Some(span);

        // Tek tip parça boyutunu öğren: son olmayan bir parçanın uzunluğu.
        // (Son parça kısadır; onu ölçü almayız.)
        if self.uniform_part_size.is_none() {
            if let Some(total) = part.total {
                if let Some(number) = part.part {
                    if total > 1 && number < total {
                        self.uniform_part_size = Some(span.len);
                    }
                }
            }
        }
        Ok(())
    }

    /// Tek tip parça boyutundan bir dosya ofsetinin hangi segmente düştüğünü
    /// TAHMİN eder (kayıt yoksa kullanılır). Boyut henüz bilinmiyorsa `None`.
    pub fn estimate_index(&self, offset: u64) -> Option<usize> {
        let part_size = self.uniform_part_size?;
        if part_size == 0 {
            return None;
        }
        let index = (offset / part_size) as usize;
        (index < self.segments.len()).then_some(index)
    }

    /// Çözülmüş byte aralığını segment dilimlerine çevirir.
    ///
    /// `range` yarı açıktır (`start..end`, `end` hariç). Tüm aralık kayıtlı
    /// segmentlerce kapsanıyorsa dilimler döner; kapsanmayan bölge varsa
    /// [`LocatorError::NeedSegments`] ile önce çekilmesi gereken segment
    /// indeksleri döner.
    pub fn resolve(
        &self,
        range: Range<u64>,
    ) -> Result<Vec<SegmentSlice>, LocatorError> {
        if range.start >= range.end {
            return Err(LocatorError::EmptyRange);
        }
        if let Some(size) = self.file_size {
            if range.end > size {
                return Err(LocatorError::OutOfBounds {
                    requested: range,
                    file_size: self.file_size,
                });
            }
        }

        let mut slices = Vec::new();
        let mut missing = Vec::new();
        let mut cursor = range.start;

        while cursor < range.end {
            match self.located_segment_at(cursor) {
                Some((index, span)) => {
                    let slice_end = span.end().min(range.end);
                    slices.push(SegmentSlice {
                        index,
                        message_id: self.segments[index].message_id.clone(),
                        within_segment: (cursor - span.start)..(slice_end - span.start),
                        file_range: cursor..slice_end,
                    });
                    cursor = slice_end;
                }
                None => {
                    // Kayıt yok: tahminle segment seç, eksik listesine al ve
                    // o segmentin (tahmini) sonuna atla.
                    let index = self.estimate_index(cursor).ok_or_else(|| {
                        // Boyut/parça bilgisi hiç yoksa en azından ilk segmenti
                        // çekmeyi öner; ilk kayıt her şeyi başlatır.
                        LocatorError::NeedSegments(vec![0])
                    })?;
                    if !missing.contains(&index) {
                        missing.push(index);
                    }
                    let part_size = self.uniform_part_size.unwrap_or(1);
                    let next = (index as u64 + 1) * part_size;
                    cursor = next.max(cursor + 1);
                }
            }
        }

        if missing.is_empty() {
            Ok(slices)
        } else {
            Err(LocatorError::NeedSegments(missing))
        }
    }

    /// `offset`'i kapsayan, konumu KAYITLI segmenti bulur (varsa).
    fn located_segment_at(&self, offset: u64) -> Option<(usize, DecodedSpan)> {
        self.segments.iter().enumerate().find_map(|(i, entry)| {
            entry.decoded.and_then(|span| {
                (span.start <= offset && offset < span.end()).then_some((i, span))
            })
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::nzb::{NzbFile, NzbSegment};

    /// Test için sahte yEnc parçası; sadece konum alanları anlamlı.
    fn part(
        file_size: u64,
        part_no: u32,
        total: u32,
        begin: u64,
        end: u64,
    ) -> YencPart {
        YencPart {
            name: "test.mkv".into(),
            file_size,
            part: Some(part_no),
            total: Some(total),
            begin: Some(begin),
            end: Some(end),
            part_crc32: None,
            file_crc32: None,
            data: Vec::new(),
        }
    }

    /// n segmentli, kodlu boyutları çözülmüşten KASITLI olarak farklı bir
    /// NZB dosyası (gerçek dünyadaki gibi: kodlu > çözülmüş).
    fn nzb_file(n: usize) -> NzbFile {
        NzbFile {
            poster: "p".into(),
            date: None,
            subject: "\"test.mkv\"".into(),
            groups: vec![],
            segments: (1..=n)
                .map(|i| NzbSegment {
                    number: i as u32,
                    bytes: 1_082_466, // kodlu; çözülmüş 1_048_576'dan büyük
                    message_id: format!("seg{i}@x"),
                })
                .collect(),
        }
    }

    const PART: u64 = 1_048_576;

    #[test]
    fn kodlu_bytes_degil_yenc_ofseti_kullanilir() {
        // Bu testin çekirdeği: NZB bytes (1_082_466) ile çözülmüş ofsetler
        // (PART=1_048_576) farklı; eşleme yEnc begin/end'i kullanmalı.
        let mut loc = SegmentLocator::from_nzb_file(&nzb_file(3));
        let file_size = 3 * PART;
        loc.record_part(0, &part(file_size, 1, 3, 1, PART)).unwrap();
        loc.record_part(1, &part(file_size, 2, 3, PART + 1, 2 * PART)).unwrap();

        // Segment 1'in (index 1) dosya konumu tam PART..2*PART olmalı —
        // NZB kodlu boyut toplamı (2*1_082_466) DEĞİL.
        let slices = loc.resolve(PART..PART + 10).unwrap();
        assert_eq!(slices.len(), 1);
        assert_eq!(slices[0].index, 1);
        assert_eq!(slices[0].file_range, PART..PART + 10);
        assert_eq!(slices[0].within_segment, 0..10);

        // Kodlu boyut ofsete sızmış olsaydı burası 2_164_932 olurdu.
        assert_ne!(2 * 1_082_466, 2 * PART);
    }

    #[test]
    fn segment_ici_alt_aralik_dogru() {
        let mut loc = SegmentLocator::from_nzb_file(&nzb_file(3));
        loc.record_part(0, &part(3 * PART, 1, 3, 1, PART)).unwrap();
        // Segmentin ortasından bir dilim.
        let slices = loc.resolve(100..500).unwrap();
        assert_eq!(slices.len(), 1);
        assert_eq!(slices[0].within_segment, 100..500);
        assert_eq!(slices[0].file_range, 100..500);
    }

    #[test]
    fn iki_segmente_yayilan_aralik_bolunur() {
        let mut loc = SegmentLocator::from_nzb_file(&nzb_file(3));
        loc.record_part(0, &part(3 * PART, 1, 3, 1, PART)).unwrap();
        loc.record_part(1, &part(3 * PART, 2, 3, PART + 1, 2 * PART)).unwrap();

        // Segment sınırını (PART) aşan aralık iki dilime bölünmeli.
        let slices = loc.resolve((PART - 5)..(PART + 5)).unwrap();
        assert_eq!(slices.len(), 2);

        assert_eq!(slices[0].index, 0);
        assert_eq!(slices[0].within_segment, (PART - 5)..PART);
        assert_eq!(slices[0].file_range, (PART - 5)..PART);

        assert_eq!(slices[1].index, 1);
        assert_eq!(slices[1].within_segment, 0..5);
        assert_eq!(slices[1].file_range, PART..(PART + 5));
    }

    #[test]
    fn eksik_segment_tahminle_bildirilir() {
        let mut loc = SegmentLocator::from_nzb_file(&nzb_file(1448));
        // Sadece ilk parçayı kaydet → uniform_part_size öğrenilir.
        loc.record_part(0, &part(1_518_038_231, 1, 1448, 1, PART)).unwrap();

        // Ortadaki bir ofset istenince, kaydı olmayan segment tahminle
        // bildirilmeli (seek senaryosu).
        let offset = 759_169_025 - 1; // CLI'den gerçek: segment 725 civarı
        let err = loc.resolve(offset..offset + 100).unwrap_err();
        match err {
            LocatorError::NeedSegments(missing) => {
                assert_eq!(missing, vec![offset as usize / PART as usize]);
                assert_eq!(missing, vec![724]); // 0 tabanlı: part 725
            }
            other => panic!("beklenmeyen: {other:?}"),
        }
    }

    #[test]
    fn kayit_sonrasi_ayni_aralik_cozulur() {
        let mut loc = SegmentLocator::from_nzb_file(&nzb_file(1448));
        let file_size = 1_518_038_231;
        loc.record_part(0, &part(file_size, 1, 1448, 1, PART)).unwrap();

        let offset = 724 * PART; // segment 725'in başı
        // Önce eksik.
        assert!(matches!(
            loc.resolve(offset..offset + 100),
            Err(LocatorError::NeedSegments(_))
        ));
        // Segment 725 (index 724) çekilip kaydedilince çözülür.
        loc.record_part(724, &part(file_size, 725, 1448, offset + 1, offset + PART))
            .unwrap();
        let slices = loc.resolve(offset..offset + 100).unwrap();
        assert_eq!(slices.len(), 1);
        assert_eq!(slices[0].index, 724);
        assert_eq!(slices[0].file_range, offset..offset + 100);
        assert_eq!(slices[0].within_segment, 0..100);
    }

    #[test]
    fn hicbir_kayit_yokken_ilk_segment_onerilir() {
        let loc = SegmentLocator::from_nzb_file(&nzb_file(10));
        // Boyut/parça bilgisi yok: en azından segment 0 çekilmeli.
        assert_eq!(
            loc.resolve(0..10),
            Err(LocatorError::NeedSegments(vec![0]))
        );
    }

    #[test]
    fn son_kisa_parca_kaydedilir() {
        let mut loc = SegmentLocator::from_nzb_file(&nzb_file(3));
        let file_size = 2 * PART + 500; // son parça 500 bayt
        loc.record_part(0, &part(file_size, 1, 3, 1, PART)).unwrap();
        loc.record_part(1, &part(file_size, 2, 3, PART + 1, 2 * PART)).unwrap();
        loc.record_part(2, &part(file_size, 3, 3, 2 * PART + 1, 2 * PART + 500))
            .unwrap();

        let slices = loc.resolve((2 * PART)..(2 * PART + 500)).unwrap();
        assert_eq!(slices.len(), 1);
        assert_eq!(slices[0].index, 2);
        assert_eq!(slices[0].within_segment, 0..500);
    }

    #[test]
    fn dosya_disi_aralik_reddedilir() {
        let mut loc = SegmentLocator::from_nzb_file(&nzb_file(2));
        loc.record_part(0, &part(2 * PART, 1, 2, 1, PART)).unwrap();
        assert!(matches!(
            loc.resolve((2 * PART - 5)..(2 * PART + 100)),
            Err(LocatorError::OutOfBounds { .. })
        ));
    }

    #[test]
    fn bos_aralik_reddedilir() {
        let loc = SegmentLocator::from_nzb_file(&nzb_file(2));
        assert_eq!(loc.resolve(5..5), Err(LocatorError::EmptyRange));
    }

    #[test]
    fn kodlu_boyut_planlama_icin_erisilebilir() {
        let loc = SegmentLocator::from_nzb_file(&nzb_file(3));
        assert_eq!(loc.encoded_bytes(0), Some(1_082_466));
        assert_eq!(loc.total_encoded_bytes(), 3 * 1_082_466);
        // Kodlu toplam, çözülmüş dosya boyutundan (3*PART) büyüktür.
        assert!(loc.total_encoded_bytes() > 3 * PART);
    }

    #[test]
    fn celiskili_dosya_boyutu_reddedilir() {
        let mut loc = SegmentLocator::from_nzb_file(&nzb_file(2));
        loc.record_part(0, &part(2 * PART, 1, 2, 1, PART)).unwrap();
        assert!(matches!(
            loc.record_part(1, &part(999, 2, 2, PART + 1, 2 * PART)),
            Err(LocatorError::FileSizeConflict { .. })
        ));
    }
}
