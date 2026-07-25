//! Ardışıl çözüm isteyen arşiv girdilerine (LZMA/LZMA2 gibi) seek
//! edilebilir görünüm kazandıran genel cephe.
//!
//! Sıkıştırılmış akışta gerçek rastgele erişim yoktur: decoder baytları
//! ancak baştan sırayla üretebilir. Bu cephe oynatıcının okuma düzenini
//! (büyük ölçüde ileri sıralı, ara sıra ileri/geri sıçramalı) üç kurala
//! indirger:
//!
//! - **İleri okuma/sıçrama:** decoder mevcut imleçten hedefe kadar
//!   çalıştırılır; aradaki baytlar pencere önbelleğinden geçer, istenen
//!   kısım servis edilir.
//! - **Pencere içi geriye okuma:** son `window_size` bayt RAM'de halka
//!   tamponda tutulur; pencere içi okumalar decoder'a dokunmadan servis
//!   edilir.
//! - **Pencere öncesi geriye sıçrama:** decoder sıfırdan açılır ve hedefe
//!   kadar yeniden çözülür. Pahalıdır ama oynatıcı düzeninde seyrektir.
//!
//! Eşzamanlı HTTP bağlantıları tek decoder'ı bir mutex ile seriler; decoder
//! işi `spawn_blocking` içinde yürür, async runtime tıkanmaz. İptal,
//! decoder'ın okuduğu [`BlockingArchiveReader`] üzerinden yayılır.

use std::io::{self, Read};
use std::ops::Range;
use std::sync::{Arc, Mutex};

use tokio::io::AsyncWrite;
use tokio::io::AsyncWriteExt;

use super::archive::validate_range;

/// Pencere önbelleği varsayılanı. TV kutularını da düşünerek masaüstünde de
/// aynı değer tutulur; geriye seek çoğunlukla birkaç saniyelik geri sar
/// olduğundan 64 MiB pratikte yeterlidir.
pub(crate) const DEFAULT_DECODE_WINDOW: usize = 64 * 1024 * 1024;
/// Decoder'dan tek seferde çekilen parça.
const READ_CHUNK: usize = 1024 * 1024;
/// HTTP yazıcısına tek seferde verilen parça.
const EMIT_CHUNK: u64 = 4 * 1024 * 1024;

/// Decoder fabrikası: her çağrıda akışın BAŞINDAN okuyan taze bir decoder
/// döndürür. Solid arşivlerde önceki dosyaları atlama maliyeti de fabrikanın
/// içindedir; cephe bunu bilmez.
type DecoderFactory = Box<dyn Fn() -> io::Result<Box<dyn Read + Send>> + Send + Sync>;

struct DecodeState {
    decoder: Option<Box<dyn Read + Send>>,
    /// Decoder'ın şu ana kadar ürettiği toplam bayt sayısı (= okuma imleci).
    cursor: u64,
    /// Halka tampon: son üretilen `window_len` bayt.
    window: Vec<u8>,
    /// `window` içindeki en eski baytın halka indeksi.
    oldest: usize,
    window_len: usize,
}

impl DecodeState {
    fn new(window_size: usize) -> Self {
        Self {
            decoder: None,
            cursor: 0,
            window: vec![0u8; window_size],
            oldest: 0,
            window_len: 0,
        }
    }

    /// Pencerenin kapsadığı ilk mutlak ofset.
    fn window_start(&self) -> u64 {
        self.cursor - self.window_len as u64
    }

    /// Üretilen baytları halkaya ekler; taşan en eski baytlar düşer.
    fn push(&mut self, mut data: &[u8]) {
        let size = self.window.len();
        // Veri pencereden büyükse yalnız son kısmı anlamlıdır.
        if data.len() >= size {
            self.oldest = 0;
            self.window.copy_from_slice(&data[data.len() - size..]);
            self.window_len = size;
            return;
        }
        while !data.is_empty() {
            let write_pos = (self.oldest + self.window_len) % size;
            let take = (size - write_pos).min(data.len());
            self.window[write_pos..write_pos + take].copy_from_slice(&data[..take]);
            if self.window_len == size {
                self.oldest = (self.oldest + take) % size;
            } else {
                self.window_len += take;
            }
            data = &data[take..];
        }
    }

    /// `[start, start + buf.len())` aralığını `buf`'a kopyalar. Önkoşul:
    /// aralık pencerede olmalı (`start >= window_start() && start + len <=
    /// cursor`); çağıran bunu Adım 1'e borçludur.
    fn copy_out(&self, start: u64, buf: &mut [u8]) {
        debug_assert!(start >= self.window_start());
        debug_assert!(start + buf.len() as u64 <= self.cursor);
        let size = self.window.len() as u64;
        let first = start - self.window_start();
        for (i, slot) in buf.iter_mut().enumerate() {
            let idx = (self.oldest as u64 + first + i as u64) % size;
            *slot = self.window[idx as usize];
        }
    }
}

fn unexpected_decode_eof(cursor: u64, expected_end: u64) -> io::Error {
    io::Error::new(
        io::ErrorKind::UnexpectedEof,
        format!("decoder {cursor} baytta bitti, {expected_end} bekleniyordu (akış bozuk)"),
    )
}

struct Inner {
    total_len: u64,
    open: DecoderFactory,
    state: Mutex<DecodeState>,
}

impl Inner {
    /// `[start, start + len)` aralığının çözülmüş baytlarını döndürür.
    /// Mutex yalnız bu çağrı boyunca tutulur; `spawn_blocking` içinde
    /// çağrılmalıdır.
    fn read_decoded(&self, start: u64, len: usize) -> io::Result<Vec<u8>> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| io::Error::other("decoder durumu zehirlendi"))?;
        let end = start
            .checked_add(len as u64)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "okuma ofseti taştı"))?;

        // Pencereden düşmüş baytlar decoder'dan geri alınamaz; baştan aç.
        // (Koşul `end`'den bağımsız: tamamı geçmişte kalan bir okuma bile
        // pencereden taşmış olabilir.)
        if start < state.window_start() {
            state.decoder = Some((self.open)()?);
            state.cursor = 0;
            state.window_len = 0;
            state.oldest = 0;
        }

        let mut out = vec![0u8; len];

        // Adım 1: imleç start'ın gerisindeyse (yeni açılış/restart) aradaki
        // baytlar yalnız halkadan geçirilir; parça sınırları start'a kenetli
        // olduğundan imleç tam start'a oturur.
        while state.cursor < start {
            if state.decoder.is_none() {
                state.decoder = Some((self.open)()?);
            }
            let want = (start - state.cursor).min(READ_CHUNK as u64) as usize;
            let mut scratch = vec![0u8; want];
            let read = state
                .decoder
                .as_mut()
                .expect("decoder az önce açıldı")
                .read(&mut scratch)?;
            if read == 0 {
                return Err(unexpected_decode_eof(state.cursor, end));
            }
            state.push(&scratch[..read]);
            state.cursor += read as u64;
        }

        // Adım 2: pencerede hazır duran öneki kopyala (ardışıl okumada tüm
        // aralık buradan gelir, decoder hiç çalışmaz).
        let from_window = (state.cursor.min(end) - start) as usize;
        state.copy_out(start, &mut out[..from_window]);

        // Adım 3: kalanı çöz; üretilen baytlar hem halkaya hem çıktıya gider.
        while state.cursor < end {
            if state.decoder.is_none() {
                state.decoder = Some((self.open)()?);
            }
            let want = (end - state.cursor).min(READ_CHUNK as u64) as usize;
            let mut scratch = vec![0u8; want];
            let read = state
                .decoder
                .as_mut()
                .expect("decoder az önce açıldı")
                .read(&mut scratch)?;
            if read == 0 {
                return Err(unexpected_decode_eof(state.cursor, end));
            }
            state.push(&scratch[..read]);
            let offset = (state.cursor - start) as usize;
            out[offset..offset + read].copy_from_slice(&scratch[..read]);
            state.cursor += read as u64;
        }
        Ok(out)
    }
}

/// [`super::server::RangeSource`] uyumlu, seek edilebilir çözüm cephesi.
pub(crate) struct SeekableDecodeSource {
    inner: Arc<Inner>,
}

impl SeekableDecodeSource {
    pub(crate) fn new(total_len: u64, open: DecoderFactory) -> Self {
        Self::with_window(total_len, DEFAULT_DECODE_WINDOW, open)
    }

    pub(crate) fn with_window(total_len: u64, window_size: usize, open: DecoderFactory) -> Self {
        Self {
            inner: Arc::new(Inner {
                total_len,
                open,
                state: Mutex::new(DecodeState::new(window_size.max(1))),
            }),
        }
    }

    /// Aralığı parça parça çözüp `out`'a yazar.
    pub(crate) async fn write_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
    where
        W: AsyncWrite + Unpin + Send,
    {
        validate_range(range.clone(), self.inner.total_len)?;
        let mut position = range.start;
        while position < range.end {
            let take = (range.end - position).min(EMIT_CHUNK) as usize;
            let inner = Arc::clone(&self.inner);
            let bytes = tokio::task::spawn_blocking(move || inner.read_decoded(position, take))
                .await
                .map_err(|error| io::Error::other(format!("çözüm görevi düştü: {error}")))??;
            out.write_all(&bytes).await?;
            position += take as u64;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Test codec'i: kaynağı XOR 0xFF ile "çözülen" akışa çevirir.
    struct XorReader {
        data: Vec<u8>,
        position: usize,
    }

    impl Read for XorReader {
        fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
            let remaining = self.data.len() - self.position;
            let take = remaining.min(buf.len());
            for (i, byte) in buf[..take].iter_mut().enumerate() {
                *byte = self.data[self.position + i] ^ 0xFF;
            }
            self.position += take;
            Ok(take)
        }
    }

    fn decoded_pattern(raw: &[u8]) -> Vec<u8> {
        raw.iter().map(|b| b ^ 0xFF).collect()
    }

    /// (kaynak, fabrika sayacı) ikilisinden cephe kurar.
    fn source_with_counter(
        raw: Vec<u8>,
        total_len: u64,
        window: usize,
    ) -> (SeekableDecodeSource, Arc<AtomicUsize>) {
        let counter = Arc::new(AtomicUsize::new(0));
        let factory_counter = Arc::clone(&counter);
        let source = SeekableDecodeSource::with_window(
            total_len,
            window,
            Box::new(move || {
                factory_counter.fetch_add(1, Ordering::SeqCst);
                Ok(Box::new(XorReader {
                    data: raw.clone(),
                    position: 0,
                }))
            }),
        );
        (source, counter)
    }

    async fn read_range(source: &SeekableDecodeSource, range: Range<u64>) -> Vec<u8> {
        let mut out = Vec::new();
        source
            .write_range(range, &mut out)
            .await
            .expect("aralık okunabilmeli");
        out
    }

    #[tokio::test]
    async fn sirali_okuma_cozulmus_icerigi_verir() {
        let raw: Vec<u8> = (0..=255u8).cycle().take(10_000).collect();
        let (source, counter) = source_with_counter(raw.clone(), 10_000, 1024);
        let got = read_range(&source, 0..10_000).await;
        assert_eq!(got, decoded_pattern(&raw));
        assert_eq!(counter.load(Ordering::SeqCst), 1, "tek decoder yeterli");
    }

    #[tokio::test]
    async fn ileri_sicrama_yeniden_baslatmaz() {
        let raw: Vec<u8> = (0..=255u8).cycle().take(100_000).collect();
        let (source, counter) = source_with_counter(raw.clone(), 100_000, 1024);
        assert_eq!(
            read_range(&source, 0..16).await,
            decoded_pattern(&raw)[..16]
        );
        assert_eq!(
            read_range(&source, 90_000..90_032).await,
            decoded_pattern(&raw)[90_000..90_032]
        );
        assert_eq!(counter.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn pencere_ici_geri_okuma_decodera_dokunmaz() {
        let raw: Vec<u8> = (0..=255u8).cycle().take(100_000).collect();
        let (source, counter) = source_with_counter(raw.clone(), 100_000, 4096);
        read_range(&source, 0..80_000).await;
        // 78_000, imleç (80_000) - pencere (4096) içinde.
        assert_eq!(
            read_range(&source, 78_000..78_064).await,
            decoded_pattern(&raw)[78_000..78_064]
        );
        assert_eq!(counter.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn pencere_oncesi_geri_sicrama_decoderi_yeniden_acar() {
        let raw: Vec<u8> = (0..=255u8).cycle().take(100_000).collect();
        let (source, counter) = source_with_counter(raw.clone(), 100_000, 1024);
        read_range(&source, 0..90_000).await;
        assert_eq!(
            read_range(&source, 1000..1032).await,
            decoded_pattern(&raw)[1000..1032]
        );
        assert_eq!(counter.load(Ordering::SeqCst), 2, "decoder baştan açılmalı");
        // Yeniden açılıştan sonra akış tutarlı kalır.
        assert_eq!(
            read_range(&source, 95_000..95_016).await,
            decoded_pattern(&raw)[95_000..95_016]
        );
    }

    #[tokio::test]
    async fn pencere_sinirini_asan_okuma() {
        let raw: Vec<u8> = (0..=255u8).cycle().take(50_000).collect();
        let (source, _) = source_with_counter(raw.clone(), 50_000, 2048);
        // Okuma pencerenin iki katı: halka tampon kaymalı yine de doğru vermeli.
        assert_eq!(
            read_range(&source, 10_000..14_096).await,
            decoded_pattern(&raw)[10_000..14_096]
        );
    }

    #[tokio::test]
    async fn kisa_akan_decoder_hata_verir() {
        let raw = vec![7u8; 100];
        let (source, _) = source_with_counter(raw, 10_000, 1024);
        let mut out = Vec::new();
        let result = source.write_range(0..5000, &mut out).await;
        assert!(matches!(
            result,
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof
        ));
    }

    #[tokio::test]
    async fn eszamanli_okumalar_dogru_servis_edilir() {
        let raw: Vec<u8> = (0..=255u8).cycle().take(60_000).collect();
        let expected = decoded_pattern(&raw);
        let (source, _) = source_with_counter(raw, 60_000, 1024);
        let source = Arc::new(source);

        let mut tasks = tokio::task::JoinSet::new();
        for start in [0u64, 5_000, 40_000, 59_000] {
            let source = Arc::clone(&source);
            tasks.spawn(async move {
                let mut out = Vec::new();
                source
                    .write_range(start..start + 512, &mut out)
                    .await
                    .unwrap();
                (start, out)
            });
        }
        while let Some(result) = tasks.join_next().await {
            let (start, out) = result.unwrap();
            assert_eq!(out, expected[start as usize..start as usize + 512]);
        }
    }
}
