//! Newznab indexer arama API'si (flutter_rust_bridge).
//!
//! Dart, güvenli depodan okuduğu indexer adresini ve API anahtarını verir;
//! Rust caps keşfi, metin araması ve NZB indirme işlerini yürütür. İndirilen
//! NZB geçici dizine yazılır ve yolu döndürülür — oynatma mevcut
//! [`crate::api::streaming`] akışıyla devam eder.
//!
//! Gizlilik kuralı: API anahtarı ve anahtar taşıyan URL'ler yalnızca bellek
//! içinde akar; hiçbir DTO `Debug` türetmez, hata metinleri URL/gövde
//! içermez.

use std::time::Duration;

use crate::engine::http::{self, HttpError};
use crate::engine::newznab::{self, MediaKind};

use super::streaming::RUNTIME;

const SEARCH_TIMEOUT: Duration = Duration::from_secs(20);
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(60);
const MAX_SEARCH_BYTES: usize = 8 * 1024 * 1024;
const MAX_NZB_BYTES: usize = 64 * 1024 * 1024;

/// Dart'tan gelen indexer yapılandırması.
pub struct IndexerConfigDto {
    /// Ör. `https://miatrix.example` (sonunda `/api` olabilir ya da olmayabilir).
    pub base_url: String,
    pub api_key: String,
}

/// `?t=caps` özeti; UI hangi arama türlerinin açık olduğunu buna göre gösterir.
pub struct IndexerCapsDto {
    pub server_title: Option<String>,
    pub search_available: bool,
    pub tv_search_available: bool,
    pub movie_search_available: bool,
}

/// Tek arama sonucu. `nzb_url` API anahtarı içerebilir; loglanmamalıdır.
pub struct SearchItemDto {
    pub title: String,
    pub nzb_url: String,
    pub info_url: Option<String>,
    pub size_bytes: Option<u64>,
    pub published_epoch_secs: Option<i64>,
    /// Rust tarafında hazırlanan görüntü rozetleri: ["2160p","HEVC","DV",…].
    pub badges: Vec<String>,
    /// "movie" | "tv" | "other" — UI simgesi için.
    pub media_kind: String,
    pub season: Option<u32>,
    pub episode: Option<u32>,
    pub year: Option<u32>,
    pub group: Option<String>,
}

pub struct SearchPageDto {
    pub total: Option<u64>,
    pub items: Vec<SearchItemDto>,
}

fn map_http_error(error: HttpError) -> String {
    error.to_string()
}

fn fetch_checked(url: &str, max_bytes: usize, timeout: Duration) -> Result<String, String> {
    RUNTIME.block_on(async {
        let response = http::http_get(url, max_bytes, timeout)
            .await
            .map_err(map_http_error)?;
        if !(200..300).contains(&response.status) {
            return Err(format!("indexer HTTP {} döndürdü", response.status));
        }
        String::from_utf8(response.body)
            .map_err(|_| "indexer yanıtı UTF-8 değil".to_string())
    })
}

/// Indexer'ın yeteneklerini sorgular (`?t=caps`). Bağlantı ve API anahtarı
/// doğrulaması için de kullanılır.
pub fn newznab_check_caps(config: IndexerConfigDto) -> Result<IndexerCapsDto, String> {
    let url = newznab::build_api_url(
        &config.base_url,
        &[("t", "caps"), ("apikey", &config.api_key)],
    );
    let body = fetch_checked(&url, MAX_SEARCH_BYTES, SEARCH_TIMEOUT)?;
    let caps = newznab::parse_caps(&body).map_err(|error| error.to_string())?;
    Ok(IndexerCapsDto {
        server_title: caps.server_title,
        search_available: caps.search.as_ref().is_some_and(|s| s.available),
        tv_search_available: caps.tv_search.as_ref().is_some_and(|s| s.available),
        movie_search_available: caps.movie_search.as_ref().is_some_and(|s| s.available),
    })
}

/// Metin araması yapar (`?t=search&q=…`). Sonuçlar release rozetleriyle
/// birlikte döner; liste sırası indexer'ın sırasıdır.
pub fn newznab_search(
    config: IndexerConfigDto,
    query: String,
    limit: u32,
    offset: u32,
) -> Result<SearchPageDto, String> {
    let limit = limit.clamp(1, 100).to_string();
    let offset = offset.to_string();
    let url = newznab::build_api_url(
        &config.base_url,
        &[
            ("t", "search"),
            ("q", &query),
            ("apikey", &config.api_key),
            ("limit", &limit),
            ("offset", &offset),
        ],
    );
    let body = fetch_checked(&url, MAX_SEARCH_BYTES, SEARCH_TIMEOUT)?;
    let page = newznab::parse_search_response(&body).map_err(|error| error.to_string())?;

    let items = page
        .items
        .into_iter()
        .map(|item| {
            let kind = item.release.media_kind(&item.categories, item.season);
            SearchItemDto {
                title: item.title,
                nzb_url: item.nzb_url,
                info_url: item.info_url,
                size_bytes: item.size_bytes,
                published_epoch_secs: item.published_epoch_secs,
                badges: item.release.badges(),
                media_kind: match kind {
                    MediaKind::Movie => "movie",
                    MediaKind::Tv => "tv",
                    MediaKind::Other => "other",
                }
                .to_string(),
                season: item.season,
                episode: item.episode,
                year: item.release.year,
                group: item.release.group,
            }
        })
        .collect();
    Ok(SearchPageDto {
        total: page.total,
        items,
    })
}

/// Arama sonucunun NZB'sini geçici dizine indirir ve dosya yolunu döndürür.
/// Yanıtın gerçekten NZB olduğu kök öğe kokusuyla doğrulanır; HTML hata
/// sayfaları oynatıcıya kadar ilerleyemez.
pub fn newznab_download_nzb(
    config: IndexerConfigDto,
    nzb_url: String,
    suggested_name: String,
) -> Result<String, String> {
    // Bazı indexer'lar feed'deki bağlantıya anahtarı gömmez.
    let url = if nzb_url.contains("apikey=") || config.api_key.is_empty() {
        nzb_url
    } else {
        let separator = if nzb_url.contains('?') { '&' } else { '?' };
        format!(
            "{nzb_url}{separator}apikey={}",
            newznab::percent_encode(&config.api_key)
        )
    };

    let body = fetch_checked(&url, MAX_NZB_BYTES, DOWNLOAD_TIMEOUT)?;
    let looks_nzb = body
        .get(..4096)
        .is_some_and(|head| head.contains("<nzb") || head.contains("<!DOCTYPE nzb"));
    if !looks_nzb {
        return Err("indirilen içerik NZB değil".to_string());
    }

    let dir = std::env::temp_dir().join("zanzibarr-nzb");
    std::fs::create_dir_all(&dir).map_err(|error| format!("geçici dizin açılamadı: {error}"))?;
    let filename = format!(
        "{}-{}.nzb",
        sanitize_filename(&suggested_name),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    );
    let path = dir.join(filename);
    std::fs::write(&path, body).map_err(|error| format!("NZB yazılamadı: {error}"))?;
    Ok(path.to_string_lossy().into_owned())
}

/// Dosya adını platform-güvenli karakterlere indirger (en çok 60 karakter).
fn sanitize_filename(name: &str) -> String {
    let sanitized: String = name
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || matches!(c, '-' | '_' | '.') {
                c
            } else {
                '_'
            }
        })
        .take(60)
        .collect();
    let sanitized = sanitized.trim_matches(['.', '_']).to_string();
    if sanitized.is_empty() {
        "arama-sonucu".to_string()
    } else {
        sanitized
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dosya_adi_temizligi() {
        assert_eq!(sanitize_filename("Fight.Club.1999-GROUP"), "Fight.Club.1999-GROUP");
        assert_eq!(sanitize_filename("a/b\\c:d*e?f\"g<h>i|j"), "a_b_c_d_e_f_g_h_i_j");
        assert_eq!(sanitize_filename("   "), "arama-sonucu");
        assert_eq!(sanitize_filename("...___"), "arama-sonucu");
        assert_eq!(sanitize_filename(&"x".repeat(200)).len(), 60);
    }
}
