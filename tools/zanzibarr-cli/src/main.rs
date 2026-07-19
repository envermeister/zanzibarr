//! Zanzibarr geçici geliştirme aracı (Xcode kurulup uygulama çalışana dek).
//!
//! Kimlik bilgileri yalnızca OS Keychain'de durur:
//! - Parola echo'suz gizli prompt ile alınır (`rpassword`), asla komut satırı
//!   argümanı olmaz, hiçbir dosyaya/log'a yazılmaz.
//! - Keychain'e `keyring` üzerinden doğrudan API ile yazılır (alt süreç yok,
//!   parola argv/env'de görünmez).
//!
//! Not: Uygulama çalışır hale gelince kimlik bilgileri uygulamanın ayar
//! ekranından (flutter_secure_storage) yeniden girilecek; bu araç geçicidir.

use std::env;
use std::io::{self, Read, Write};
use std::net::TcpStream;
use std::process::ExitCode;
use std::time::Duration;

use std::collections::HashMap;
use std::ops::Range;

use std::sync::Arc;

use rust_lib_zanzibarr::api::streaming::{start_stream, ProviderConfigDto};
use rust_lib_zanzibarr::engine::locator::{LocatorError, SegmentLocator};
use rust_lib_zanzibarr::engine::nntp::{self, NntpPool, ProviderConfig, TlsNntpConnector};
use rust_lib_zanzibarr::engine::nntp_source::NntpByteSource;
use rust_lib_zanzibarr::engine::nzb::{self, NzbFile};
use rust_lib_zanzibarr::engine::server::{self, RangeSource};
use rust_lib_zanzibarr::engine::yenc;

/// Keychain servis adı; anahtarlar uygulamadakiyle aynı adları izler.
const SERVICE: &str = "zanzibarr";
const KEY_HOST: &str = "provider.host";
const KEY_PORT: &str = "provider.port";
const KEY_USERNAME: &str = "provider.username";
const KEY_PASSWORD: &str = "provider.password";
const KEY_MAX_CONNECTIONS: &str = "provider.maxConnections";

const NETWORK_TIMEOUT: Duration = Duration::from_secs(30);

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("setup") => setup(),
        Some("show") => show(),
        Some("clear") => clear(),
        Some("check") => run_async(check()),
        Some("fetch") => match args.get(1) {
            // İkinci argüman verilirse çözülen baytlar diske yazılır
            // (başlık incelemesi gibi tanı işleri için).
            Some(message_id) => run_async(fetch(message_id.clone(), args.get(2).cloned())),
            None => {
                eprintln!("kullanım: zanzibarr-cli fetch <message-id> [çıktı-dosyası]");
                return ExitCode::FAILURE;
            }
        },
        Some("probe") => match args.get(1) {
            Some(nzb_path) => {
                let offset = args.get(2).map(|s| s.parse::<u64>());
                match offset {
                    Some(Err(_)) => {
                        eprintln!("offset bir sayı olmalı");
                        return ExitCode::FAILURE;
                    }
                    Some(Ok(o)) => run_async(probe(nzb_path.clone(), Some(o))),
                    None => run_async(probe(nzb_path.clone(), None)),
                }
            }
            None => {
                eprintln!("kullanım: zanzibarr-cli probe <nzb-dosyası> [çözülmüş-offset]");
                return ExitCode::FAILURE;
            }
        },
        Some("serve") => match args.get(1) {
            Some(nzb_path) => {
                let port = args.get(2).map(|s| s.parse::<u16>());
                match port {
                    Some(Err(_)) => {
                        eprintln!("port bir sayı olmalı");
                        return ExitCode::FAILURE;
                    }
                    Some(Ok(p)) => run_async(serve(nzb_path.clone(), p)),
                    None => run_async(serve(nzb_path.clone(), 0)),
                }
            }
            None => {
                eprintln!("kullanım: zanzibarr-cli serve <nzb-dosyası> [port]");
                return ExitCode::FAILURE;
            }
        },
        Some("stream-check") => match args.get(1) {
            Some(nzb_path) => {
                let offset = args.get(2).map(|s| s.parse::<u64>());
                match offset {
                    Some(Err(_)) => {
                        eprintln!("offset bir sayı olmalı");
                        return ExitCode::FAILURE;
                    }
                    Some(Ok(o)) => stream_check(nzb_path.clone(), Some(o)),
                    None => stream_check(nzb_path.clone(), None),
                }
            }
            None => {
                eprintln!("kullanım: zanzibarr-cli stream-check <nzb-dosyası> [çözülmüş-offset]");
                return ExitCode::FAILURE;
            }
        },
        _ => {
            print_help();
            return ExitCode::SUCCESS;
        }
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("hata: {err}");
            ExitCode::FAILURE
        }
    }
}

fn print_help() {
    println!(
        "zanzibarr-cli — geçici geliştirme aracı\n\
         \n\
         Komutlar:\n\
         setup   Sağlayıcı bilgilerini sorar, Keychain'e yazar\n\
         (parola gizli prompt ile alınır, asla argüman değildir)\n\
         show    Kayıtlı ayarları gösterir (parolayı asla yazmaz)\n\
         clear   Keychain'deki Zanzibarr kayıtlarını siler\n\
         check   TLS + AUTHINFO + DATE ile bağlantıyı sınar\n\
         fetch <message-id>  Tek article çeker, yEnc olarak çözmeyi dener\n\
         probe <nzb> [offset]  NZB'nin en büyük dosyasında verilen çözülmüş\n\
         byte offsetini eşleyiciyle çözer (seek kanıtı)\n\
         serve <nzb> [port]  NZB'nin en büyük dosyasını localhost HTTP Range\n\
         server olarak sunar (curl --range / media_kit için)\n\
         stream-check <nzb>  Uygulamanın gerçek stream seçimini başlatır ve\n\
         ilk medya imzasını güvenli biçimde doğrular"
    );
}

fn run_async(fut: impl std::future::Future<Output = Result<(), String>>) -> Result<(), String> {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())?
        .block_on(fut)
}

fn entry(key: &str) -> Result<keyring::Entry, String> {
    keyring::Entry::new(SERVICE, key).map_err(|e| e.to_string())
}

fn read_secret(key: &str) -> Result<Option<String>, String> {
    match entry(key)?.get_password() {
        Ok(value) => return Ok(Some(value)),
        Err(keyring::Error::NoEntry) => {}
        Err(err) => return Err(err.to_string()),
    }
    // Eski kurulumlar (yeniden adlandırma öncesi) kimliği "usenews"
    // servisinde sakladı; bulunamazsa oraya da bak.
    match keyring::Entry::new("usenews", key) {
        Ok(legacy) => match legacy.get_password() {
            Ok(value) => Ok(Some(value)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(err) => Err(err.to_string()),
        },
        Err(err) => Err(err.to_string()),
    }
}

fn write_secret(key: &str, value: &str) -> Result<(), String> {
    entry(key)?.set_password(value).map_err(|e| e.to_string())
}

/// Görünür alanlar için satır sorusu; boş girişte mevcut/öntanımlı kalır.
fn prompt(label: &str, current: Option<&str>) -> Result<String, String> {
    let hint = current
        .map(|value| format!(" [{value}]"))
        .unwrap_or_default();
    print!("{label}{hint}: ");
    io::stdout().flush().map_err(|e| e.to_string())?;
    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .map_err(|e| e.to_string())?;
    let input = input.trim();
    if input.is_empty() {
        current
            .map(str::to_string)
            .ok_or_else(|| format!("{label} boş bırakılamaz"))
    } else {
        Ok(input.to_string())
    }
}

fn setup() -> Result<(), String> {
    println!("Zanzibarr sağlayıcı kurulumu — değerler yalnızca Keychain'e yazılır.\n");

    let host = prompt("NNTP sunucusu", read_secret(KEY_HOST)?.as_deref())?;
    let port = prompt(
        "Port (TLS)",
        Some(read_secret(KEY_PORT)?.as_deref().unwrap_or("563")),
    )?;
    port.parse::<u16>()
        .map_err(|_| format!("port sayı olmalı: {port}"))?;
    let username = prompt("Kullanıcı adı", read_secret(KEY_USERNAME)?.as_deref())?;
    let max_connections = prompt(
        "Eşzamanlı bağlantı limiti",
        Some(read_secret(KEY_MAX_CONNECTIONS)?.as_deref().unwrap_or("10")),
    )?;
    max_connections
        .parse::<usize>()
        .map_err(|_| format!("bağlantı limiti sayı olmalı: {max_connections}"))?;

    // Parola: echo'suz, iki kez; boşsa mevcut parola korunur.
    let has_existing = read_secret(KEY_PASSWORD)?.is_some();
    let suffix = if has_existing {
        " (boş bırak = mevcut korunur)"
    } else {
        ""
    };
    let password =
        rpassword::prompt_password(format!("Parola{suffix}: ")).map_err(|e| e.to_string())?;
    if password.is_empty() {
        if !has_existing {
            return Err("parola boş bırakılamaz".into());
        }
        println!("Parola değiştirilmedi.");
    } else {
        let confirm = rpassword::prompt_password("Parola (tekrar): ").map_err(|e| e.to_string())?;
        if password != confirm {
            return Err("parolalar eşleşmedi; hiçbir şey yazılmadı".into());
        }
        write_secret(KEY_PASSWORD, &password)?;
    }

    write_secret(KEY_HOST, &host)?;
    write_secret(KEY_PORT, &port)?;
    write_secret(KEY_USERNAME, &username)?;
    write_secret(KEY_MAX_CONNECTIONS, &max_connections)?;

    println!("\nKaydedildi. Sınamak için: zanzibarr-cli check");
    Ok(())
}

fn show() -> Result<(), String> {
    let password_state = if read_secret(KEY_PASSWORD)?.is_some() {
        "[kayıtlı — gösterilmez]"
    } else {
        "[yok]"
    };
    println!(
        "Sunucu   : {}\nPort     : {}\nKullanıcı: {}\nParola   : {}\nBağlantı : {}",
        read_secret(KEY_HOST)?.unwrap_or_else(|| "[yok]".into()),
        read_secret(KEY_PORT)?.unwrap_or_else(|| "[yok]".into()),
        read_secret(KEY_USERNAME)?.unwrap_or_else(|| "[yok]".into()),
        password_state,
        read_secret(KEY_MAX_CONNECTIONS)?.unwrap_or_else(|| "[yok]".into()),
    );
    Ok(())
}

fn clear() -> Result<(), String> {
    for key in [
        KEY_HOST,
        KEY_PORT,
        KEY_USERNAME,
        KEY_PASSWORD,
        KEY_MAX_CONNECTIONS,
    ] {
        match entry(key)?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => {}
            Err(err) => return Err(err.to_string()),
        }
    }
    println!("Keychain'deki Zanzibarr kayıtları silindi.");
    Ok(())
}

fn load_config() -> Result<ProviderConfig, String> {
    let missing = || "eksik ayar; önce çalıştır: zanzibarr-cli setup".to_string();
    Ok(ProviderConfig {
        host: read_secret(KEY_HOST)?.ok_or_else(missing)?,
        port: read_secret(KEY_PORT)?
            .ok_or_else(missing)?
            .parse()
            .map_err(|_| "kayıtlı port bozuk; setup'ı yeniden çalıştır".to_string())?,
        username: read_secret(KEY_USERNAME)?.ok_or_else(missing)?,
        password: read_secret(KEY_PASSWORD)?.ok_or_else(missing)?,
        max_connections: read_secret(KEY_MAX_CONNECTIONS)?
            .ok_or_else(missing)?
            .parse()
            .map_err(|_| "kayıtlı bağlantı limiti bozuk".to_string())?,
    })
}

/// Keychain'deki ayarlardan TLS+AUTHINFO'lu bağlantı havuzu kurar.
fn build_pool() -> Result<Arc<NntpPool<TlsNntpConnector>>, String> {
    let config = load_config()?;
    Ok(TlsNntpConnector::new(config).into_pool())
}

/// Uygulamanın FRB ile kullandığı aynı `start_stream` yolunu gerçek sağlayıcı
/// üzerinde sınar. Kimlik bilgileri yalnızca Keychain'den belleğe alınır;
/// parola, archive password veya message-ID yazdırılmaz.
fn stream_check(nzb_path: String, offset: Option<u64>) -> Result<(), String> {
    let config = load_config()?;
    println!("Akış hazırlanıyor; arşiv ciltleri ve arşiv başlığı doğrulanıyor…");
    let info = start_stream(
        ProviderConfigDto {
            host: config.host,
            port: config.port,
            username: config.username,
            password: config.password,
            max_connections: config.max_connections as u32,
        },
        nzb_path,
    )?;

    let address_and_path = info
        .url
        .strip_prefix("http://")
        .ok_or_else(|| "localhost stream URL biçimi geçersiz".to_string())?;
    let (address, path) = address_and_path
        .split_once('/')
        .ok_or_else(|| "localhost stream URL yolu yok".to_string())?;
    let mut socket = TcpStream::connect(address).map_err(|error| error.to_string())?;
    socket
        .set_read_timeout(Some(Duration::from_secs(60)))
        .map_err(|error| error.to_string())?;
    // Offset verilmezse dosya başı istenir ve medya imzası doğrulanır; başka
    // bir offset verilirse amaç arşiv parça eşleminin uzak seek'i doğru
    // çözümlediğini kanıtlamaktır (206 + tam 32 bayt yeterli).
    let start = offset.unwrap_or(0).min(info.size.saturating_sub(32));
    let end = start + 31;
    let request = format!(
        "GET /{path} HTTP/1.1\r\nHost: {address}\r\nRange: bytes={start}-{end}\r\nConnection: close\r\n\r\n"
    );
    socket
        .write_all(request.as_bytes())
        .map_err(|error| error.to_string())?;

    let mut response = Vec::new();
    socket
        .read_to_end(&mut response)
        .map_err(|error| error.to_string())?;
    let header_end = response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|index| index + 4)
        .ok_or_else(|| "localhost HTTP yanıt başlığı eksik".to_string())?;
    let header = std::str::from_utf8(&response[..header_end])
        .map_err(|_| "localhost HTTP yanıt başlığı UTF-8 değil".to_string())?;
    if !header.starts_with("HTTP/1.1 206") {
        return Err("localhost Range isteği 206 döndürmedi".into());
    }
    let body = &response[header_end..];
    if body.len() != 32 {
        return Err(format!(
            "localhost {start}-{end} aralığı için 32 bayt yerine {} bayt döndü",
            body.len()
        ));
    }
    if offset.is_none() {
        let recognized = body.starts_with(&[0x1A, 0x45, 0xDF, 0xA3])
            || body.get(4..8) == Some(b"ftyp")
            || body.first() == Some(&0x47);
        if !recognized {
            return Err("arşiv içinden dönen ilk baytlar medya imzası değil".into());
        }
    }

    println!(
        "Akış doğrulandı: {} · {} bayt · {} segment · aralık {start}-{end} geçerli",
        info.filename, info.size, info.segment_count
    );
    Ok(())
}

async fn connect_and_auth() -> Result<nntp::TlsNntpConnection, String> {
    let config = load_config()?;
    println!("Bağlanılıyor: {}:{} (TLS)…", config.host, config.port);
    let mut conn = tokio::time::timeout(
        NETWORK_TIMEOUT,
        nntp::connect_tls(&config.host, config.port),
    )
    .await
    .map_err(|_| "bağlantı zaman aşımı".to_string())?
    .map_err(|e| e.to_string())?;
    println!("TLS kuruldu, karşılama alındı. AUTHINFO gönderiliyor…");
    tokio::time::timeout(
        NETWORK_TIMEOUT,
        conn.authenticate(&config.username, &config.password),
    )
    .await
    .map_err(|_| "kimlik doğrulama zaman aşımı".to_string())?
    .map_err(|e| e.to_string())?;
    println!("Kimlik doğrulandı.");
    let _ = conn.mode_reader().await;
    Ok(conn)
}

async fn check() -> Result<(), String> {
    let mut conn = connect_and_auth().await?;
    let date = tokio::time::timeout(NETWORK_TIMEOUT, conn.date())
        .await
        .map_err(|_| "DATE zaman aşımı".to_string())?
        .map_err(|e| e.to_string())?;
    println!("Sunucu saati (DATE): {date}");
    let _ = conn.quit().await;
    println!("Bağlantı sınaması BAŞARILI.");
    Ok(())
}

async fn fetch(message_id: String, output_path: Option<String>) -> Result<(), String> {
    let mut conn = connect_and_auth().await?;
    println!("Article gövdesi çekiliyor…");
    let body = tokio::time::timeout(NETWORK_TIMEOUT, conn.body_by_message_id(&message_id))
        .await
        .map_err(|_| "BODY zaman aşımı".to_string())?
        .map_err(|e| e.to_string())?;
    println!("Gövde alındı: {} bayt (kodlu).", body.len());

    match yenc::decode(&body) {
        Ok(part) => {
            println!(
                "yEnc çözüldü: name={} boyut={} bayt (dosya toplamı {} bayt)",
                part.name,
                part.data.len(),
                part.file_size
            );
            if let (Some(begin), Some(end)) = (part.begin, part.end) {
                println!(
                    "Parça aralığı: {begin}-{end} (part {}/{})",
                    part.part.map_or_else(|| "?".into(), |p| p.to_string()),
                    part.total.map_or_else(|| "?".into(), |t| t.to_string()),
                );
            }
            match part.part_crc32 {
                Some(_) => println!("pcrc32 doğrulandı ✔"),
                None => println!("pcrc32 yok (doğrulanacak CRC bulunamadı)"),
            }
            if let Some(path) = output_path {
                std::fs::write(&path, &part.data)
                    .map_err(|e| format!("{path} yazılamadı: {e}"))?;
                println!("Çözülen baytlar {path} dosyasına yazıldı.");
            }
        }
        Err(err) => println!("Gövde yEnc olarak çözülemedi: {err}"),
    }

    let _ = conn.quit().await;
    Ok(())
}

/// NZB'nin en büyük dosyası (en çok segmentli) — genelde video.
fn largest_file(nzb: &nzb::Nzb) -> Option<&NzbFile> {
    nzb.files.iter().max_by_key(|f| f.segments.len())
}

/// Bir çözülmüş byte aralığını, gereken segmentleri çekip çözerek karşılar;
/// birleştirilmiş baytları döndürür. Seek yolunun kendisi.
async fn read_range(
    conn: &mut nntp::TlsNntpConnection,
    locator: &mut SegmentLocator,
    cache: &mut HashMap<usize, Vec<u8>>,
    range: Range<u64>,
) -> Result<Vec<u8>, String> {
    // resolve → NeedSegments → çek/çöz/kaydet → resolve; sonlu döngü.
    let slices = loop {
        match locator.resolve(range.clone()) {
            Ok(slices) => break slices,
            Err(LocatorError::NeedSegments(indices)) => {
                for index in indices {
                    let mid = locator
                        .message_id(index)
                        .ok_or_else(|| format!("segment {index} yok"))?
                        .to_string();
                    println!("  · segment #{} çekiliyor…", index + 1);
                    let body = tokio::time::timeout(NETWORK_TIMEOUT, conn.body_by_message_id(&mid))
                        .await
                        .map_err(|_| "BODY zaman aşımı".to_string())?
                        .map_err(|e| e.to_string())?;
                    let part = yenc::decode(&body).map_err(|e| e.to_string())?;
                    println!(
                        "    çözüldü: {} bayt, aralık {}-{}, pcrc32 {}",
                        part.data.len(),
                        part.begin.map_or(0, |b| b),
                        part.end.map_or(0, |e| e),
                        if part.part_crc32.is_some() {
                            "✔"
                        } else {
                            "yok"
                        },
                    );
                    locator
                        .record_part(index, &part)
                        .map_err(|e| e.to_string())?;
                    cache.insert(index, part.data);
                }
            }
            Err(other) => return Err(other.to_string()),
        }
    };

    let mut out = Vec::with_capacity((range.end - range.start) as usize);
    for slice in slices {
        let data = cache
            .get(&slice.index)
            .ok_or_else(|| format!("segment {} verisi cache'te yok", slice.index))?;
        let from = slice.within_segment.start as usize;
        let to = slice.within_segment.end as usize;
        out.extend_from_slice(&data[from..to]);
    }
    Ok(out)
}

async fn probe(nzb_path: String, offset: Option<u64>) -> Result<(), String> {
    let xml = std::fs::read_to_string(&nzb_path).map_err(|e| format!("NZB okunamadı: {e}"))?;
    let parsed = nzb::parse_nzb(&xml).map_err(|e| e.to_string())?;
    let file = largest_file(&parsed)
        .ok_or_else(|| "NZB'de dosya yok".to_string())?
        .clone();
    println!(
        "Hedef dosya: {} ({} segment, ~{:.2} GB kodlu)",
        file.filename().unwrap_or("(adsız)"),
        file.segments.len(),
        file.encoded_bytes() as f64 / 1e9,
    );

    let mut locator = SegmentLocator::from_nzb_file(&file);
    let mut cache: HashMap<usize, Vec<u8>> = HashMap::new();
    let mut conn = connect_and_auth().await?;

    // Dosya boyutunu öğrenmek için ilk segmenti çek (bootstrap).
    println!("\n[1] Bootstrap: ilk segment çekilip yerleşim öğreniliyor…");
    read_range(&mut conn, &mut locator, &mut cache, 0..1).await?;
    let file_size = locator
        .file_size()
        .ok_or_else(|| "dosya boyutu öğrenilemedi".to_string())?;
    println!("    Çözülmüş dosya boyutu (yEnc size): {file_size} bayt");

    // Seek hedefi: verilmezse dosyanın ortası.
    let target = offset
        .unwrap_or(file_size / 2)
        .min(file_size.saturating_sub(1));
    let want = 64u64.min(file_size - target);
    let range = target..target + want;
    println!(
        "\n[2] Seek: çözülmüş ofset {target} isteniyor ({want} bayt) — \
         eşleyici gereken segmenti bulup çekecek…"
    );
    let data = read_range(&mut conn, &mut locator, &mut cache, range.clone()).await?;

    println!("\n[3] Sonuç: {} bayt döndü.", data.len());
    let preview: String = data
        .iter()
        .take(32)
        .map(|b| format!("{b:02x}"))
        .collect::<Vec<_>>()
        .join(" ");
    println!("    İlk {} bayt (hex): {preview}", data.len().min(32));
    let est = locator
        .estimate_index(target)
        .map(|i| (i + 1).to_string())
        .unwrap_or_else(|| "?".into());
    println!(
        "    Bu ofset segment #{est}'e düştü; ofsetler yEnc begin/end'ten \
         (NZB bytes'tan DEĞİL) hesaplandı."
    );

    let _ = conn.quit().await;
    println!("\nSeek doğrulaması BAŞARILI.");
    Ok(())
}

async fn serve(nzb_path: String, port: u16) -> Result<(), String> {
    let xml = std::fs::read_to_string(&nzb_path).map_err(|e| format!("NZB okunamadı: {e}"))?;
    let parsed = nzb::parse_nzb(&xml).map_err(|e| e.to_string())?;
    let file = largest_file(&parsed)
        .ok_or_else(|| "NZB'de dosya yok".to_string())?
        .clone();

    let pool = build_pool()?;
    println!(
        "Kaynak hazırlanıyor (bootstrap: ilk segment çekiliyor)…\n  dosya: {}",
        file.filename().unwrap_or("(adsız)")
    );
    let source = NntpByteSource::new(pool, &file)
        .await
        .map_err(|e| e.to_string())?;
    let total = source.total_len();
    println!(
        "  çözülmüş boyut: {total} bayt ({:.2} GB), {} segment",
        total as f64 / 1e9,
        source.segment_count()
    );

    let listener = server::bind_local(port)
        .await
        .map_err(|e| format!("port bağlanamadı: {e}"))?;
    let bound = listener.local_addr().map_err(|e| e.to_string())?.port();

    let name = source.filename().to_string();
    println!(
        "\nSunuluyor: http://127.0.0.1:{bound}/{name}\n\
         Dene:\n  \
         curl -s -D - -o /dev/null -r 0-1023        http://127.0.0.1:{bound}/{name}\n  \
         curl -s -D - -o /dev/null -r {}-{}  http://127.0.0.1:{bound}/{name}\n  \
         curl -s -D - -o /dev/null -r -65536        http://127.0.0.1:{bound}/{name}\n\
         (Ctrl-C ile durdur)",
        total / 2,
        total / 2 + 63,
    );

    server::serve(listener, Arc::new(source))
        .await
        .map_err(|e| e.to_string())
}
