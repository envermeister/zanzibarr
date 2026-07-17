//! Localhost HTTP Range server — media_kit/mpv'nin okuduğu yerel uç.
//!
//! Player, dosyayı `http://127.0.0.1:PORT/...` üzerinden açar ve `Range`
//! istekleriyle rastgele konumları okur (moov atom için baş, sık sık son,
//! seek için orta). Bu modül HTTP/Range katmanını, veri kaynağından
//! ([`RangeSource`]) bağımsız tutar; böylece doğruluğu media_kit ve NNTP
//! değişkenlerinden yalıtık test edilir.
//!
//! Tasarım notları (player uyumu için kritik):
//! - Durum satırı ve başlıklar, gövdeden ÖNCE yazılıp flush edilir; böylece
//!   player ilk `Range` isteğine anında `206` görür ve "bozuk dosya" demez.
//! - `Range` biçimlerinin üçü de desteklenir: `bytes=a-b`, `bytes=a-`,
//!   `bytes=-suffix` (dosya sonu / moov atom).
//! - `Accept-Ranges: bytes` her yanıtta ilan edilir.

use std::io;
use std::ops::Range;
use std::sync::Arc;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinSet;

/// Bir byte aralığını çözüp yazan kaynak. Somut hali NZB+NNTP'dir
/// ([`super::nntp_source::NntpByteSource`]); testlerde bellek içi tampon.
pub trait RangeSource: Send + Sync + 'static {
    /// Dosyanın çözülmüş tam boyutu (bilinmeli — server başlamadan bootstrap).
    fn total_len(&self) -> u64;
    fn content_type(&self) -> &str;
    /// `range`'i (yarı açık) `out`'a yazar. Gerektikçe veri çeker; ilk baytı
    /// yazmadan önce beklemek olağandır (veri Usenet'ten gelir).
    fn write_range<W>(
        &self,
        range: Range<u64>,
        out: &mut W,
    ) -> impl std::future::Future<Output = io::Result<()>> + Send
    where
        W: AsyncWrite + Unpin + Send;
}

/// Yalnız `127.0.0.1` üzerinde dinler (dışarıya açılmaz).
pub async fn bind_local(port: u16) -> io::Result<TcpListener> {
    TcpListener::bind(("127.0.0.1", port)).await
}

/// Kabul döngüsü; her bağlantıyı izlenen ayrı bir görevde işler ve
/// sonsuza dek çalışır.
pub async fn serve<S: RangeSource>(listener: TcpListener, source: Arc<S>) -> io::Result<()> {
    serve_until(listener, source, std::future::pending()).await
}

/// `shutdown` tamamlanana dek bağlantı kabul eder; kapanışta açık HTTP
/// görevlerini iptal edip hepsini drain etmeden dönmez.
///
/// Yalnızca dış server görevini abort etmek, [`JoinSet`]'in child görevlere
/// iptal isteği göndermesini sağlar ama onların future'larının gerçekten
/// düşmesini beklemez. Normal shutdown yolu burada child görevleri join ederek
/// taşıdıkları kaynakların ve bağlantıların dönüşten önce bırakılmasını
/// garanti eder.
pub async fn serve_until<S, F>(listener: TcpListener, source: Arc<S>, shutdown: F) -> io::Result<()>
where
    S: RangeSource,
    F: std::future::Future<Output = ()> + Send,
{
    let mut connections = JoinSet::new();
    let mut shutdown = Box::pin(shutdown);

    let outcome = loop {
        tokio::select! {
            _ = &mut shutdown => break Ok(()),
            accepted = listener.accept() => {
                let (stream, _) = match accepted {
                    Ok(connection) => connection,
                    Err(error) => break Err(error),
                };

                // Önceki isteklerden biten görevlerin sonuçlarını tutmayalım.
                while connections.try_join_next().is_some() {}

                let source = Arc::clone(&source);
                connections.spawn(async move {
                    // Bağlantı hatalarını (player erken kapatması vb.) yut.
                    let _ = handle_connection(stream, source).await;
                });
            }
        }
    };

    connections.abort_all();
    while connections.join_next().await.is_some() {}
    outcome
}

const MAX_HEAD: usize = 16 * 1024;

#[derive(Debug, PartialEq, Eq)]
struct RequestHead {
    method: String,
    target: String,
    range: Option<String>,
}

async fn handle_connection<S: RangeSource>(
    mut stream: TcpStream,
    source: Arc<S>,
) -> io::Result<()> {
    let head_bytes = match read_head(&mut stream).await? {
        Some(bytes) => bytes,
        None => return Ok(()), // boş/erken kapanan bağlantı
    };
    let head = match parse_request_head(&head_bytes) {
        Some(head) => head,
        None => {
            return write_simple(&mut stream, 400, "Bad Request").await;
        }
    };

    let is_head = head.method.eq_ignore_ascii_case("HEAD");
    if !is_head && !head.method.eq_ignore_ascii_case("GET") {
        return write_simple(&mut stream, 405, "Method Not Allowed").await;
    }

    let total = source.total_len();
    let content_type = source.content_type().to_string();

    let outcome = match head.range.as_deref() {
        Some(spec) => resolve_range(spec, total),
        None => RangeOutcome::Full,
    };

    match outcome {
        RangeOutcome::Unsatisfiable => {
            let header = format!(
                "HTTP/1.1 416 Range Not Satisfiable\r\n\
                 Content-Range: bytes */{total}\r\n\
                 Accept-Ranges: bytes\r\n\
                 Content-Length: 0\r\n\
                 Connection: close\r\n\r\n"
            );
            stream.write_all(header.as_bytes()).await?;
            stream.flush().await?;
            Ok(())
        }
        RangeOutcome::Full => {
            let header = format!(
                "HTTP/1.1 200 OK\r\n\
                 Content-Type: {content_type}\r\n\
                 Accept-Ranges: bytes\r\n\
                 Content-Length: {total}\r\n\
                 Connection: close\r\n\r\n"
            );
            stream.write_all(header.as_bytes()).await?;
            stream.flush().await?;
            if !is_head && total > 0 {
                source.write_range(0..total, &mut stream).await?;
            }
            stream.flush().await?;
            Ok(())
        }
        RangeOutcome::Satisfiable(range) => {
            let len = range.end - range.start;
            let last = range.end - 1;
            // Başlıklar gövdeden ÖNCE: player anında 206 görür.
            let header = format!(
                "HTTP/1.1 206 Partial Content\r\n\
                 Content-Type: {content_type}\r\n\
                 Accept-Ranges: bytes\r\n\
                 Content-Range: bytes {}-{}/{}\r\n\
                 Content-Length: {len}\r\n\
                 Connection: close\r\n\r\n",
                range.start, last, total
            );
            stream.write_all(header.as_bytes()).await?;
            stream.flush().await?;
            if !is_head {
                source.write_range(range, &mut stream).await?;
            }
            stream.flush().await?;
            Ok(())
        }
    }
}

async fn write_simple(stream: &mut TcpStream, code: u16, reason: &str) -> io::Result<()> {
    let header = format!(
        "HTTP/1.1 {code} {reason}\r\n\
         Content-Length: 0\r\n\
         Connection: close\r\n\r\n"
    );
    stream.write_all(header.as_bytes()).await?;
    stream.flush().await
}

/// İstek başlığını `\r\n\r\n`'e kadar okur (boyut sınırlı).
async fn read_head<R: AsyncRead + Unpin>(stream: &mut R) -> io::Result<Option<Vec<u8>>> {
    let mut buf = Vec::with_capacity(1024);
    let mut chunk = [0u8; 1024];
    loop {
        let n = stream.read(&mut chunk).await?;
        if n == 0 {
            return Ok(if buf.is_empty() { None } else { Some(buf) });
        }
        buf.extend_from_slice(&chunk[..n]);
        if find_head_end(&buf).is_some() {
            return Ok(Some(buf));
        }
        if buf.len() > MAX_HEAD {
            return Ok(Some(buf)); // parse aşamasında reddedilir
        }
    }
}

fn find_head_end(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n")
}

fn parse_request_head(bytes: &[u8]) -> Option<RequestHead> {
    let end = find_head_end(bytes)?;
    let head = std::str::from_utf8(&bytes[..end]).ok()?;
    let mut lines = head.split("\r\n");

    let request_line = lines.next()?;
    let mut parts = request_line.split_whitespace();
    let method = parts.next()?.to_string();
    let target = parts.next()?.to_string();
    // HTTP sürümü (parts.next()) yok sayılır.

    let mut range = None;
    for line in lines {
        if let Some((key, value)) = line.split_once(':') {
            if key.trim().eq_ignore_ascii_case("range") {
                range = Some(value.trim().to_string());
            }
        }
    }

    Some(RequestHead {
        method,
        target,
        range,
    })
}

#[derive(Debug, PartialEq, Eq)]
enum RangeOutcome {
    /// `Range` yok → tüm dosya, 200.
    Full,
    /// Geçerli aralık → 206.
    Satisfiable(Range<u64>),
    /// Karşılanamaz → 416.
    Unsatisfiable,
}

/// `Range` başlığını çözer. Yalnız tek aralık ve `bytes` birimi desteklenir.
/// Biçimler: `bytes=a-b`, `bytes=a-`, `bytes=-suffix`.
fn resolve_range(spec: &str, total: u64) -> RangeOutcome {
    let spec = spec.trim();
    let Some(set) = spec.strip_prefix("bytes=") else {
        return RangeOutcome::Unsatisfiable;
    };
    // Çoklu aralık (virgül) desteklenmez; ilkini bile almayız (belirsizlik).
    if set.contains(',') {
        return RangeOutcome::Unsatisfiable;
    }
    let Some((start_s, end_s)) = set.split_once('-') else {
        return RangeOutcome::Unsatisfiable;
    };
    let start_s = start_s.trim();
    let end_s = end_s.trim();

    if total == 0 {
        return RangeOutcome::Unsatisfiable;
    }

    match (start_s.is_empty(), end_s.is_empty()) {
        // `bytes=-suffix`: son `suffix` bayt.
        (true, false) => {
            let Ok(suffix) = end_s.parse::<u64>() else {
                return RangeOutcome::Unsatisfiable;
            };
            if suffix == 0 {
                return RangeOutcome::Unsatisfiable;
            }
            let start = total.saturating_sub(suffix);
            RangeOutcome::Satisfiable(start..total)
        }
        // `bytes=start-`: start'tan sona.
        (false, true) => {
            let Ok(start) = start_s.parse::<u64>() else {
                return RangeOutcome::Unsatisfiable;
            };
            if start >= total {
                return RangeOutcome::Unsatisfiable;
            }
            RangeOutcome::Satisfiable(start..total)
        }
        // `bytes=start-end`: kapsayıcı; end dosya sonuna kırpılır.
        (false, false) => {
            let (Ok(start), Ok(end)) = (start_s.parse::<u64>(), end_s.parse::<u64>()) else {
                return RangeOutcome::Unsatisfiable;
            };
            if start > end || start >= total {
                return RangeOutcome::Unsatisfiable;
            }
            let end_exclusive = end.saturating_add(1).min(total);
            RangeOutcome::Satisfiable(start..end_exclusive)
        }
        (true, true) => RangeOutcome::Unsatisfiable,
    }
}

/// Dosya adı uzantısından MIME türü. libmpv içeriği kendisi de probe eder;
/// yine de kapsayıcı/elementary stream için doğru HTTP türünü vermek demuxer
/// seçimini hızlandırır ve istemcinin octet-stream'e bağımlı kalmasını önler.
pub fn content_type_for(name: &str) -> &'static str {
    let ext = name.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
    match ext.as_str() {
        "3gp" => "video/3gpp",
        "3g2" => "video/3gpp2",
        "264" | "avc" | "h264" => "video/h264",
        "265" | "h265" | "hevc" => "video/h265",
        "amv" => "video/x-amv",
        "asf" => "video/x-ms-asf",
        "av1" | "obu" => "video/av1",
        "avi" | "divx" => "video/x-msvideo",
        "bik" | "bk2" => "video/x-bink",
        "dv" => "video/dv",
        "dvr-ms" => "video/x-ms-dvr",
        "f4v" | "m4v" | "mp4" => "video/mp4",
        "flv" => "video/x-flv",
        "gxf" => "application/gxf",
        "h261" => "video/h261",
        "h263" => "video/h263",
        "ivf" => "video/x-ivf",
        "m1v" | "m2v" | "mpeg" | "mpg" | "mpv" | "evo" | "vob" | "vro" => "video/mpeg",
        "m2t" | "m2ts" | "mts" | "tp" | "trp" | "ts" => "video/mp2t",
        "mj2" | "mjp2" => "video/mj2",
        "mjpeg" | "mjpg" => "video/x-motion-jpeg",
        "mk3d" | "mkv" => "video/x-matroska",
        "mov" | "qt" => "video/quicktime",
        "mxf" => "application/mxf",
        "nsv" => "video/x-nsv",
        "nut" => "video/x-nut",
        "ogm" | "ogv" => "video/ogg",
        "rm" | "rmvb" => "application/vnd.rn-realmedia",
        "roq" => "video/x-roq",
        "vc1" => "video/vc1",
        "webm" => "video/webm",
        "wmv" => "video/x-ms-wmv",
        "wtv" => "video/x-ms-wtv",
        "y4m" => "video/x-yuv4mpeg",
        "mp3" => "audio/mpeg",
        "flac" => "audio/flac",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt, BufReader};
    use tokio::sync::{oneshot, Notify};

    // --- Saf birim testleri: Range çözümleme ---

    #[test]
    fn range_bastan_aralik() {
        assert_eq!(
            resolve_range("bytes=0-1023", 10_000),
            RangeOutcome::Satisfiable(0..1024)
        );
    }

    #[test]
    fn range_ortadan_aralik() {
        // Kullanıcının 759M ofseti gibi.
        assert_eq!(
            resolve_range("bytes=759019115-759019178", 1_518_038_231),
            RangeOutcome::Satisfiable(759019115..759019179)
        );
    }

    #[test]
    fn range_acik_uclu() {
        assert_eq!(
            resolve_range("bytes=0-", 10_000),
            RangeOutcome::Satisfiable(0..10_000)
        );
    }

    #[test]
    fn range_suffix_dosya_sonu() {
        // moov atom / dosya sonu: son 500 bayt.
        assert_eq!(
            resolve_range("bytes=-500", 10_000),
            RangeOutcome::Satisfiable(9_500..10_000)
        );
        // suffix dosyadan büyükse tüm dosya.
        assert_eq!(
            resolve_range("bytes=-99999", 10_000),
            RangeOutcome::Satisfiable(0..10_000)
        );
    }

    #[test]
    fn range_end_dosya_sonuna_kirpilir() {
        assert_eq!(
            resolve_range("bytes=9990-999999", 10_000),
            RangeOutcome::Satisfiable(9_990..10_000)
        );
    }

    #[test]
    fn range_u64_max_sonu_tasmadan_dosya_sonuna_kirpilir() {
        assert_eq!(
            resolve_range("bytes=0-18446744073709551615", 10_000),
            RangeOutcome::Satisfiable(0..10_000)
        );
        assert_eq!(
            resolve_range("bytes=18446744073709551614-18446744073709551615", u64::MAX,),
            RangeOutcome::Satisfiable((u64::MAX - 1)..u64::MAX)
        );
    }

    #[test]
    fn range_karsilanamaz_haller() {
        assert_eq!(
            resolve_range("bytes=10000-", 10_000),
            RangeOutcome::Unsatisfiable
        );
        assert_eq!(
            resolve_range("bytes=5000-4000", 10_000),
            RangeOutcome::Unsatisfiable
        );
        assert_eq!(
            resolve_range("bytes=-0", 10_000),
            RangeOutcome::Unsatisfiable
        );
        assert_eq!(
            resolve_range("bytes=0-100,200-300", 10_000),
            RangeOutcome::Unsatisfiable
        );
        assert_eq!(
            resolve_range("items=0-100", 10_000),
            RangeOutcome::Unsatisfiable
        );
    }

    #[test]
    fn istek_basligi_cozumlenir() {
        let raw = b"GET /video.mkv HTTP/1.1\r\nHost: x\r\nRange: bytes=100-200\r\n\r\n";
        let head = parse_request_head(raw).unwrap();
        assert_eq!(head.method, "GET");
        assert_eq!(head.target, "/video.mkv");
        assert_eq!(head.range.as_deref(), Some("bytes=100-200"));
    }

    #[test]
    fn range_siz_istek() {
        let raw = b"GET / HTTP/1.1\r\nHost: x\r\n\r\n";
        let head = parse_request_head(raw).unwrap();
        assert_eq!(head.range, None);
    }

    #[test]
    fn mime_turleri() {
        assert_eq!(content_type_for("film.mkv"), "video/x-matroska");
        assert_eq!(content_type_for("a.MP4"), "video/mp4");
        assert_eq!(content_type_for("telefon.3gp"), "video/3gpp");
        assert_eq!(content_type_for("kamera.m2ts"), "video/mp2t");
        assert_eq!(content_type_for("kurgu.mxf"), "application/mxf");
        assert_eq!(content_type_for("ham.h264"), "video/h264");
        assert_eq!(content_type_for("ham.hevc"), "video/h265");
        assert_eq!(content_type_for("animasyon.av1"), "video/av1");
        assert_eq!(
            content_type_for("eski.rmvb"),
            "application/vnd.rn-realmedia"
        );
        assert_eq!(content_type_for("acik.ogv"), "video/ogg");
        assert_eq!(content_type_for("tv.wtv"), "video/x-ms-wtv");
        assert_eq!(content_type_for("x"), "application/octet-stream");
    }

    #[test]
    fn oynatilabilir_her_video_uzantisinin_acik_mime_eslemesi_var() {
        for extension in crate::engine::nzb::PLAYABLE_VIDEO_EXTENSIONS {
            let filename = format!("video.{extension}");
            assert_ne!(
                content_type_for(&filename),
                "application/octet-stream",
                "{extension} uzantısının MIME eşlemesi yok"
            );
        }
    }

    // --- Uçtan uca: gerçek localhost TCP + bellek içi kaynak (kimliksiz) ---

    struct InMemorySource {
        data: Vec<u8>,
        content_type: String,
    }

    impl RangeSource for InMemorySource {
        fn total_len(&self) -> u64 {
            self.data.len() as u64
        }
        fn content_type(&self) -> &str {
            &self.content_type
        }
        async fn write_range<W>(&self, range: Range<u64>, out: &mut W) -> io::Result<()>
        where
            W: AsyncWrite + Unpin + Send,
        {
            out.write_all(&self.data[range.start as usize..range.end as usize])
                .await
        }
    }

    async fn start_test_server(data: Vec<u8>) -> u16 {
        let source = Arc::new(InMemorySource {
            data,
            content_type: "video/x-matroska".into(),
        });
        let listener = bind_local(0).await.unwrap();
        let port = listener.local_addr().unwrap().port();
        tokio::spawn(async move {
            let _ = serve(listener, source).await;
        });
        port
    }

    /// Ham HTTP isteği atıp (durum satırı, başlıklar, gövde) döndürür.
    async fn request(port: u16, raw: &str) -> (String, Vec<u8>) {
        let mut stream = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        stream.write_all(raw.as_bytes()).await.unwrap();
        stream.flush().await.unwrap();
        let mut reader = BufReader::new(stream);
        let mut buf = Vec::new();
        reader.read_to_end(&mut buf).await.unwrap();
        let split = buf
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .expect("başlık sonu");
        let head = String::from_utf8_lossy(&buf[..split]).to_string();
        let body = buf[split + 4..].to_vec();
        (head, body)
    }

    #[tokio::test]
    async fn bastan_aralik_206_ve_dogru_govde() {
        let data: Vec<u8> = (0..=255u8).cycle().take(10_000).collect();
        let port = start_test_server(data.clone()).await;
        let (head, body) = request(
            port,
            "GET /f.mkv HTTP/1.1\r\nHost: x\r\nRange: bytes=0-1023\r\n\r\n",
        )
        .await;
        assert!(head.starts_with("HTTP/1.1 206 Partial Content"), "{head}");
        assert!(head.contains("Content-Range: bytes 0-1023/10000"));
        assert!(head.contains("Content-Length: 1024"));
        assert!(head.contains("Accept-Ranges: bytes"));
        assert_eq!(body, data[0..1024]);
    }

    #[tokio::test]
    async fn ortadan_aralik_206() {
        let data: Vec<u8> = (0..=255u8).cycle().take(10_000).collect();
        let port = start_test_server(data.clone()).await;
        let (head, body) = request(
            port,
            "GET /f.mkv HTTP/1.1\r\nHost: x\r\nRange: bytes=5000-5099\r\n\r\n",
        )
        .await;
        assert!(head.contains("206 Partial Content"));
        assert!(head.contains("Content-Range: bytes 5000-5099/10000"));
        assert_eq!(body, data[5000..5100]);
    }

    #[tokio::test]
    async fn acik_uclu_tum_dosya_206() {
        let data: Vec<u8> = (0..=255u8).cycle().take(10_000).collect();
        let port = start_test_server(data.clone()).await;
        let (head, body) = request(
            port,
            "GET /f.mkv HTTP/1.1\r\nHost: x\r\nRange: bytes=0-\r\n\r\n",
        )
        .await;
        assert!(head.contains("206 Partial Content"));
        assert!(head.contains("Content-Range: bytes 0-9999/10000"));
        assert_eq!(body, data);
    }

    #[tokio::test]
    async fn suffix_dosya_sonu_206() {
        let data: Vec<u8> = (0..=255u8).cycle().take(10_000).collect();
        let port = start_test_server(data.clone()).await;
        let (head, body) = request(
            port,
            "GET /f.mkv HTTP/1.1\r\nHost: x\r\nRange: bytes=-500\r\n\r\n",
        )
        .await;
        assert!(head.contains("206 Partial Content"));
        assert!(head.contains("Content-Range: bytes 9500-9999/10000"));
        assert_eq!(body, data[9500..10000]);
    }

    #[tokio::test]
    async fn range_siz_istek_200_tum_dosya() {
        let data: Vec<u8> = (0..=255u8).cycle().take(4096).collect();
        let port = start_test_server(data.clone()).await;
        let (head, body) = request(port, "GET /f.mkv HTTP/1.1\r\nHost: x\r\n\r\n").await;
        assert!(head.starts_with("HTTP/1.1 200 OK"));
        assert!(head.contains("Content-Length: 4096"));
        assert!(head.contains("Accept-Ranges: bytes"));
        assert_eq!(body, data);
    }

    #[tokio::test]
    async fn head_istegi_govde_dondurmez() {
        let data: Vec<u8> = (0..=255u8).cycle().take(4096).collect();
        let port = start_test_server(data.clone()).await;
        let (head, body) = request(
            port,
            "HEAD /f.mkv HTTP/1.1\r\nHost: x\r\nRange: bytes=0-1023\r\n\r\n",
        )
        .await;
        assert!(head.contains("206 Partial Content"));
        assert!(head.contains("Content-Length: 1024"));
        assert!(body.is_empty(), "HEAD gövde döndürmemeli");
    }

    #[tokio::test]
    async fn karsilanamaz_range_416() {
        let data: Vec<u8> = vec![0; 1000];
        let port = start_test_server(data).await;
        let (head, _) = request(
            port,
            "GET /f.mkv HTTP/1.1\r\nHost: x\r\nRange: bytes=5000-6000\r\n\r\n",
        )
        .await;
        assert!(head.starts_with("HTTP/1.1 416"));
        assert!(head.contains("Content-Range: bytes */1000"));
    }

    struct BlockingSource {
        entered: Arc<Notify>,
    }

    impl RangeSource for BlockingSource {
        fn total_len(&self) -> u64 {
            1
        }

        fn content_type(&self) -> &str {
            "application/octet-stream"
        }

        async fn write_range<W>(&self, _range: Range<u64>, _out: &mut W) -> io::Result<()>
        where
            W: AsyncWrite + Unpin + Send,
        {
            self.entered.notify_one();
            std::future::pending::<io::Result<()>>().await
        }
    }

    #[tokio::test]
    async fn graceful_shutdown_acik_baglanti_gorevlerini_ve_kaynagi_dusurur() {
        let entered = Arc::new(Notify::new());
        let source = Arc::new(BlockingSource {
            entered: Arc::clone(&entered),
        });
        let weak_source = Arc::downgrade(&source);
        let listener = bind_local(0).await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let server = tokio::spawn(serve_until(listener, source, async move {
            let _ = shutdown_rx.await;
        }));

        let mut client = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        client
            .write_all(b"GET /f HTTP/1.1\r\nHost: x\r\nRange: bytes=0-0\r\n\r\n")
            .await
            .unwrap();
        client.flush().await.unwrap();
        entered.notified().await;

        shutdown_tx.send(()).unwrap();
        server.await.unwrap().unwrap();
        assert!(
            weak_source.upgrade().is_none(),
            "graceful shutdown döndüğünde child GET görevi kaynağı tutmamalı"
        );
    }
}
