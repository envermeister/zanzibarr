//! NNTP istemcisi: TLS (:563), komut/yanıt katmanı, AUTHINFO akışı ve
//! bağlantı havuzu iskeleti.
//!
//! Katmanlar bilinçli olarak ayrık:
//! - [`Response`] ve satır kuralları: saf ayrıştırma, ağsız test edilir.
//! - [`connection::NntpConnection`]: herhangi bir `AsyncRead + AsyncWrite`
//!   üzerinde protokol konuşur; testler tokio `duplex` ile sahte sunucu
//!   kullanır, gerçek bağlantı TLS akışıyla aynı kodu çalıştırır.
//! - [`pool::NntpPool`]: sağlayıcının eşzamanlı bağlantı limitini semaforla
//!   uygular; boşta bağlantıları yeniden kullanır.
//!
//! Kimlik bilgisi hiçbir yerde loglanmaz; hata metinlerine parola girmez.

pub mod connection;
pub mod pool;

pub use connection::{connect_tls, NntpConnection, TlsNntpConnection};
pub use pool::{Connect, NntpPool, PooledConnection, TlsNntpConnector};

use std::fmt;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum NntpError {
    #[error("G/Ç hatası: {0}")]
    Io(#[from] std::io::Error),
    #[error("geçersiz argüman: {0}")]
    InvalidArgument(String),
    #[error("sunucu bağlantıyı kapattı")]
    ConnectionClosed,
    #[error("bozuk sunucu yanıtı: {0}")]
    Malformed(String),
    #[error("beklenmeyen yanıt ({context}): {code} {text}")]
    UnexpectedResponse {
        context: &'static str,
        code: u16,
        text: String,
    },
    #[error("kimlik doğrulama başarısız: {code} {text}")]
    AuthFailed { code: u16, text: String },
    #[error("sağlayıcının eşzamanlı bağlantı sınırına ulaşıldı: {code} {text}")]
    ConnectionLimit { code: u16, text: String },
    #[error("{operation} zaman aşımı")]
    Timeout { operation: &'static str },
    #[error("article bulunamadı")]
    NoSuchArticle,
    #[error("yanıt çok büyük (sınır {limit} bayt)")]
    TooLarge { limit: usize },
}

/// Sağlayıcıların bağlantı kotası için kullandığı metinleri, gerçek kimlik
/// doğrulama hatalarından ayırır. Yalnız durum koduna (özellikle genel amaçlı
/// 502'ye) bakmak yanlış parola/izin hatalarını bağlantı kotası sanabilir;
/// bu nedenle açık bir kota ifadesi de zorunludur.
pub(crate) fn is_connection_limit_response(text: &str) -> bool {
    let text = text.to_ascii_lowercase();
    text.contains("too many connection")
        || text.contains("connection limit")
        || text.contains("maximum connections")
        || text.contains("maximum number of connections")
        || text.contains("max connections")
}

/// Tek satırlık NNTP durum yanıtı, ör. `222 0 <id@host> body`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub code: u16,
    pub text: String,
}

impl Response {
    pub fn parse(line: &str) -> Result<Self, NntpError> {
        let code = line
            .get(0..3)
            .and_then(|s| s.parse::<u16>().ok())
            .filter(|c| (100..=599).contains(c))
            .ok_or_else(|| NntpError::Malformed(format!("durum kodu yok: {line:.80}")))?;
        Ok(Response {
            code,
            text: line[3..].trim().to_string(),
        })
    }
}

/// NNTP sağlayıcı yapılandırması. Parola bellekte düz metin durur ama
/// `Debug` çıktısında asla görünmez.
#[derive(Clone)]
pub struct ProviderConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    /// Sağlayıcının izin verdiği eşzamanlı bağlantı sayısı (havuz boyutu).
    pub max_connections: usize,
}

impl fmt::Debug for ProviderConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ProviderConfig")
            .field("host", &self.host)
            .field("port", &self.port)
            .field("username", &self.username)
            .field("password", &"***")
            .field("max_connections", &self.max_connections)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn yanit_satiri_cozumlenir() {
        let r = Response::parse("200 news.example.com ready").unwrap();
        assert_eq!(r.code, 200);
        assert_eq!(r.text, "news.example.com ready");

        // "381" tek başına: metin kısmı boş ama kod okunur.
        let r = Response::parse("381").unwrap();
        assert_eq!(r.code, 381);
        assert_eq!(r.text, "");
    }

    #[test]
    fn kodsuz_satir_reddedilir() {
        assert!(Response::parse("bozuk").is_err());
        assert!(Response::parse("99").is_err());
        assert!(Response::parse("999 kod araligi disi").is_err());
    }

    #[test]
    fn baglanti_kotasi_metni_izin_hatasindan_ayrilir() {
        assert!(is_connection_limit_response("Too many connections"));
        assert!(is_connection_limit_response(
            "Maximum number of connections reached"
        ));
        assert!(!is_connection_limit_response("Permission denied"));
        assert!(!is_connection_limit_response("Invalid credentials"));
    }

    #[test]
    fn debug_ciktisinda_parola_gorunmez() {
        let config = ProviderConfig {
            host: "news.example.com".into(),
            port: 563,
            username: "alice".into(),
            password: "sahte-parola".into(),
            max_connections: 8,
        };
        let debug = format!("{config:?}");
        assert!(!debug.contains("sahte-parola"));
        assert!(debug.contains("***"));
    }
}
