//! Minimal HTTP/1.1 GET istemcisi.
//!
//! Indexer API çağrıları (Newznab caps/arama) ve NZB indirme tek atımlık
//! HTTPS GET'lerdir. reqwest gibi yeni bir bağımlılık eklemek yerine mevcut
//! tokio + rustls yığını üzerinde küçük bir istemci tutulur; gzip istenmez
//! (`Accept-Encoding: identity`), her istek yeni bağlantıdır
//! (`Connection: close`).
//!
//! Gizlilik kuralı: URL'ler sorgu kısmında API anahtarı taşıyabilir. Hata
//! türleri URL, yanıt gövdesi veya `Location` başlığı içermez; yalnızca
//! statik bağlam ve durum kodu taşır.

use std::io;
use std::sync::Arc;
use std::time::Duration;

use thiserror::Error;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;
use tokio_rustls::rustls;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::TlsConnector;

const MAX_HEADER_BYTES: usize = 64 * 1024;
const MAX_REDIRECTS: u32 = 5;
const USER_AGENT: &str = "zanzibarr/1.1 (+https://zanzibarr.app)";

#[derive(Debug, Error)]
pub enum HttpError {
    #[error("geçersiz URL: {0}")]
    InvalidUrl(&'static str),
    #[error("ağ hatası: {0}")]
    Io(#[from] io::Error),
    #[error("TLS el sıkışması başarısız: {0}")]
    Tls(String),
    #[error("bozuk HTTP yanıtı: {0}")]
    Malformed(&'static str),
    #[error("yanıt boyutu sınırı aşıldı (sınır {limit} bayt)")]
    TooLarge { limit: usize },
    #[error("çok fazla yönlendirme")]
    TooManyRedirects,
    #[error("istek zaman aşımına uğradı")]
    Timeout,
}

pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl HttpResponse {
    /// Başlık değerini büyük/küçük harf duyarsız arar.
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }
}

/// Ayrıştırılmış URL; `target` yol + sorguyu birlikte taşır.
struct ParsedUrl<'a> {
    https: bool,
    host: &'a str,
    port: u16,
    target: &'a str,
}

fn parse_url(url: &str) -> Result<ParsedUrl<'_>, HttpError> {
    let (https, rest) = if let Some(rest) = url.strip_prefix("https://") {
        (true, rest)
    } else if let Some(rest) = url.strip_prefix("http://") {
        (false, rest)
    } else {
        return Err(HttpError::InvalidUrl("şema http/https olmalı"));
    };
    let (authority, target) = match rest.find('/') {
        Some(idx) => (&rest[..idx], &rest[idx..]),
        None => (rest, "/"),
    };
    // userinfo (user:pass@host) kullanılmaz; varsa atılır.
    let authority = authority.rsplit('@').next().unwrap_or(authority);
    let (host, port) = match authority.rsplit_once(':') {
        Some((host, port)) => {
            let port: u16 = port
                .parse()
                .map_err(|_| HttpError::InvalidUrl("port geçersiz"))?;
            (host, port)
        }
        None => (authority, if https { 443 } else { 80 }),
    };
    if host.is_empty() {
        return Err(HttpError::InvalidUrl("host boş"));
    }
    Ok(ParsedUrl {
        https,
        host,
        port,
        target,
    })
}

/// 3xx `Location` değerini tam URL'ye çözer. Mutlak URL'ler olduğu gibi
/// döner; kök-göreli ve yol-göreli biçimler yönlendiren URL'ye göre kurulur.
fn resolve_redirect(base: &ParsedUrl, location: &str) -> Result<String, HttpError> {
    let location = location.trim();
    if location.is_empty() {
        return Err(HttpError::Malformed("boş Location başlığı"));
    }
    if location.starts_with("http://") || location.starts_with("https://") {
        return Ok(location.to_string());
    }
    let scheme = if base.https { "https" } else { "http" };
    let default_port = if base.https { 443 } else { 80 };
    let port = if base.port == default_port {
        String::new()
    } else {
        format!(":{}", base.port)
    };
    if location.starts_with('/') {
        return Ok(format!("{scheme}://{}{port}{location}", base.host));
    }
    // Yol-göreli: base target'ın sorgusuz dizinine göre.
    let path = base.target.split('?').next().unwrap_or("/");
    let dir = match path.rfind('/') {
        Some(idx) => &path[..=idx],
        None => "/",
    };
    Ok(format!("{scheme}://{}{port}{dir}{location}", base.host))
}

/// Kök sertifikalar `webpki-roots`'tan gelir (platform bağımsız) — NNTP
/// bağlayıcısıyla aynı yaklaşım.
fn tls_connector() -> TlsConnector {
    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let config = rustls::ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    TlsConnector::from(Arc::new(config))
}

/// Verilen URL'ye GET atar; 3xx yönlendirmeleri en çok [`MAX_REDIRECTS`]
/// kez izler. Son yanıtı (2xx/4xx/5xx) olduğu gibi döndürür — durum kodunun
/// yorumu çağırana aittir.
pub async fn http_get(
    url: &str,
    max_bytes: usize,
    timeout: Duration,
) -> Result<HttpResponse, HttpError> {
    match tokio::time::timeout(timeout, http_get_inner(url, max_bytes)).await {
        Ok(result) => result,
        Err(_) => Err(HttpError::Timeout),
    }
}

async fn http_get_inner(url: &str, max_bytes: usize) -> Result<HttpResponse, HttpError> {
    let mut current = url.to_string();
    for _ in 0..=MAX_REDIRECTS {
        let parsed = parse_url(&current)?;
        let default_port = if parsed.https { 443 } else { 80 };
        let host_header = if parsed.port == default_port {
            parsed.host.to_string()
        } else {
            format!("{}:{}", parsed.host, parsed.port)
        };

        let tcp = TcpStream::connect((parsed.host, parsed.port)).await?;
        tcp.set_nodelay(true).ok();
        let response = if parsed.https {
            let server_name = ServerName::try_from(parsed.host.to_string())
                .map_err(|_| HttpError::InvalidUrl("geçersiz sunucu adı"))?;
            let mut tls = tls_connector()
                .connect(server_name, tcp)
                .await
                .map_err(|error| HttpError::Tls(error.to_string()))?;
            exchange(&mut tls, &host_header, parsed.target, max_bytes).await?
        } else {
            let mut plain = tcp;
            exchange(&mut plain, &host_header, parsed.target, max_bytes).await?
        };

        match response.status {
            301 | 302 | 303 | 307 | 308 => {
                let location = response
                    .header("location")
                    .ok_or(HttpError::Malformed("yönlendirmede Location yok"))?;
                current = resolve_redirect(&parsed, location)?;
            }
            _ => return Ok(response),
        }
    }
    Err(HttpError::TooManyRedirects)
}

/// Tek bağlantı üzerinde istek/yanıt turu. TLS'siz akışlarla da
/// çalışabildiği için birim testleri `duplex` ile ağsız yapılır.
async fn exchange<S>(
    stream: &mut S,
    host_header: &str,
    target: &str,
    max_bytes: usize,
) -> Result<HttpResponse, HttpError>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let request = format!(
        "GET {target} HTTP/1.1\r\nHost: {host_header}\r\nUser-Agent: {USER_AGENT}\r\n\
         Accept: */*\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n"
    );
    stream.write_all(request.as_bytes()).await?;
    stream.flush().await?;

    let mut reader = BufReader::new(stream);
    let status_line = read_line(&mut reader, MAX_HEADER_BYTES).await?;
    let status = parse_status_line(&status_line)?;

    let mut headers = Vec::new();
    let mut header_bytes = status_line.len();
    loop {
        let line = read_line(&mut reader, MAX_HEADER_BYTES).await?;
        header_bytes += line.len();
        if header_bytes > MAX_HEADER_BYTES {
            return Err(HttpError::Malformed("başlık bloğu çok uzun"));
        }
        let trimmed = trim_line(&line);
        if trimmed.is_empty() {
            break;
        }
        if let Some((name, value)) = trimmed.split_once(':') {
            headers.push((name.trim().to_string(), value.trim().to_string()));
        }
    }

    let body = read_body(&mut reader, &headers, max_bytes).await?;
    Ok(HttpResponse {
        status,
        headers,
        body,
    })
}

fn parse_status_line(line: &[u8]) -> Result<u16, HttpError> {
    let text = String::from_utf8_lossy(line);
    let mut parts = text.split_whitespace();
    let version = parts.next().unwrap_or_default();
    if !version.starts_with("HTTP/") {
        return Err(HttpError::Malformed("durum satırı HTTP ile başlamıyor"));
    }
    parts
        .next()
        .and_then(|code| code.parse().ok())
        .ok_or(HttpError::Malformed("durum kodu okunamadı"))
}

/// `\n` ile biten satırı (sınır aşımına karşı korumalı) okur; EOF'ta eldeki
/// baytlar döner.
async fn read_line<S>(reader: &mut BufReader<&mut S>, cap: usize) -> Result<Vec<u8>, HttpError>
where
    S: AsyncRead + Unpin,
{
    let mut line = Vec::with_capacity(128);
    let mut byte = [0u8; 1];
    loop {
        if line.len() >= cap {
            return Err(HttpError::Malformed("satır çok uzun"));
        }
        let read = reader.read(&mut byte).await?;
        if read == 0 {
            return Ok(line);
        }
        line.push(byte[0]);
        if byte[0] == b'\n' {
            return Ok(line);
        }
    }
}

fn trim_line(line: &[u8]) -> &str {
    let end = line
        .iter()
        .rposition(|b| !matches!(b, b'\r' | b'\n'))
        .map(|idx| idx + 1)
        .unwrap_or(0);
    std::str::from_utf8(&line[..end]).unwrap_or("")
}

async fn read_body<S>(
    reader: &mut BufReader<&mut S>,
    headers: &[(String, String)],
    max_bytes: usize,
) -> Result<Vec<u8>, HttpError>
where
    S: AsyncRead + Unpin,
{
    let chunked = headers.iter().any(|(name, value)| {
        name.eq_ignore_ascii_case("transfer-encoding")
            && value.to_ascii_lowercase().contains("chunked")
    });
    if chunked {
        return read_chunked(reader, max_bytes).await;
    }

    if let Some((_, value)) = headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("content-length"))
    {
        let len: usize = value
            .trim()
            .parse()
            .map_err(|_| HttpError::Malformed("Content-Length okunamadı"))?;
        if len > max_bytes {
            return Err(HttpError::TooLarge { limit: max_bytes });
        }
        let mut body = vec![0u8; len];
        reader.read_exact(&mut body).await?;
        return Ok(body);
    }

    // Uzunluk yoksa `Connection: close` ile EOF'a kadar oku.
    let mut body = Vec::new();
    let mut chunk = [0u8; 16 * 1024];
    loop {
        let read = reader.read(&mut chunk).await?;
        if read == 0 {
            return Ok(body);
        }
        if body.len() + read > max_bytes {
            return Err(HttpError::TooLarge { limit: max_bytes });
        }
        body.extend_from_slice(&chunk[..read]);
    }
}

async fn read_chunked<S>(
    reader: &mut BufReader<&mut S>,
    max_bytes: usize,
) -> Result<Vec<u8>, HttpError>
where
    S: AsyncRead + Unpin,
{
    let mut body = Vec::new();
    loop {
        let size_line = read_line(reader, 1024).await?;
        let size_text = trim_line(&size_line);
        // "1a4;ext=..." biçiminde chunk uzantıları atılır.
        let size_hex = size_text.split(';').next().unwrap_or_default().trim();
        let size = usize::from_str_radix(size_hex, 16)
            .map_err(|_| HttpError::Malformed("bozuk chunk boyutu"))?;
        if size == 0 {
            // Trailer satırlarını boş satıra kadar atla.
            loop {
                let trailer = read_line(reader, MAX_HEADER_BYTES).await?;
                if trim_line(&trailer).is_empty() {
                    break;
                }
            }
            return Ok(body);
        }
        if body.len() + size > max_bytes {
            return Err(HttpError::TooLarge { limit: max_bytes });
        }
        let start = body.len();
        body.resize(start + size, 0);
        reader.read_exact(&mut body[start..]).await?;
        // Her chunk'ın sonunda CRLF bulunur.
        let mut crlf = [0u8; 2];
        reader.read_exact(&mut crlf).await?;
        if &crlf != b"\r\n" {
            return Err(HttpError::Malformed("chunk sonu CRLF değil"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{duplex, AsyncWriteExt};

    /// Sahte sunucuya isteği okutup beklenen öneki doğrular, yanıtı basar.
    async fn serve_once(
        server: tokio::io::DuplexStream,
        expected_prefix: &'static str,
        response: &'static str,
    ) {
        let mut server = server;
        let mut request = vec![0u8; expected_prefix.len()];
        server.read_exact(&mut request).await.unwrap();
        assert_eq!(
            String::from_utf8_lossy(&request),
            expected_prefix,
            "istemci beklenmeyen istek gönderdi"
        );
        server.write_all(response.as_bytes()).await.unwrap();
        server.shutdown().await.unwrap();
    }

    #[test]
    fn url_ayristirma_temel_durumlar() {
        let parsed = parse_url("https://indexer.example/api?t=search&q=a b").unwrap();
        assert!(parsed.https);
        assert_eq!(parsed.host, "indexer.example");
        assert_eq!(parsed.port, 443);
        assert_eq!(parsed.target, "/api?t=search&q=a b");

        let parsed = parse_url("http://indexer.example:8080/api").unwrap();
        assert!(!parsed.https);
        assert_eq!(parsed.port, 8080);
        assert_eq!(parsed.target, "/api");

        let parsed = parse_url("https://indexer.example").unwrap();
        assert_eq!(parsed.target, "/");

        // userinfo taşıyan URL'de kimlik kısmı atılır.
        let parsed = parse_url("https://user:pass@indexer.example/api").unwrap();
        assert_eq!(parsed.host, "indexer.example");
    }

    #[test]
    fn url_ayristirma_hatalari() {
        assert!(matches!(
            parse_url("ftp://x.example/"),
            Err(HttpError::InvalidUrl(_))
        ));
        assert!(matches!(
            parse_url("https:///api"),
            Err(HttpError::InvalidUrl(_))
        ));
        assert!(matches!(
            parse_url("https://x.example:abc/api"),
            Err(HttpError::InvalidUrl(_))
        ));
    }

    #[test]
    fn yonlendirme_cozumleme() {
        let base = parse_url("https://a.example/api?t=get&id=1").unwrap();
        assert_eq!(
            resolve_redirect(&base, "https://b.example/get/2").unwrap(),
            "https://b.example/get/2"
        );
        assert_eq!(
            resolve_redirect(&base, "/dl/2").unwrap(),
            "https://a.example/dl/2"
        );
        assert_eq!(
            resolve_redirect(&base, "nzb/3").unwrap(),
            "https://a.example/nzb/3"
        );

        let base = parse_url("http://a.example:8080/api?t=1").unwrap();
        assert_eq!(
            resolve_redirect(&base, "/get").unwrap(),
            "http://a.example:8080/get"
        );
    }

    #[tokio::test]
    async fn content_length_ile_yanit() {
        let (mut client, server) = duplex(4096);
        let server_task = tokio::spawn(serve_once(
            server,
            "GET /api?t=search HTTP/1.1\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX-Test: evet\r\n\r\nhello",
        ));
        let response = exchange(&mut client, "idx.example", "/api?t=search", 1024)
            .await
            .unwrap();
        assert_eq!(response.status, 200);
        assert_eq!(response.header("x-test"), Some("evet"));
        assert_eq!(response.body, b"hello");
        server_task.await.unwrap();
    }

    #[tokio::test]
    async fn chunked_govde_ve_trailer() {
        let (mut client, server) = duplex(4096);
        let server_task = tokio::spawn(serve_once(
            server,
            "GET /feed HTTP/1.1\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n\
             5\r\nhello\r\n6;ext=x\r\n world\r\n0\r\nX-Trailer: y\r\n\r\n",
        ));
        let response = exchange(&mut client, "idx.example", "/feed", 1024)
            .await
            .unwrap();
        assert_eq!(response.body, b"hello world");
        server_task.await.unwrap();
    }

    #[tokio::test]
    async fn uzunluk_yoksa_eofa_kadar_okunur() {
        let (mut client, server) = duplex(4096);
        let server_task = tokio::spawn(serve_once(
            server,
            "GET /x HTTP/1.1\r\n",
            "HTTP/1.1 200 OK\r\n\r\nkapanana dek govde",
        ));
        let response = exchange(&mut client, "idx.example", "/x", 1024)
            .await
            .unwrap();
        assert_eq!(response.body, "kapanana dek govde".as_bytes());
        server_task.await.unwrap();
    }

    #[tokio::test]
    async fn boyut_siniri_content_length_ile() {
        let (mut client, server) = duplex(4096);
        let server_task = tokio::spawn(serve_once(
            server,
            "GET /big HTTP/1.1\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 999\r\n\r\n",
        ));
        let result = exchange(&mut client, "idx.example", "/big", 100).await;
        assert!(matches!(result, Err(HttpError::TooLarge { limit: 100 })));
        server_task.await.unwrap();
    }

    #[tokio::test]
    async fn bozuk_durum_satiri_reddedilir() {
        let (mut client, server) = duplex(4096);
        let server_task = tokio::spawn(serve_once(
            server,
            "GET /x HTTP/1.1\r\n",
            "MERHABA bu bir http yaniti degil\r\n\r\n",
        ));
        let result = exchange(&mut client, "idx.example", "/x", 100).await;
        assert!(matches!(result, Err(HttpError::Malformed(_))));
        server_task.await.unwrap();
    }

    /// Yerel geri çevrim üzerinde 301 → 200 zinciri; dış ağ gerektirmez.
    #[tokio::test]
    async fn yonlendirme_zinciri_yerel_sunucuda() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = tokio::spawn(async move {
            // 1. istek: 301 döndür.
            let (mut conn, _) = listener.accept().await.unwrap();
            let mut buf = [0u8; 512];
            let _ = conn.read(&mut buf).await.unwrap();
            conn.write_all(
                b"HTTP/1.1 301 Moved\r\nLocation: /son\r\nContent-Length: 0\r\n\r\n",
            )
            .await
            .unwrap();
            // 2. istek: 200 döndür.
            let (mut conn, _) = listener.accept().await.unwrap();
            let _ = conn.read(&mut buf).await.unwrap();
            conn.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
                .await
                .unwrap();
        });

        let url = format!("http://127.0.0.1:{port}/basla");
        let response = http_get(&url, 1024, Duration::from_secs(5)).await.unwrap();
        assert_eq!(response.status, 200);
        assert_eq!(response.body, b"ok");
        server.await.unwrap();
    }

    #[tokio::test]
    async fn sonsuz_yonlendirme_siniri() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = tokio::spawn(async move {
            loop {
                let Ok((mut conn, _)) = listener.accept().await else {
                    break;
                };
                tokio::spawn(async move {
                    let mut buf = [0u8; 512];
                    let _ = conn.read(&mut buf).await.unwrap();
                    let _ = conn
                        .write_all(
                            b"HTTP/1.1 302 Found\r\nLocation: /tekrar\r\nContent-Length: 0\r\n\r\n",
                        )
                        .await;
                });
            }
        });

        let url = format!("http://127.0.0.1:{port}/basla");
        let result = http_get(&url, 1024, Duration::from_secs(10)).await;
        assert!(matches!(result, Err(HttpError::TooManyRedirects)));
        server.abort();
    }
}
