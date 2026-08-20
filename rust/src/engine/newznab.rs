//! Newznab indexer protokolü: caps keşfi, arama yanıtı (RSS) ayrıştırma,
//! sahne release adı çözümleme ve çapraz-indexer tekilleştirme.
//!
//! Bu modül tamamen ağsızdır; HTTP taşıyıcısı [`crate::engine::http`]'dir.
//! Böylece tüm ayrıştırma mantığı fixture XML'lerle birim test edilir.
//!
//! Gizlilik kuralı: API anahtarı yalnızca URL kurulurken parametre olarak
//! geçer; hiçbir hata türü veya `Debug` çıktısı anahtar taşımaz.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum NewznabError {
    #[error("could not parse XML: {0}")]
    Xml(#[from] quick_xml::Error),
    #[error("malformed indexer response: {0}")]
    Malformed(&'static str),
    #[error("indexer API error {code}: {description}")]
    Api { code: u32, description: String },
}

// ---------------------------------------------------------------------------
// Caps keşfi (?t=caps)
// ---------------------------------------------------------------------------

/// Bir arama ucunun yetenek bildirimi (`<search .../>` öğeleri).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchSupport {
    pub available: bool,
    pub supported_params: Vec<String>,
}

/// `?t=caps` yanıtının ilgilendiğimiz özeti.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct IndexerCaps {
    pub server_title: Option<String>,
    /// Genel metin araması (`t=search`).
    pub search: Option<SearchSupport>,
    /// Dizi araması (`t=tvsearch`; bazı indexer'lar `tv-search` yazar).
    pub tv_search: Option<SearchSupport>,
    /// Film araması (`t=movie`).
    pub movie_search: Option<SearchSupport>,
}

impl IndexerCaps {
    /// Uygulamanın kullandığı temel metin araması yapılabiliyor mu?
    pub fn supports_text_search(&self) -> bool {
        self.search.as_ref().is_some_and(|s| s.available)
    }
}

pub fn parse_caps(xml: &str) -> Result<IndexerCaps, NewznabError> {
    use quick_xml::events::Event;

    if let Some((code, description)) = parse_error_xml(xml)? {
        return Err(NewznabError::Api { code, description });
    }

    let mut reader = quick_xml::Reader::from_str(xml);
    let mut caps = IndexerCaps::default();
    let mut saw_caps = false;

    loop {
        match reader.read_event().map_err(NewznabError::Xml)? {
            Event::Start(e) | Event::Empty(e) => {
                match e.local_name().as_ref() {
                    b"caps" => saw_caps = true,
                    b"server" if caps.server_title.is_none() => {
                        caps.server_title = attr_value(&e, b"title")?;
                    }
                    name @ (b"search" | b"tvsearch" | b"tv-search" | b"movie" | b"movie-search") => {
                        let support = SearchSupport {
                            available: attr_value(&e, b"available")?
                                .is_some_and(|v| v.eq_ignore_ascii_case("yes")),
                            supported_params: attr_value(&e, b"supportedparams")?
                                .map(|v| {
                                    v.split(',')
                                        .map(|p| p.trim().to_string())
                                        .filter(|p| !p.is_empty())
                                        .collect()
                                })
                                .unwrap_or_default(),
                        };
                        let slot = match name {
                            b"search" => &mut caps.search,
                            b"tvsearch" | b"tv-search" => &mut caps.tv_search,
                            _ => &mut caps.movie_search,
                        };
                        // İki yazım da gelirse ilkini koru.
                        if slot.is_none() {
                            *slot = Some(support);
                        }
                    }
                    _ => {}
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }

    if !saw_caps {
        return Err(NewznabError::Malformed("no <caps> root element"));
    }
    Ok(caps)
}

/// Newznab hata belgesi (`<error code="100" description="..."/>`) varsa
/// kodu ve kırpılmış açıklamayı döndürür. Açıklamalar indexer'ın sabit
/// metinleridir; yine de 160 karakterle sınırlanır.
pub fn parse_error_xml(xml: &str) -> Result<Option<(u32, String)>, NewznabError> {
    use quick_xml::events::Event;

    let mut reader = quick_xml::Reader::from_str(xml);
    loop {
        match reader.read_event().map_err(NewznabError::Xml)? {
            Event::Start(e) | Event::Empty(e) => {
                if e.local_name().as_ref() == b"error" {
                    let code = attr_value(&e, b"code")?
                        .and_then(|v| v.trim().parse().ok())
                        .unwrap_or(0);
                    let mut description =
                        attr_value(&e, b"description")?.unwrap_or_else(|| "bilinmeyen hata".into());
                    description.truncate(160);
                    return Ok(Some((code, description)));
                }
            }
            Event::Eof => return Ok(None),
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// Arama yanıtı (RSS)
// ---------------------------------------------------------------------------

/// Tek bir arama sonucu. `nzb_url` API anahtarını içerebilir; bu yüzden bu
/// tür bilinçli olarak `Debug` türetmez.
pub struct SearchItem {
    pub title: String,
    /// NZB indirme adresi (`enclosure url`, yoksa `link`).
    pub nzb_url: String,
    /// Detay sayfası (`guid` permalink).
    pub info_url: Option<String>,
    pub size_bytes: Option<u64>,
    pub published_epoch_secs: Option<i64>,
    pub categories: Vec<u32>,
    pub imdb_id: Option<String>,
    pub season: Option<u32>,
    pub episode: Option<u32>,
    /// Başlıktan çözümlenen release bilgisi.
    pub release: ReleaseInfo,
}

pub struct SearchPage {
    pub total: Option<u64>,
    pub offset: u64,
    pub items: Vec<SearchItem>,
}

pub fn parse_search_response(xml: &str) -> Result<SearchPage, NewznabError> {
    use quick_xml::events::Event;

    if let Some((code, description)) = parse_error_xml(xml)? {
        return Err(NewznabError::Api { code, description });
    }

    #[derive(Default)]
    struct ItemBuilder {
        title: String,
        link: Option<String>,
        guid: Option<String>,
        enclosure_url: Option<String>,
        enclosure_len: Option<u64>,
        published: Option<i64>,
        categories: Vec<u32>,
        imdb_id: Option<String>,
        season: Option<u32>,
        episode: Option<u32>,
        size: Option<u64>,
    }

    let mut reader = quick_xml::Reader::from_str(xml);
    let mut page = SearchPage {
        total: None,
        offset: 0,
        items: Vec::new(),
    };
    let mut saw_rss = false;
    let mut in_item = false;
    let mut current: Option<ItemBuilder> = None;
    let mut element = String::new();
    let mut text = String::new();

    loop {
        match reader.read_event().map_err(NewznabError::Xml)? {
            Event::Start(e) => {
                text.clear();
                match e.local_name().as_ref() {
                    b"rss" => saw_rss = true,
                    b"item" => {
                        in_item = true;
                        current = Some(ItemBuilder::default());
                    }
                    b"response" if !in_item => {
                        // <newznab:response offset="0" total="123"/>
                        page.total = attr_value(&e, b"total")?.and_then(|v| v.trim().parse().ok());
                        page.offset = attr_value(&e, b"offset")?
                            .and_then(|v| v.trim().parse().ok())
                            .unwrap_or(0);
                    }
                    // Öğe adları büyük/küçük harf karışık gelebilir (pubDate
                    // gibi); karşılaştırma küçük harf üzerinden yapılır.
                    name => element = String::from_utf8_lossy(name).to_ascii_lowercase(),
                }
            }
            Event::Empty(e) => {
                // <newznab:response offset="0" total="123"/> item dışındadır.
                if !in_item && e.local_name().as_ref() == b"response" {
                    page.total = attr_value(&e, b"total")?.and_then(|v| v.trim().parse().ok());
                    page.offset = attr_value(&e, b"offset")?
                        .and_then(|v| v.trim().parse().ok())
                        .unwrap_or(0);
                }
                if in_item {
                    match e.local_name().as_ref() {
                        b"enclosure" => {
                            if let Some(url) = attr_value(&e, b"url")? {
                                current.as_mut().expect("item durumu").enclosure_url = Some(url);
                            }
                            if let Some(len) =
                                attr_value(&e, b"length")?.and_then(|v| v.trim().parse().ok())
                            {
                                current.as_mut().expect("item durumu").enclosure_len = Some(len);
                            }
                        }
                        b"attr" => {
                            // <newznab:attr name="size" value="..."/>
                            let name = attr_value(&e, b"name")?.unwrap_or_default();
                            let value = attr_value(&e, b"value")?.unwrap_or_default();
                            let item = current.as_mut().expect("item durumu");
                            match name.as_str() {
                                "size" => item.size = value.trim().parse().ok(),
                                "category" => {
                                    if let Ok(cat) = value.trim().parse::<u32>() {
                                        item.categories.push(cat);
                                    }
                                }
                                "imdb" | "imdbid" => {
                                    item.imdb_id = Some(
                                        value.trim().trim_start_matches("tt").to_string(),
                                    );
                                }
                                "season" => {
                                    item.season = parse_leading_number(&value);
                                }
                                "episode" => {
                                    item.episode = parse_leading_number(&value);
                                }
                                _ => {}
                            }
                        }
                        _ => {}
                    }
                }
            }
            Event::Text(t) => {
                let piece = t
                    .xml10_content()
                    .map_err(|_| NewznabError::Malformed("malformed text content"))?;
                text.push_str(&piece);
            }
            Event::CData(c) => {
                text.push_str(&String::from_utf8_lossy(&c));
            }
            Event::End(e) => {
                match e.local_name().as_ref() {
                    b"item" => {
                        in_item = false;
                        if let Some(item) = current.take() {
                            let nzb_url = item.enclosure_url.or(item.link.clone());
                            if let Some(nzb_url) = nzb_url {
                                let release = ReleaseInfo::parse(&item.title);
                                page.items.push(SearchItem {
                                    title: item.title.trim().to_string(),
                                    nzb_url,
                                    info_url: item.guid.or(item.link),
                                    size_bytes: item.size.or(item.enclosure_len),
                                    published_epoch_secs: item.published,
                                    categories: item.categories,
                                    imdb_id: item.imdb_id,
                                    season: item.season.or(release.season),
                                    episode: item.episode.or(release.episode),
                                    release,
                                });
                            }
                        }
                    }
                    _ if in_item => {
                        let value = text.trim();
                        let item = current.as_mut().expect("item durumu");
                        match element.as_str() {
                            "title" => item.title = value.to_string(),
                            "link" => item.link = Some(value.to_string()),
                            "guid" => item.guid = Some(value.to_string()),
                            "pubdate" => item.published = parse_rfc2822_date(value),
                            "category" => {
                                if let Ok(cat) = value.parse::<u32>() {
                                    item.categories.push(cat);
                                }
                            }
                            _ => {}
                        }
                    }
                    _ => {}
                }
                text.clear();
            }
            Event::Eof => break,
            _ => {}
        }
    }

    if !saw_rss {
        return Err(NewznabError::Malformed("no <rss> root element"));
    }
    Ok(page)
}

/// `"S01"`, `"E3"`, `"7"` gibi değerlerin başındaki sayıyı çeker.
fn parse_leading_number(value: &str) -> Option<u32> {
    let digits: String = value
        .trim()
        .trim_start_matches(['S', 's', 'E', 'e'])
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    digits.parse().ok()
}

/// Öznitelik değerini yerel ada göre bulur (namespace önekinden bağımsız);
/// anahtarlar büyük/küçük harf duyarsız eşleşir.
fn attr_value(
    e: &quick_xml::events::BytesStart<'_>,
    name: &[u8],
) -> Result<Option<String>, NewznabError> {
    for attr in e.attributes() {
        let attr = attr.map_err(|_| NewznabError::Malformed("malformed attribute"))?;
        if attr.key.local_name().as_ref().eq_ignore_ascii_case(name) {
            let value = attr
                .normalized_value(quick_xml::XmlVersion::Implicit1_0)
                .map_err(|_| NewznabError::Malformed("malformed attribute value"))?;
            return Ok(Some(value.into_owned()));
        }
    }
    Ok(None)
}

// ---------------------------------------------------------------------------
// Sahne release adı çözümleme
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Resolution {
    Uhd2160,
    Fhd1080,
    Hd720,
    Sd,
}

impl Resolution {
    pub fn badge(self) -> &'static str {
        match self {
            Resolution::Uhd2160 => "2160p",
            Resolution::Fhd1080 => "1080p",
            Resolution::Hd720 => "720p",
            Resolution::Sd => "SD",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    BluRay,
    Remux,
    WebDl,
    WebRip,
    Hdtv,
    DvdRip,
}

impl Source {
    pub fn badge(self) -> &'static str {
        match self {
            Source::BluRay => "BluRay",
            Source::Remux => "Remux",
            Source::WebDl => "WEB-DL",
            Source::WebRip => "WEBRip",
            Source::Hdtv => "HDTV",
            Source::DvdRip => "DVDRip",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VideoCodec {
    X264,
    Hevc,
    Av1,
    Vc1,
    Vp9,
    Mpeg2,
    Mpeg4,
}

impl VideoCodec {
    pub fn badge(self) -> &'static str {
        match self {
            VideoCodec::X264 => "x264",
            VideoCodec::Hevc => "HEVC",
            VideoCodec::Av1 => "AV1",
            VideoCodec::Vc1 => "VC-1",
            VideoCodec::Vp9 => "VP9",
            VideoCodec::Mpeg2 => "MPEG2",
            VideoCodec::Mpeg4 => "XviD",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HdrFormat {
    Hdr,
    Hdr10,
    Hdr10Plus,
    DolbyVision,
    Hlg,
}

impl HdrFormat {
    pub fn badge(self) -> &'static str {
        match self {
            HdrFormat::Hdr => "HDR",
            HdrFormat::Hdr10 => "HDR10",
            HdrFormat::Hdr10Plus => "HDR10+",
            HdrFormat::DolbyVision => "DV",
            HdrFormat::Hlg => "HLG",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioCodec {
    Atmos,
    TrueHd,
    DtsHdMa,
    Dts,
    Ddp,
    Dd,
    Aac,
    Flac,
    Lpcm,
    Opus,
    Mp3,
}

impl AudioCodec {
    pub fn badge(self) -> &'static str {
        match self {
            AudioCodec::Atmos => "Atmos",
            AudioCodec::TrueHd => "TrueHD",
            AudioCodec::DtsHdMa => "DTS-HD MA",
            AudioCodec::Dts => "DTS",
            AudioCodec::Ddp => "DD+",
            AudioCodec::Dd => "DD",
            AudioCodec::Aac => "AAC",
            AudioCodec::Flac => "FLAC",
            AudioCodec::Lpcm => "LPCM",
            AudioCodec::Opus => "Opus",
            AudioCodec::Mp3 => "MP3",
        }
    }
}

/// Arama sonucunun medya türü (UI simgesi için).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaKind {
    Movie,
    Tv,
    Other,
}

/// Başlıktan çözümlenen release etiketleri. Tüm alanlar isteğe bağlıdır;
/// çözümlenemeyen etiketler sessizce atlanır.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ReleaseInfo {
    pub resolution: Option<Resolution>,
    pub source: Option<Source>,
    pub video_codec: Option<VideoCodec>,
    pub hdr: Vec<HdrFormat>,
    /// Codec + isteğe bağlı kanal düzeni ("5.1" gibi).
    pub audio: Vec<(AudioCodec, Option<String>)>,
    pub season: Option<u32>,
    pub episode: Option<u32>,
    pub year: Option<u32>,
    pub group: Option<String>,
    pub proper: bool,
    pub repack: bool,
}

impl ReleaseInfo {
    pub fn parse(title: &str) -> ReleaseInfo {
        let mut info = ReleaseInfo {
            group: extract_group(title),
            ..ReleaseInfo::default()
        };
        let tokens = tokenize(title);
        let mut i = 0;
        while i < tokens.len() {
            let upper = tokens[i].to_ascii_uppercase();
            let token = upper.as_str();

            if let Some((season, episode)) = parse_season_episode(token) {
                info.season.get_or_insert(season);
                if let Some(ep) = episode {
                    info.episode.get_or_insert(ep);
                }
                i += 1;
                continue;
            }

            match token {
                "PROPER" => info.proper = true,
                "REPACK" | "RERIP" => info.repack = true,
                "2160P" | "4K" | "UHD" => {
                    info.resolution.get_or_insert(Resolution::Uhd2160);
                }
                "1080P" | "1080I" | "FHD" => {
                    info.resolution.get_or_insert(Resolution::Fhd1080);
                }
                "720P" | "HD" => {
                    info.resolution.get_or_insert(Resolution::Hd720);
                }
                "480P" | "576P" | "SD" => {
                    info.resolution.get_or_insert(Resolution::Sd);
                }
                "X264" | "H264" | "AVC" => {
                    info.video_codec.get_or_insert(VideoCodec::X264);
                }
                "X265" | "H265" | "HEVC" => {
                    info.video_codec.get_or_insert(VideoCodec::Hevc);
                }
                "AV1" => {
                    info.video_codec.get_or_insert(VideoCodec::Av1);
                }
                "VC1" => {
                    info.video_codec.get_or_insert(VideoCodec::Vc1);
                }
                "VP9" => {
                    info.video_codec.get_or_insert(VideoCodec::Vp9);
                }
                "MPEG2" | "MPEG-2" => {
                    info.video_codec.get_or_insert(VideoCodec::Mpeg2);
                }
                "XVID" | "DIVX" => {
                    info.video_codec.get_or_insert(VideoCodec::Mpeg4);
                }
                // Remux, BluRay'den önce gelmezse bile baskındır:
                // "BluRay.Remux" kaynağı BluRay olan bir remux'tur.
                "REMUX" => info.source = Some(Source::Remux),
                "BLURAY" | "BLU" | "BDRIP" | "BRRIP" | "BD25" | "BD50" => {
                    info.source.get_or_insert(Source::BluRay);
                }
                "WEBDL" => {
                    info.source.get_or_insert(Source::WebDl);
                }
                "WEBRIP" => {
                    info.source.get_or_insert(Source::WebRip);
                }
                "WEB" => {
                    // "WEB-DL"/"WEB-RIP" ayraçla bölündüğünde iki token olur.
                    let next = tokens.get(i + 1).map(|t| t.to_ascii_uppercase());
                    match next.as_deref() {
                        Some("DL") => {
                            info.source.get_or_insert(Source::WebDl);
                            i += 1;
                        }
                        Some("RIP") => {
                            info.source.get_or_insert(Source::WebRip);
                            i += 1;
                        }
                        _ => {
                            info.source.get_or_insert(Source::WebDl);
                        }
                    }
                }
                "HDTV" | "PDTV" => {
                    info.source.get_or_insert(Source::Hdtv);
                }
                "DVDRIP" | "DVDSCR" => {
                    info.source.get_or_insert(Source::DvdRip);
                }
                "HDR" => push_unique(&mut info.hdr, HdrFormat::Hdr),
                "HDR10" => push_unique(&mut info.hdr, HdrFormat::Hdr10),
                "HDR10+" | "HDR10PLUS" => push_unique(&mut info.hdr, HdrFormat::Hdr10Plus),
                "HLG" => push_unique(&mut info.hdr, HdrFormat::Hlg),
                "DV" | "DOVI" => push_unique(&mut info.hdr, HdrFormat::DolbyVision),
                "DOLBY" => {
                    if tokens
                        .get(i + 1)
                        .is_some_and(|t| t.eq_ignore_ascii_case("vision"))
                    {
                        push_unique(&mut info.hdr, HdrFormat::DolbyVision);
                        i += 1;
                    }
                }
                _ => {
                    if info.year.is_none() && is_year(token) {
                        info.year = token.parse().ok();
                    } else if let Some((codec, consumed)) = parse_audio(&tokens, i) {
                        push_audio(&mut info.audio, codec);
                        i += consumed;
                    }
                }
            }
            i += 1;
        }
        info
    }

    /// UI'da doğrudan gösterilecek rozet dizisi (sıralı).
    pub fn badges(&self) -> Vec<String> {
        let mut badges = Vec::new();
        if let Some(resolution) = self.resolution {
            badges.push(resolution.badge().to_string());
        }
        if let Some(source) = self.source {
            badges.push(source.badge().to_string());
        }
        if let Some(codec) = self.video_codec {
            badges.push(codec.badge().to_string());
        }
        for format in &self.hdr {
            badges.push(format.badge().to_string());
        }
        for (codec, channels) in &self.audio {
            match channels {
                Some(channels) => badges.push(format!("{} {channels}", codec.badge())),
                None => badges.push(codec.badge().to_string()),
            }
        }
        if self.proper {
            badges.push("PROPER".to_string());
        }
        if self.repack {
            badges.push("REPACK".to_string());
        }
        badges
    }

    pub fn media_kind(&self, categories: &[u32], season: Option<u32>) -> MediaKind {
        if season.is_some() || categories.iter().any(|c| (5000..6000).contains(c)) {
            return MediaKind::Tv;
        }
        if categories.iter().any(|c| (2000..3000).contains(c)) {
            return MediaKind::Movie;
        }
        MediaKind::Other
    }
}

/// Başlığı sınıflandırılabilir token'lara böler. `+` token'da kalır
/// (HDR10+, DD+), diğer tüm ayraçlar böler.
fn tokenize(title: &str) -> Vec<String> {
    title
        .split(|c: char| {
            matches!(
                c,
                ' ' | '.' | '_' | '-' | '[' | ']' | '(' | ')' | '{' | '}' | '"' | ','
            )
        })
        .filter(|token| !token.is_empty())
        .map(str::to_string)
        .collect()
}

/// `S01E02`, `S01`, `1x02` kalıplarını yakalar.
fn parse_season_episode(token: &str) -> Option<(u32, Option<u32>)> {
    let bytes = token.as_bytes();
    if bytes.len() >= 3 && bytes[0] == b'S' {
        let season_digits: String = bytes[1..]
            .iter()
            .take_while(|b| b.is_ascii_digit())
            .map(|b| *b as char)
            .collect();
        if season_digits.is_empty() {
            return None;
        }
        let season: u32 = season_digits.parse().ok()?;
        let rest = &token[1 + season_digits.len()..];
        if rest.is_empty() {
            return Some((season, None));
        }
        let episode_digits = rest.strip_prefix('E')?;
        if !episode_digits.is_empty() && episode_digits.bytes().all(|b| b.is_ascii_digit()) {
            return Some((season, Some(episode_digits.parse().ok()?)));
        }
        return None;
    }
    // "1x02" biçimi (Rust 2021'de let-chain yok; iç içe if ile).
    if let Some((left, right)) = token.split_once(['x', 'X']) {
        let plausible = !left.is_empty()
            && left.len() <= 2
            && right.len() == 2
            && left.bytes().all(|b| b.is_ascii_digit())
            && right.bytes().all(|b| b.is_ascii_digit());
        if plausible {
            return Some((left.parse().ok()?, Some(right.parse().ok()?)));
        }
    }
    None
}

/// Sondaki tek rakamı ayırır: `"DDP5"` → `("DDP", Some('5'))`.
fn split_trailing_digit(token: &str) -> (&str, Option<char>) {
    let mut chars = token.chars();
    match chars.next_back() {
        Some(last) if last.is_ascii_digit() => (chars.as_str(), Some(last)),
        _ => (token, None),
    }
}

/// Ses codec'i token'ını (kanal bilgisiyle birlikte) çözer. Dönüşteki ikinci
/// değer, kanal rakamları için tüketilen ek token sayısıdır.
fn parse_audio(tokens: &[String], index: usize) -> Option<((AudioCodec, Option<String>), usize)> {
    let upper = tokens[index].to_ascii_uppercase();
    let token = upper.as_str();

    // Rakamla biten özel durumlar önce exact-match ister: AC3, EAC3, EC3.
    let (base, first_digit) = match token {
        "AC3" => return Some(((AudioCodec::Dd, None), 0)),
        "EAC3" | "EC3" | "DD+" => return Some(((AudioCodec::Ddp, None), 0)),
        _ => split_trailing_digit(token),
    };

    let mut consumed = 0;
    let codec = match base {
        "ATMOS" => AudioCodec::Atmos,
        "TRUEHD" => AudioCodec::TrueHd,
        "DTSHD" => AudioCodec::DtsHdMa,
        "DTS" => {
            // "DTS-HD(.MA)" ayraçla bölündüğünde iki/üç token olur.
            if tokens
                .get(index + 1)
                .is_some_and(|t| t.eq_ignore_ascii_case("hd"))
            {
                consumed += 1;
                if tokens
                    .get(index + 2)
                    .is_some_and(|t| t.eq_ignore_ascii_case("ma"))
                {
                    consumed += 1;
                }
                AudioCodec::DtsHdMa
            } else {
                AudioCodec::Dts
            }
        }
        "DDP" => AudioCodec::Ddp,
        "DD" => AudioCodec::Dd,
        "AAC" => AudioCodec::Aac,
        "FLAC" => AudioCodec::Flac,
        "LPCM" | "PCM" => AudioCodec::Lpcm,
        "OPUS" => AudioCodec::Opus,
        "MP3" => AudioCodec::Mp3,
        _ => return None,
    };

    // Kanal düzeni: codec'in hemen ardından gelen "7","1" çifti veya
    // "DDP5" biçiminde codec'e bitişik ilk rakam.
    let next = |offset: usize| tokens.get(index + consumed + offset);
    let single_digit = |token: &String| {
        (token.len() == 1 && token.bytes().next().is_some_and(|b| b.is_ascii_digit()))
            .then(|| token.clone())
    };
    let channels = if let Some(first) = first_digit {
        match next(1).and_then(single_digit) {
            Some(second) => {
                consumed += 1;
                Some(format!("{first}.{second}"))
            }
            None => Some(format!("{first}.0")),
        }
    } else {
        match (next(1).and_then(single_digit), next(2).and_then(single_digit)) {
            (Some(first), Some(second)) => {
                consumed += 2;
                Some(format!("{first}.{second}"))
            }
            _ => None,
        }
    };
    Some(((codec, channels), consumed))
}

fn push_unique<T: PartialEq>(list: &mut Vec<T>, value: T) {
    if !list.contains(&value) {
        list.push(value);
    }
}

fn push_audio(list: &mut Vec<(AudioCodec, Option<String>)>, value: (AudioCodec, Option<String>)) {
    if !list.iter().any(|(codec, _)| *codec == value.0) {
        list.push(value);
    }
}

fn is_year(token: &str) -> bool {
    token.len() == 4
        && token.bytes().all(|b| b.is_ascii_digit())
        && ("1900"..="2099").contains(&token)
}

/// `-GRUP` sonekini ham başlıktan çeker. Ayraçlarla bölünmeden önce
/// uygulanır; güvenli tarafta kalmak için katı ölçütler kullanır.
fn extract_group(title: &str) -> Option<String> {
    let trimmed = title.trim().trim_matches('"');
    let idx = trimmed.rfind('-')?;
    let candidate = trimmed[idx + 1..].trim();
    let plausible = !candidate.is_empty()
        && candidate.len() <= 20
        && !candidate.contains(' ')
        && candidate.chars().any(|c| c.is_alphabetic())
        && !candidate.to_ascii_lowercase().ends_with(".nzb");
    plausible.then(|| candidate.to_string())
}

// ---------------------------------------------------------------------------
// Sorgu URL'si kurulumu
// ---------------------------------------------------------------------------

/// Indexer API URL'si kurar. `base_url` sonunda `/api` yoksa eklenir;
/// parametre değerleri yüzde-kodlanır (API anahtarı da bu sorguda geçer —
/// dönen URL hiçbir zaman loglanmamalıdır).
pub fn build_api_url(base_url: &str, params: &[(&str, &str)]) -> String {
    let base = base_url.trim().trim_end_matches('/');
    let mut url = if base.to_ascii_lowercase().ends_with("/api") {
        base.to_string()
    } else {
        format!("{base}/api")
    };
    let mut separator = '?';
    for (name, value) in params {
        url.push(separator);
        separator = '&';
        url.push_str(name);
        url.push('=');
        url.push_str(&percent_encode(value));
    }
    url
}

/// RFC 3986 unreserved karakterler dışındaki her baytı yüzde-kodlar.
pub fn percent_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Tekilleştirme
// ---------------------------------------------------------------------------

/// Aynı release'in farklı indexer kopyalarını eler: normalize başlık eşit ve
/// boyutlar %1 tolerans içindeyse (veya ikisi de bilinmiyorsa) ilk kayıt
/// tutulur. Sıra korunur.
pub fn dedup_items(items: Vec<SearchItem>) -> Vec<SearchItem> {
    let mut kept: Vec<SearchItem> = Vec::with_capacity(items.len());
    for item in items {
        let title_key = normalize_title(&item.title);
        let duplicate = kept.iter().any(|existing| {
            normalize_title(&existing.title) == title_key
                && sizes_match(existing.size_bytes, item.size_bytes)
        });
        if !duplicate {
            kept.push(item);
        }
    }
    kept
}

fn normalize_title(title: &str) -> String {
    title
        .chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(|c| c.to_lowercase())
        .collect()
}

fn sizes_match(a: Option<u64>, b: Option<u64>) -> bool {
    match (a, b) {
        (Some(a), Some(b)) => {
            let (lo, hi) = if a <= b { (a, b) } else { (b, a) };
            hi - lo <= hi / 100
        }
        (None, None) => true,
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// RFC 2822 tarih → epoch
// ---------------------------------------------------------------------------

/// `"Sat, 01 Jun 2024 12:34:56 +0200"` biçimini epoch saniyesine çevirir.
/// Hafta günü yok sayılır; `GMT`/`UT`/`Z` ve sayısal ofsetler desteklenir.
pub fn parse_rfc2822_date(raw: &str) -> Option<i64> {
    let text = raw.trim();
    let text = match text.find(',') {
        Some(idx) => text[idx + 1..].trim(),
        None => text,
    };
    let mut parts = text.split_whitespace();
    let day: i64 = parts.next()?.parse().ok()?;
    let month = match parts.next()?.get(..3)?.to_ascii_lowercase().as_str() {
        "jan" => 1,
        "feb" => 2,
        "mar" => 3,
        "apr" => 4,
        "may" => 5,
        "jun" => 6,
        "jul" => 7,
        "aug" => 8,
        "sep" => 9,
        "oct" => 10,
        "nov" => 11,
        "dec" => 12,
        _ => return None,
    };
    let year: i64 = parts.next()?.parse().ok()?;
    let time = parts.next()?;
    let mut hms = time.split(':');
    let hour: i64 = hms.next()?.parse().ok()?;
    let minute: i64 = hms.next()?.parse().ok()?;
    let second: i64 = hms.next().unwrap_or("0").parse().ok()?;

    let zone = parts.next().unwrap_or("+0000");
    let offset_secs: i64 = match zone {
        "GMT" | "UT" | "UTC" | "Z" => 0,
        _ if zone.len() == 5 => {
            let sign: i64 = if zone.starts_with('-') { -1 } else { 1 };
            let hours: i64 = zone.get(1..3)?.parse().ok()?;
            let minutes: i64 = zone.get(3..5)?.parse().ok()?;
            sign * (hours * 3600 + minutes * 60)
        }
        _ => 0,
    };

    let days = days_from_civil(year, month, day);
    Some(days * 86_400 + hour * 3600 + minute * 60 + second - offset_secs)
}

/// Howard Hinnant'ın days-from-civil algoritması (1970-01-01 = 0).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let yoe = year - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- caps ---------------------------------------------------------------

    const CAPS_FIXTURE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<caps>
  <server appversion="1.0" title="Miatrix" url="https://miatrix.example/"/>
  <limits max="500" default="100"/>
  <searching>
    <search available="yes" supportedParams="q"/>
    <tv-search available="yes" supportedParams="q,rid,tvdbid,season,ep"/>
    <movie-search available="yes" supportedParams="q,imdbid,tmdbid"/>
    <audio available="no" supportedParams="q"/>
  </searching>
</caps>"#;

    #[test]
    fn caps_temel_ayristirma() {
        let caps = parse_caps(CAPS_FIXTURE).unwrap();
        assert_eq!(caps.server_title.as_deref(), Some("Miatrix"));
        assert!(caps.supports_text_search());
        let tv = caps.tv_search.expect("tv-search support");
        assert!(tv.available);
        assert!(tv.supported_params.contains(&"tvdbid".to_string()));
        let movie = caps.movie_search.expect("movie support");
        assert!(movie.supported_params.contains(&"imdbid".to_string()));
    }

    #[test]
    fn caps_tvsearch_yazimi_ve_kok_eksikligi() {
        let xml = r#"<caps><searching><search available="no" supportedParams=""/>
            <tvsearch available="yes" supportedParams="q,season,ep"/></searching></caps>"#;
        let caps = parse_caps(xml).unwrap();
        assert!(!caps.supports_text_search());
        assert!(caps.tv_search.unwrap().available);

        assert!(matches!(
            parse_caps("<html><body>nope</body></html>"),
            Err(NewznabError::Malformed(_))
        ));
    }

    #[test]
    fn hata_belgesi_yakalanir() {
        let xml = r#"<?xml version="1.0"?><error code="100" description="Invalid API key"/>"#;
        let (code, description) = parse_error_xml(xml).unwrap().expect("hata bekleniyor");
        assert_eq!(code, 100);
        assert_eq!(description, "Invalid API key");
        assert!(matches!(
            parse_caps(xml),
            Err(NewznabError::Api { code: 100, .. })
        ));
    }

    // -- RSS arama yanıtı ----------------------------------------------------

    const SEARCH_FIXTURE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:newznab="http://www.newznab.com/DTD/2010/feeds/attributes/">
  <channel>
    <title>Miatrix</title>
    <newznab:response offset="0" total="2"/>
    <item>
      <title>Fight.Club.1999.UHD.BluRay.2160p.DDP.5.1.DV.HDR10.x265-hallowed</title>
      <guid isPermaLink="true">https://idx.example/details/fc1999</guid>
      <link>https://idx.example/api?t=get&amp;id=fc1999&amp;apikey=SECRET</link>
      <pubDate>Sat, 01 Jun 2024 12:34:56 +0200</pubDate>
      <category>2040</category>
      <enclosure url="https://idx.example/api?t=get&amp;id=fc1999" length="1610612736" type="application/x-nzb"/>
      <newznab:attr name="category" value="2000"/>
      <newznab:attr name="size" value="1500000000"/>
      <newznab:attr name="imdb" value="0137523"/>
    </item>
    <item>
      <title>Some.Show.S01E02.1080p.WEB-DL.DDP5.1.Atmos-GRP</title>
      <link>https://idx.example/api?t=get&amp;id=ss0102</link>
      <pubDate>02 Jun 2024 08:00:00 GMT</pubDate>
      <category>5030</category>
      <newznab:attr name="season" value="S01"/>
      <newznab:attr name="episode" value="E02"/>
    </item>
    <item>
      <title>Bos.Baslik.Olmayan-GROUP</title>
    </item>
  </channel>
</rss>"#;

    #[test]
    fn arama_yaniti_ayristirma() {
        let page = parse_search_response(SEARCH_FIXTURE).unwrap();
        assert_eq!(page.total, Some(2));
        // Üçüncü item'da link/enclosure yok: elenir.
        assert_eq!(page.items.len(), 2);

        let first = &page.items[0];
        assert_eq!(first.size_bytes, Some(1_500_000_000));
        assert_eq!(first.imdb_id.as_deref(), Some("0137523"));
        assert_eq!(first.info_url.as_deref(), Some("https://idx.example/details/fc1999"));
        // &amp; entity'si çözülmüş olmalı.
        assert!(first.nzb_url.contains("t=get&id=fc1999"));
        assert!(first.categories.contains(&2000) && first.categories.contains(&2040));
        // 12:34:56 +0200 → 10:34:56 UTC
        let expected = parse_rfc2822_date("Sat, 01 Jun 2024 12:34:56 +0200");
        assert_eq!(first.published_epoch_secs, expected);

        let second = &page.items[1];
        assert_eq!(second.season, Some(1));
        assert_eq!(second.episode, Some(2));
        assert_eq!(
            second.release.media_kind(&second.categories, second.season),
            MediaKind::Tv
        );
    }

    #[test]
    fn arama_yaniti_hata_belgesi() {
        let xml = r#"<error code="202" description="No such function"/>"#;
        assert!(matches!(
            parse_search_response(xml),
            Err(NewznabError::Api { code: 202, .. })
        ));
    }

    // -- Release ayrıştırıcı --------------------------------------------------

    #[test]
    fn release_gercek_ornekler() {
        let info = ReleaseInfo::parse(
            "Fight.Club.1999.UHD.BluRay.2160p.DDP.5.1.DV.HDR10.x265-hallowed",
        );
        assert_eq!(info.resolution, Some(Resolution::Uhd2160));
        assert_eq!(info.source, Some(Source::BluRay));
        assert_eq!(info.video_codec, Some(VideoCodec::Hevc));
        assert_eq!(
            info.hdr,
            vec![HdrFormat::DolbyVision, HdrFormat::Hdr10]
        );
        assert_eq!(
            info.audio,
            vec![(AudioCodec::Ddp, Some("5.1".to_string()))]
        );
        assert_eq!(info.year, Some(1999));
        assert_eq!(info.group.as_deref(), Some("hallowed"));

        let info = ReleaseInfo::parse("Heartstopper.Forever.2026.DV.2160p.WEB.h265-ETHEL");
        assert_eq!(info.source, Some(Source::WebDl));
        assert_eq!(info.hdr, vec![HdrFormat::DolbyVision]);
        assert_eq!(info.group.as_deref(), Some("ETHEL"));

        let info = ReleaseInfo::parse(
            "Coming.to.America.1988.2160p.UHD.BluRay.Remux.HDR.DV.HEVC.DTS-HD.MA.5.1-PmP",
        );
        assert_eq!(info.source, Some(Source::Remux));
        assert!(info.hdr.contains(&HdrFormat::Hdr));
        assert!(info.hdr.contains(&HdrFormat::DolbyVision));
        assert_eq!(
            info.audio,
            vec![(AudioCodec::DtsHdMa, Some("5.1".to_string()))]
        );

        let info = ReleaseInfo::parse("Some.Show.S01E02.1080p.WEB-DL.DDP5.1.Atmos-GRP");
        assert_eq!(info.season, Some(1));
        assert_eq!(info.episode, Some(2));
        assert_eq!(info.source, Some(Source::WebDl));
        assert!(info.audio.contains(&(AudioCodec::Ddp, Some("5.1".to_string()))));
        assert!(info.audio.contains(&(AudioCodec::Atmos, None)));

        let info = ReleaseInfo::parse("Old.Movie.1956.480p.DVDRip.XviD");
        assert_eq!(info.resolution, Some(Resolution::Sd));
        assert_eq!(info.source, Some(Source::DvdRip));
        assert_eq!(info.video_codec, Some(VideoCodec::Mpeg4));
        assert_eq!(info.year, Some(1956));
        assert_eq!(info.group, None);
    }

    #[test]
    fn release_kanal_ve_bicim_koseleri() {
        let info = ReleaseInfo::parse("Movie.2024.1080p.BluRay.REMUX.AVC.HDR10+.TrueHD.7.1-GRP");
        assert_eq!(info.video_codec, Some(VideoCodec::X264));
        assert_eq!(info.hdr, vec![HdrFormat::Hdr10Plus]);
        assert_eq!(
            info.audio,
            vec![(AudioCodec::TrueHd, Some("7.1".to_string()))]
        );

        // "1x03" biçimi ve PROPER/REPACK bayrakları.
        let info = ReleaseInfo::parse("Show.Name.1x03.PROPER.720p.HDTV.x264-GRP");
        assert_eq!(info.season, Some(1));
        assert_eq!(info.episode, Some(3));
        assert!(info.proper);
        assert_eq!(info.source, Some(Source::Hdtv));

        // Dolby Vision iki token ile.
        let info = ReleaseInfo::parse("Movie.2024.2160p.Dolby.Vision.WEB-DL.HLG-GRP");
        assert!(info.hdr.contains(&HdrFormat::DolbyVision));
        assert!(info.hdr.contains(&HdrFormat::Hlg));

        // 2160 yıl sanılmasın; AC3 codec'e karışmasın.
        let info = ReleaseInfo::parse("Movie.2160p.WEB-DL.AC3-GRP");
        assert_eq!(info.year, None);
        assert_eq!(info.audio, vec![(AudioCodec::Dd, None)]);
    }

    #[test]
    fn release_rozet_siralamasi() {
        let info = ReleaseInfo::parse("Movie.2024.2160p.BluRay.HEVC.DV.HDR10.TrueHD.7.1-GRP");
        assert_eq!(
            info.badges(),
            vec!["2160p", "BluRay", "HEVC", "DV", "HDR10", "TrueHD 7.1"]
        );
    }

    // -- URL kurulumu ----------------------------------------------------------

    #[test]
    fn api_url_kurulumu() {
        assert_eq!(
            build_api_url("https://idx.example/", &[("t", "search"), ("q", "a b&c")]),
            "https://idx.example/api?t=search&q=a%20b%26c"
        );
        assert_eq!(
            build_api_url("https://idx.example/api", &[("t", "caps")]),
            "https://idx.example/api?t=caps"
        );
        assert_eq!(
            build_api_url("https://idx.example/base/", &[("t", "search")]),
            "https://idx.example/base/api?t=search"
        );
    }

    #[test]
    fn yuzde_kodlama() {
        assert_eq!(percent_encode("abc-._~"), "abc-._~");
        assert_eq!(percent_encode("a b"), "a%20b");
        assert_eq!(percent_encode("çğü"), "%C3%A7%C4%9F%C3%BC");
        assert_eq!(percent_encode("100%"), "100%25");
    }

    // -- Tekilleştirme ----------------------------------------------------------

    fn item(title: &str, size: Option<u64>) -> SearchItem {
        SearchItem {
            title: title.to_string(),
            nzb_url: "https://idx.example/get/x".to_string(),
            info_url: None,
            size_bytes: size,
            published_epoch_secs: None,
            categories: Vec::new(),
            imdb_id: None,
            season: None,
            episode: None,
            release: ReleaseInfo::parse(title),
        }
    }

    #[test]
    fn tekillestirme() {
        let items = vec![
            item("Movie.2024.2160p.WEB-DL-GRP", Some(1000)),
            item("movie.2024.2160p.web.dl-grp", Some(1005)), // aynı, %1 içinde
            item("Movie.2024.2160p.WEB-DL-GRP", Some(2000)), // farklı boyut: kalır
            item("Other.2024.1080p-XYZ", None),
            item("Other.2024.1080p-XYZ", None), // ikisi de boyutsuz: elenir
        ];
        let kept = dedup_items(items);
        assert_eq!(kept.len(), 3);
        assert_eq!(kept[0].size_bytes, Some(1000));
        assert_eq!(kept[1].size_bytes, Some(2000));
    }

    // -- Tarih ------------------------------------------------------------------

    #[test]
    fn tarih_ayristirma() {
        assert_eq!(parse_rfc2822_date("Sat, 01 Jan 2000 00:00:00 +0000"), Some(946_684_800));
        assert_eq!(parse_rfc2822_date("Thu, 01 Jan 1970 00:00:00 GMT"), Some(0));
        // +0200 ofset UTC'den 2 saat çıkarır.
        assert_eq!(parse_rfc2822_date("01 Jan 2000 02:00:00 +0200"), Some(946_684_800));
        // -0530: yerel saat UTC-5:30 → UTC = 11:00.
        assert_eq!(parse_rfc2822_date("Sat, 01 Jan 2000 05:30:00 -0530"), Some(946_724_400));
        assert_eq!(parse_rfc2822_date("not a date"), None);
        assert_eq!(parse_rfc2822_date("32 Foo 9999 99:99:99 +0000"), None);
    }
}
