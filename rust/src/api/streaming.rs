//! Dart'a açılan streaming API'si (flutter_rust_bridge).
//!
//! Dart, güvenli depodan okuduğu sağlayıcı bilgilerini ve bir NZB dosya
//! yolunu verir; Rust bir localhost HTTP Range server ayağa kaldırıp
//! media_kit'in açacağı URL'i döndürür. Ağır iş (NNTP, yEnc, byte-range)
//! tümüyle bu tarafta kalır.
//!
//! Kimlik bilgileri yalnızca çağrı parametresi olarak gelir; Rust bunları
//! diske yazmaz, loglamaz.

use std::sync::Arc;

use once_cell::sync::Lazy;
use tokio::runtime::Runtime;

use crate::engine::nntp::{ProviderConfig, TlsNntpConnector};
use crate::engine::nntp_source::NntpByteSource;
use crate::engine::nzb::{self, NzbFile};
use crate::engine::server::{self, RangeSource};

/// Tüm ağ/stream işleri bu global çok-iş-parçacıklı runtime'da yürür.
/// Server görevleri, başlatan çağrı bitse de burada yaşamaya devam eder.
static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    Runtime::new().expect("tokio runtime kurulamadı")
});

/// Dart'tan gelen sağlayıcı yapılandırması.
pub struct ProviderConfigDto {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub max_connections: u32,
}

impl From<ProviderConfigDto> for ProviderConfig {
    fn from(dto: ProviderConfigDto) -> Self {
        ProviderConfig {
            host: dto.host,
            port: dto.port,
            username: dto.username,
            password: dto.password,
            max_connections: dto.max_connections.max(1) as usize,
        }
    }
}

/// Başlatılan stream'in oynatıcıya verilecek bilgileri.
pub struct StreamInfo {
    /// media_kit'in açacağı localhost URL'i.
    pub url: String,
    /// Çözülmüş dosya boyutu (bayt).
    pub size: u64,
    pub filename: String,
    pub segment_count: u32,
}

/// NZB'nin en büyük dosyası için localhost Range server'ı başlatır ve URL
/// döndürür. Bootstrap (ilk segmentle boyut öğrenme) bu çağrıda tamamlanır;
/// döndükten sonra URL hemen oynatılabilir.
///
/// Bu FRB fonksiyonu ayrı bir worker thread'de çalışır (UI bloklanmaz).
pub fn start_stream(
    config: ProviderConfigDto,
    nzb_path: String,
) -> Result<StreamInfo, String> {
    let xml = std::fs::read_to_string(&nzb_path)
        .map_err(|e| format!("NZB okunamadı: {e}"))?;
    let parsed = nzb::parse_nzb(&xml).map_err(|e| e.to_string())?;
    let file: NzbFile = parsed
        .files
        .iter()
        .max_by_key(|f| f.segments.len())
        .ok_or_else(|| "NZB'de dosya yok".to_string())?
        .clone();

    let pool = TlsNntpConnector::new(config.into()).into_pool();

    RUNTIME.block_on(async move {
        let source = NntpByteSource::new(pool, &file)
            .await
            .map_err(|e| e.to_string())?;
        let size = source.total_len();
        let filename = source.filename().to_string();
        let segment_count = source.segment_count() as u32;

        let listener = server::bind_local(0)
            .await
            .map_err(|e| format!("port bağlanamadı: {e}"))?;
        let port = listener
            .local_addr()
            .map_err(|e| e.to_string())?
            .port();

        // Server görevi runtime'da arka planda yaşar.
        RUNTIME.spawn(server::serve(listener, Arc::new(source)));

        // URL yol kısmı yalnızca gösterim/uzantı içindir; server tek dosya sunar.
        let encoded_name = url_encode_path(&filename);
        Ok(StreamInfo {
            url: format!("http://127.0.0.1:{port}/{encoded_name}"),
            size,
            filename,
            segment_count,
        })
    })
}

/// URL yol bileşeni için minimal yüzde-kodlama (boşluk ve URL-güvensiz
/// karakterler). Dosya adları genelde güvenlidir ama garantiye alırız.
fn url_encode_path(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    for byte in name.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_encode_bosluk_ve_ozel_karakter() {
        assert_eq!(url_encode_path("film.mkv"), "film.mkv");
        assert_eq!(url_encode_path("a b.mkv"), "a%20b.mkv");
        assert_eq!(url_encode_path("x&y.mkv"), "x%26y.mkv");
    }

    #[test]
    fn dto_config_donusumu() {
        let dto = ProviderConfigDto {
            host: "h".into(),
            port: 563,
            username: "u".into(),
            password: "p".into(),
            max_connections: 0, // en az 1'e yükseltilmeli
        };
        let config: ProviderConfig = dto.into();
        assert_eq!(config.max_connections, 1);
        assert_eq!(config.port, 563);
    }
}
