//! Tek NNTP bağlantısı: komut gönderme, yanıt/multiline okuma, AUTHINFO.
//!
//! [`NntpConnection`] akış tipinden bağımsızdır (`AsyncRead + AsyncWrite`);
//! gerçek kullanımda TLS akışı, testlerde `tokio::io::duplex` ile sahte
//! sunucu kullanılır — protokol kodu iki durumda da birebir aynıdır.

use std::sync::Arc;

use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;
use tokio_rustls::rustls;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::TlsConnector;

use super::{NntpError, Response};

/// Tek durum satırı için üst sınır; saldırgan sunucuya karşı koruma.
const MAX_LINE: usize = 64 * 1024;
/// Tek article gövdesi için üst sınır (tipik segment ~750 KB).
const MAX_BODY: usize = 16 * 1024 * 1024;

pub type TlsNntpConnection = NntpConnection<tokio_rustls::client::TlsStream<TcpStream>>;

pub struct NntpConnection<S> {
    stream: BufReader<S>,
    /// Karşılamadaki 200/201 ayrımı (201 = post yasak; okuma için yeterli).
    pub posting_allowed: bool,
}

impl<S: AsyncRead + AsyncWrite + Unpin> NntpConnection<S> {
    /// Karşılama satırını okur (200/201 bekler).
    pub async fn handshake(stream: S) -> Result<Self, NntpError> {
        let mut conn = NntpConnection {
            stream: BufReader::new(stream),
            posting_allowed: false,
        };
        let greeting = conn.read_response().await?;
        match greeting.code {
            200 => conn.posting_allowed = true,
            201 => conn.posting_allowed = false,
            code => {
                return Err(NntpError::UnexpectedResponse {
                    context: "karşılama",
                    code,
                    text: greeting.text,
                })
            }
        }
        Ok(conn)
    }

    /// RFC 4643 AUTHINFO USER/PASS akışı.
    ///
    /// Parola yalnızca sokete yazılır; hata mesajlarına ve loglara girmez.
    pub async fn authenticate(
        &mut self,
        username: &str,
        password: &str,
    ) -> Result<(), NntpError> {
        if username.contains(['\r', '\n']) || username.is_empty() {
            return Err(NntpError::InvalidArgument(
                "kullanıcı adı boş veya satır sonu içeriyor".into(),
            ));
        }
        if password.contains(['\r', '\n']) {
            // Değeri hata metnine bilerek koymuyoruz.
            return Err(NntpError::InvalidArgument(
                "parola satır sonu içeremez".into(),
            ));
        }

        let resp = self.command(&format!("AUTHINFO USER {username}")).await?;
        match resp.code {
            281 => return Ok(()), // parolasız kabul
            381 => {}             // parola bekleniyor
            code => return Err(NntpError::AuthFailed { code, text: resp.text }),
        }

        let resp = self.command(&format!("AUTHINFO PASS {password}")).await?;
        match resp.code {
            281 => Ok(()),
            code => Err(NntpError::AuthFailed { code, text: resp.text }),
        }
    }

    /// RFC 3977 MODE READER; anlamayan sunuculara (500/501) tolerans gösterir.
    pub async fn mode_reader(&mut self) -> Result<(), NntpError> {
        let resp = self.command("MODE READER").await?;
        match resp.code {
            200 | 201 | 500 | 501 => Ok(()),
            code => Err(NntpError::UnexpectedResponse {
                context: "MODE READER",
                code,
                text: resp.text,
            }),
        }
    }

    /// Bağlantı sağlığı için hafif komut: `DATE` → `111 yyyymmddhhmmss`.
    pub async fn date(&mut self) -> Result<String, NntpError> {
        let resp = self.command("DATE").await?;
        match resp.code {
            111 => Ok(resp.text),
            code => Err(NntpError::UnexpectedResponse {
                context: "DATE",
                code,
                text: resp.text,
            }),
        }
    }

    /// `BODY <message-id>`: article gövdesini dot-unstuffing yapılmış ham
    /// bayt olarak döndürür (satır sonları CRLF'e normalize edilir).
    /// `message_id` açılı ayraçsız verilir (NZB'deki kanonik biçim).
    pub async fn body_by_message_id(
        &mut self,
        message_id: &str,
    ) -> Result<Vec<u8>, NntpError> {
        let id = message_id.trim().trim_start_matches('<').trim_end_matches('>');
        if id.is_empty() || id.contains(['\r', '\n', '<', '>']) {
            return Err(NntpError::InvalidArgument(format!(
                "geçersiz message-ID: {id:.80}"
            )));
        }
        let resp = self.command(&format!("BODY <{id}>")).await?;
        match resp.code {
            222 => self.read_multiline().await,
            430 => Err(NntpError::NoSuchArticle(id.to_string())),
            code => Err(NntpError::UnexpectedResponse {
                context: "BODY",
                code,
                text: resp.text,
            }),
        }
    }

    /// Nazik kapanış; yanıt beklenir ama hatası önemsenmez.
    pub async fn quit(mut self) -> Result<(), NntpError> {
        let _ = self.command("QUIT").await;
        Ok(())
    }

    async fn command(&mut self, line: &str) -> Result<Response, NntpError> {
        let stream = self.stream.get_mut();
        stream.write_all(line.as_bytes()).await?;
        stream.write_all(b"\r\n").await?;
        stream.flush().await?;
        self.read_response().await
    }

    async fn read_response(&mut self) -> Result<Response, NntpError> {
        let line = self.read_line().await?;
        Response::parse(&String::from_utf8_lossy(&line))
    }

    /// CRLF'siz tek satır okur; boyut sınırı ve erken EOF denetimli.
    async fn read_line(&mut self) -> Result<Vec<u8>, NntpError> {
        let mut buf = Vec::new();
        let n = (&mut self.stream)
            .take(MAX_LINE as u64 + 1)
            .read_until(b'\n', &mut buf)
            .await?;
        if n == 0 {
            return Err(NntpError::ConnectionClosed);
        }
        if !buf.ends_with(b"\n") {
            if buf.len() > MAX_LINE {
                return Err(NntpError::TooLarge { limit: MAX_LINE });
            }
            return Err(NntpError::ConnectionClosed); // satır ortasında EOF
        }
        buf.pop();
        if buf.ends_with(b"\r") {
            buf.pop();
        }
        Ok(buf)
    }

    /// `.\r\n` sonlandırıcısına kadar okur; `..` ile başlayan satırların ilk
    /// noktasını kaldırır (RFC 3977 dot-stuffing).
    async fn read_multiline(&mut self) -> Result<Vec<u8>, NntpError> {
        let mut body = Vec::new();
        loop {
            let line = self.read_line().await?;
            if line == b"." {
                return Ok(body);
            }
            let content: &[u8] = if line.starts_with(b"..") { &line[1..] } else { &line };
            if body.len() + content.len() + 2 > MAX_BODY {
                return Err(NntpError::TooLarge { limit: MAX_BODY });
            }
            body.extend_from_slice(content);
            body.extend_from_slice(b"\r\n");
        }
    }
}

/// Sertifika doğrulamalı TLS bağlantısı kurar ve karşılamayı okur.
/// Kök sertifikalar `webpki-roots`'tan gelir (platform bağımsız).
pub async fn connect_tls(host: &str, port: u16) -> Result<TlsNntpConnection, NntpError> {
    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let config = rustls::ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    let connector = TlsConnector::from(Arc::new(config));

    let server_name = ServerName::try_from(host.to_string()).map_err(|_| {
        NntpError::InvalidArgument(format!("geçersiz sunucu adı: {host}"))
    })?;
    let tcp = TcpStream::connect((host, port)).await?;
    tcp.set_nodelay(true).ok();
    let tls = connector.connect(server_name, tcp).await?;
    NntpConnection::handshake(tls).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{duplex, DuplexStream};

    /// Sahte sunucu: beklenen komutları sırayla doğrular, yanıtları basar.
    /// İlk eleman karşılama satırıdır (komut beklemez).
    fn mock_server(
        stream: DuplexStream,
        greeting: &'static str,
        script: Vec<(&'static str, &'static str)>,
    ) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            let mut stream = BufReader::new(stream);
            stream
                .get_mut()
                .write_all(greeting.as_bytes())
                .await
                .unwrap();
            for (expected, reply) in script {
                let mut line = String::new();
                stream.read_line(&mut line).await.unwrap();
                assert_eq!(line, expected, "istemci beklenmeyen komut gönderdi");
                stream.get_mut().write_all(reply.as_bytes()).await.unwrap();
            }
        })
    }

    #[tokio::test]
    async fn karsilamada_200_ve_201_kabul_edilir() {
        for (greeting, posting) in [("200 hazir\r\n", true), ("201 salt-okur\r\n", false)] {
            let (client, server) = duplex(4096);
            let task = mock_server(server, greeting, vec![]);
            let conn = NntpConnection::handshake(client).await.unwrap();
            assert_eq!(conn.posting_allowed, posting);
            task.await.unwrap();
        }
    }

    #[tokio::test]
    async fn karsilamada_hata_kodu_reddedilir() {
        let (client, server) = duplex(4096);
        let task = mock_server(server, "400 hizmet yok\r\n", vec![]);
        assert!(matches!(
            NntpConnection::handshake(client).await,
            Err(NntpError::UnexpectedResponse { code: 400, .. })
        ));
        task.await.unwrap();
    }

    #[tokio::test]
    async fn authinfo_user_pass_akisi() {
        let (client, server) = duplex(4096);
        let task = mock_server(
            server,
            "200 hazir\r\n",
            vec![
                ("AUTHINFO USER test-kullanici\r\n", "381 parola bekleniyor\r\n"),
                ("AUTHINFO PASS test-parola\r\n", "281 hosgeldin\r\n"),
            ],
        );
        let mut conn = NntpConnection::handshake(client).await.unwrap();
        conn.authenticate("test-kullanici", "test-parola").await.unwrap();
        task.await.unwrap();
    }

    #[tokio::test]
    async fn yanlis_parola_auth_failed_dondurur() {
        let (client, server) = duplex(4096);
        let task = mock_server(
            server,
            "200 hazir\r\n",
            vec![
                ("AUTHINFO USER test-kullanici\r\n", "381 parola bekleniyor\r\n"),
                ("AUTHINFO PASS yanlis\r\n", "481 reddedildi\r\n"),
            ],
        );
        let mut conn = NntpConnection::handshake(client).await.unwrap();
        assert!(matches!(
            conn.authenticate("test-kullanici", "yanlis").await,
            Err(NntpError::AuthFailed { code: 481, .. })
        ));
        task.await.unwrap();
    }

    #[tokio::test]
    async fn crlf_iceren_kimlik_sokete_yazilmadan_reddedilir() {
        let (client, server) = duplex(4096);
        // Sahte sunucu hiçbir komut BEKLEMEZ: injection satırı sokete
        // yazılsaydı script boş olduğu için test yine de yakalayamazdı;
        // bu yüzden istemci tarafında hata tipiyle doğruluyoruz.
        let task = mock_server(server, "200 hazir\r\n", vec![]);
        let mut conn = NntpConnection::handshake(client).await.unwrap();
        assert!(matches!(
            conn.authenticate("kotu\r\nQUIT", "p").await,
            Err(NntpError::InvalidArgument(_))
        ));
        assert!(matches!(
            conn.authenticate("iyi", "kotu\r\nparola").await,
            Err(NntpError::InvalidArgument(_))
        ));
        task.await.unwrap();
    }

    #[tokio::test]
    async fn body_dot_unstuffing_yapar() {
        let (client, server) = duplex(4096);
        let task = mock_server(
            server,
            "200 hazir\r\n",
            vec![(
                "BODY <seg1@news.example.com>\r\n",
                "222 0 <seg1@news.example.com>\r\n\
                 ilk satir\r\n\
                 ..nokta ile baslayan satir\r\n\
                 son satir\r\n\
                 .\r\n",
            )],
        );
        let mut conn = NntpConnection::handshake(client).await.unwrap();
        let body = conn
            .body_by_message_id("seg1@news.example.com")
            .await
            .unwrap();
        assert_eq!(
            body,
            b"ilk satir\r\n.nokta ile baslayan satir\r\nson satir\r\n"
        );
        task.await.unwrap();
    }

    #[tokio::test]
    async fn ayracli_message_id_normalize_edilir() {
        let (client, server) = duplex(4096);
        let task = mock_server(
            server,
            "200 hazir\r\n",
            vec![("BODY <a@b>\r\n", "222 0 <a@b>\r\nx\r\n.\r\n")],
        );
        let mut conn = NntpConnection::handshake(client).await.unwrap();
        // NZB'den ayraçlı gelse bile tek çift ayraçla gönderilir.
        conn.body_by_message_id("<a@b>").await.unwrap();
        task.await.unwrap();
    }

    #[tokio::test]
    async fn olmayan_article_430_no_such_article() {
        let (client, server) = duplex(4096);
        let task = mock_server(
            server,
            "200 hazir\r\n",
            vec![("BODY <yok@x>\r\n", "430 boyle bir article yok\r\n")],
        );
        let mut conn = NntpConnection::handshake(client).await.unwrap();
        assert!(matches!(
            conn.body_by_message_id("yok@x").await,
            Err(NntpError::NoSuchArticle(id)) if id == "yok@x"
        ));
        task.await.unwrap();
    }

    #[tokio::test]
    async fn body_yenc_ile_uctan_uca_cozulur() {
        // Sahte sunucudan dönen yEnc gövdesi decoder'dan geçer:
        // NNTP katmanı + yEnc katmanı birlikte, ağsız.
        let (client, server) = duplex(16 * 1024);
        let task = mock_server(
            server,
            "200 hazir\r\n",
            vec![(
                "BODY <yenc@x>\r\n",
                "222 0 <yenc@x>\r\n\
                 =ybegin part=1 total=1 line=128 size=9 name=test.bin\r\n\
                 =ypart begin=1 end=9\r\n\
                 [\\]^_`abc\r\n\
                 =yend size=9 part=1 pcrc32=cbf43926\r\n\
                 .\r\n",
            )],
        );
        let mut conn = NntpConnection::handshake(client).await.unwrap();
        let body = conn.body_by_message_id("yenc@x").await.unwrap();
        let part = crate::engine::yenc::decode(&body).unwrap();
        assert_eq!(part.data, b"123456789");
        assert_eq!(part.name, "test.bin");
        task.await.unwrap();
    }

    #[tokio::test]
    async fn date_calisir() {
        let (client, server) = duplex(4096);
        let task = mock_server(
            server,
            "200 hazir\r\n",
            vec![("DATE\r\n", "111 20260716120000\r\n")],
        );
        let mut conn = NntpConnection::handshake(client).await.unwrap();
        assert_eq!(conn.date().await.unwrap(), "20260716120000");
        task.await.unwrap();
    }
}
