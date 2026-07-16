//! [`RangeSource`] için gerçek uygulama: NZB dosyasını, NNTP havuzu ve
//! segment↔byte-range eşleyicisi üzerinden bir byte akışı gibi sunar.
//!
//! Akış: bir byte aralığı istenince [`SegmentLocator`] o aralığı kapsayan
//! segmentleri belirler; kaydı olmayanlar havuzdan çekilip yEnc çözülür,
//! konumları kaydedilir; sonra dilimler sırayla çıktı akışına yazılır.
//!
//! Çözülmüş veriler sınırlı bir FIFO önbellekte tutulur (seek sırasında
//! komşu isteklerin tekrar çekmesini önler); önbellekten düşen segment
//! yeniden istenirse tekrar çekilir. Bellek, GB'lık dosyalarda bile
//! önbellek kapasitesiyle sınırlı kalır.

use std::collections::{HashMap, VecDeque};
use std::io;
use std::ops::Range;
use std::sync::{Arc, Mutex};

use tokio::io::{AsyncWrite, AsyncWriteExt};

use super::locator::{LocatorError, SegmentLocator};
use super::nntp::{NntpPool, TlsNntpConnector};
use super::nzb::NzbFile;
use super::server::{content_type_for, RangeSource};
use super::yenc;

/// Çözülmüş segment verisi için basit kapasiteli FIFO önbellek.
struct SegmentCache {
    capacity: usize,
    map: HashMap<usize, Arc<Vec<u8>>>,
    order: VecDeque<usize>,
}

impl SegmentCache {
    fn new(capacity: usize) -> Self {
        SegmentCache {
            capacity: capacity.max(1),
            map: HashMap::new(),
            order: VecDeque::new(),
        }
    }

    fn get(&self, index: usize) -> Option<Arc<Vec<u8>>> {
        self.map.get(&index).cloned()
    }

    fn insert(&mut self, index: usize, data: Arc<Vec<u8>>) {
        if self.map.contains_key(&index) {
            return;
        }
        while self.order.len() >= self.capacity {
            if let Some(evicted) = self.order.pop_front() {
                self.map.remove(&evicted);
            } else {
                break;
            }
        }
        self.order.push_back(index);
        self.map.insert(index, data);
    }
}

pub struct NntpByteSource {
    pool: Arc<NntpPool<TlsNntpConnector>>,
    locator: Mutex<SegmentLocator>,
    cache: Mutex<SegmentCache>,
    content_type: &'static str,
    filename: String,
}

impl NntpByteSource {
    /// Varsayılan önbellek kapasitesi (segment sayısı) — ~1 MB'lık parçalarla
    /// birkaç yüz MB'lık kayan pencere.
    pub const DEFAULT_CACHE_SEGMENTS: usize = 256;

    /// Kaynağı kurar ve ilk segmenti çekerek dosya boyutunu (yEnc `size`)
    /// öğrenir; böylece [`RangeSource::total_len`] server başlar başlamaz
    /// hazırdır.
    pub async fn new(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        file: &NzbFile,
    ) -> io::Result<Self> {
        Self::with_cache_capacity(pool, file, Self::DEFAULT_CACHE_SEGMENTS).await
    }

    pub async fn with_cache_capacity(
        pool: Arc<NntpPool<TlsNntpConnector>>,
        file: &NzbFile,
        cache_segments: usize,
    ) -> io::Result<Self> {
        let filename = file.filename().unwrap_or("stream.bin").to_string();
        let content_type = content_type_for(&filename);
        let source = NntpByteSource {
            pool,
            locator: Mutex::new(SegmentLocator::from_nzb_file(file)),
            cache: Mutex::new(SegmentCache::new(cache_segments)),
            content_type,
            filename,
        };
        // Bootstrap: ilk segment → file_size + tek tip parça boyutu.
        source.ensure_located(0).await?;
        if source.file_size().is_none() {
            return Err(io::Error::other(
                "ilk segmentten dosya boyutu öğrenilemedi",
            ));
        }
        Ok(source)
    }

    pub fn file_size(&self) -> Option<u64> {
        self.locator.lock().expect("kilit").file_size()
    }

    pub fn segment_count(&self) -> usize {
        self.locator.lock().expect("kilit").segment_count()
    }

    pub fn filename(&self) -> &str {
        &self.filename
    }

    /// Bir segmenti çeker, yEnc çözer; verisini döndürür. Konumu bilinmiyorsa
    /// eşleyiciye kaydeder, veriyi önbelleğe koyar.
    async fn fetch_segment(&self, index: usize) -> io::Result<Arc<Vec<u8>>> {
        let message_id = {
            let loc = self.locator.lock().expect("kilit");
            loc.message_id(index)
                .ok_or_else(|| io::Error::other(format!("segment {index} yok")))?
                .to_string()
        };

        let mut conn = self
            .pool
            .checkout()
            .await
            .map_err(|e| io::Error::other(e.to_string()))?;
        let body_result = conn.body_by_message_id(&message_id).await;
        let body = match body_result {
            Ok(body) => body,
            Err(err) => {
                conn.discard(); // olası bozuk bağlantıyı havuzdan at
                return Err(io::Error::other(err.to_string()));
            }
        };
        drop(conn); // bağlantı havuza döner

        let part = yenc::decode(&body).map_err(|e| io::Error::other(e.to_string()))?;
        let data = Arc::new(part.data.clone());

        {
            let mut loc = self.locator.lock().expect("kilit");
            if !loc.is_located(index) {
                loc.record_part(index, &part)
                    .map_err(|e| io::Error::other(e.to_string()))?;
            }
        }
        self.cache.lock().expect("kilit").insert(index, Arc::clone(&data));
        Ok(data)
    }

    /// Segmentin konumu eşleyicide kayıtlı olana dek çeker.
    async fn ensure_located(&self, index: usize) -> io::Result<()> {
        if self.locator.lock().expect("kilit").is_located(index) {
            return Ok(());
        }
        self.fetch_segment(index).await?;
        Ok(())
    }

    /// Segmentin çözülmüş verisini önbellekten alır; yoksa yeniden çeker.
    async fn segment_data(&self, index: usize) -> io::Result<Arc<Vec<u8>>> {
        if let Some(data) = self.cache.lock().expect("kilit").get(index) {
            return Ok(data);
        }
        self.fetch_segment(index).await
    }

    /// `offset`'i içeren segmentin indeksini ve çözülmüş dosya aralığını,
    /// gerekiyorsa o segmenti çekerek bulur. Yalnızca bu tek segment için
    /// veri getirir — böylece açık uçlu (`bytes=0-`) isteklerde tüm dosya
    /// önden çekilmez; player okudukça segment segment ilerlenir.
    async fn locate(&self, offset: u64) -> io::Result<(usize, Range<u64>)> {
        loop {
            let outcome = {
                let loc = self.locator.lock().expect("kilit");
                loc.resolve(offset..offset + 1)
            };
            match outcome {
                Ok(slices) => {
                    let index = slices[0].index;
                    let span = self
                        .locator
                        .lock()
                        .expect("kilit")
                        .decoded_span(index)
                        .expect("çözülen segmentin span'i olur");
                    return Ok((index, span));
                }
                Err(LocatorError::NeedSegments(indices)) => {
                    for index in indices {
                        self.ensure_located(index).await?;
                    }
                }
                Err(other) => return Err(io::Error::other(other.to_string())),
            }
        }
    }
}

impl RangeSource for NntpByteSource {
    fn total_len(&self) -> u64 {
        self.file_size().unwrap_or(0)
    }

    fn content_type(&self) -> &str {
        self.content_type
    }

    async fn write_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        // Segment segment, tembel akış: her adımda cursor'ı içeren segmenti
        // bulup yazarız. Player (mpv/media_kit) yeterince okuyup bağlantıyı
        // kapatınca ilk `write_all` `BrokenPipe` döner ve gereksiz çekme durur.
        let mut cursor = range.start;
        while cursor < range.end {
            let (index, span) = self.locate(cursor).await?;
            let seg_end = span.end.min(range.end);
            let data = self.segment_data(index).await?;
            let from = (cursor - span.start) as usize;
            let to = (seg_end - span.start) as usize;
            out.write_all(&data[from..to]).await?;
            cursor = seg_end;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_kapasiteyi_asinca_en_eskiyi_atar() {
        let mut cache = SegmentCache::new(2);
        cache.insert(0, Arc::new(vec![0]));
        cache.insert(1, Arc::new(vec![1]));
        cache.insert(2, Arc::new(vec![2])); // 0 atılmalı
        assert!(cache.get(0).is_none());
        assert!(cache.get(1).is_some());
        assert!(cache.get(2).is_some());
    }

    #[test]
    fn cache_ayni_indeksi_tekrar_eklemez() {
        let mut cache = SegmentCache::new(2);
        cache.insert(5, Arc::new(vec![5]));
        cache.insert(5, Arc::new(vec![9])); // yok sayılır
        assert_eq!(cache.get(5).unwrap().as_slice(), &[5]);
    }
}
