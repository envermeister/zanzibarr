//! Bağlantı havuzu iskeleti.
//!
//! Sağlayıcının eşzamanlı bağlantı limiti ([`super::ProviderConfig`]
//! `max_connections`) semaforla uygulanır: aynı anda en fazla o kadar
//! bağlantı dışarıda olabilir. Ödünç alınan bağlantı varsayılan olarak güvenli
//! sayılmaz; yalnız protokol yanıtı eksiksiz okunduktan sonra
//! [`PooledConnection::mark_reusable`] ile boşta listeye dönebilir. Böylece
//! iptal edilen bir BODY okumasının yarım soketi yeniden kullanılmaz.

use std::future::Future;
use std::ops::{Deref, DerefMut};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::{Mutex as AsyncMutex, Notify, OwnedSemaphorePermit, Semaphore};

use super::connection::{connect_tls, TlsNntpConnection};
use super::{NntpError, ProviderConfig};

/// Havuzun bağlantı fabrikası. Gerçekte TLS + AUTHINFO kurar; testlerde
/// sahte bağlantı üretir.
pub trait Connect: Send + Sync + 'static {
    type Conn: Send + 'static;
    fn connect(&self) -> impl Future<Output = Result<Self::Conn, NntpError>> + Send;
}

pub struct NntpPool<C: Connect> {
    connector: C,
    semaphore: Arc<Semaphore>,
    max_connections: usize,
    idle: Mutex<Vec<C::Conn>>,
    /// Eşzamanlı checkout'ların aynı anda TLS+AUTH bağlantısı yağdırmasını
    /// engeller. Kilidi alan görev boşta listeyi tekrar kontrol eder.
    connection_creation: AsyncMutex<()>,
    idle_available: Notify,
}

const CONNECTION_LIMIT_BACKOFF_STEPS: usize = 4;
const CONNECTION_LIMIT_BACKOFF_BASE_MS: u64 = 250;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const AUTH_TIMEOUT: Duration = Duration::from_secs(15);
const MODE_READER_TIMEOUT: Duration = Duration::from_secs(10);

fn connection_limit_backoff(step: usize) -> Option<Duration> {
    (step < CONNECTION_LIMIT_BACKOFF_STEPS)
        .then(|| Duration::from_millis(CONNECTION_LIMIT_BACKOFF_BASE_MS << step))
}

async fn with_operation_timeout<T>(
    operation: &'static str,
    duration: Duration,
    future: impl Future<Output = Result<T, NntpError>>,
) -> Result<T, NntpError> {
    tokio::time::timeout(duration, future)
        .await
        .map_err(|_| NntpError::Timeout { operation })?
}

impl<C: Connect> NntpPool<C> {
    pub fn new(connector: C, max_connections: usize) -> Arc<Self> {
        let max_connections = max_connections.max(1);
        Arc::new(NntpPool {
            connector,
            semaphore: Arc::new(Semaphore::new(max_connections)),
            max_connections,
            idle: Mutex::new(Vec::new()),
            connection_creation: AsyncMutex::new(()),
            idle_available: Notify::new(),
        })
    }

    /// Havuzun sabit eşzamanlı bağlantı sınırı. Başlatma işlerini de aynı
    /// sınırla kuyruklamak için kullanılır; anlık permit sayısından etkilenmez.
    pub fn max_connections(&self) -> usize {
        self.max_connections
    }

    /// Bağlantı alır: limit doluysa yer açılana dek bekler; boşta bağlantı
    /// varsa onu kullanır, yoksa yenisini kurar.
    pub async fn checkout(self: &Arc<Self>) -> Result<PooledConnection<C>, NntpError> {
        let permit = Arc::clone(&self.semaphore)
            .acquire_owned()
            .await
            .expect("havuz semaforu kapatılmaz");
        if let Some(conn) = self.take_idle() {
            return Ok(self.pooled(conn, permit));
        }

        // Bir görev bağlantı kurarken diğer checkout'lar burada bekler. Kilidi
        // alan her görev tekrar idle kontrolü yapar; önceki kurulum/kullanım
        // bitmişse yeni bir sağlayıcı oturumu açmak yerine onu devralır.
        let _creation_guard = self.connection_creation.lock().await;
        if let Some(conn) = self.take_idle() {
            return Ok(self.pooled(conn, permit));
        }

        let mut backoff_step = 0;
        let conn = loop {
            match self.connector.connect().await {
                Ok(conn) => break conn,
                Err(limit @ NntpError::ConnectionLimit { .. }) => {
                    // Bağlantı denemesi sürerken başka bir checkout bitmiş
                    // olabilir. Sağlayıcıya tekrar yük bindirmeden onu kullan.
                    if let Some(conn) = self.take_idle() {
                        break conn;
                    }

                    let Some(delay) = connection_limit_backoff(backoff_step) else {
                        return Err(limit);
                    };
                    backoff_step += 1;

                    // Notify gelecekteki drop'u, ikinci idle kontrolü de
                    // notified() kurulurken oluşabilecek yarışı kapsar.
                    let notified = self.idle_available.notified();
                    if let Some(conn) = self.take_idle() {
                        break conn;
                    }
                    let _ = tokio::time::timeout(delay, notified).await;
                    if let Some(conn) = self.take_idle() {
                        break conn;
                    }
                }
                // Kurulum başarısızsa permit düşer; limit sızmaz.
                Err(error) => return Err(error),
            }
        };
        Ok(self.pooled(conn, permit))
    }

    fn take_idle(&self) -> Option<C::Conn> {
        self.idle.lock().expect("kilit zehirlenmez").pop()
    }

    fn pooled(
        self: &Arc<Self>,
        conn: C::Conn,
        permit: OwnedSemaphorePermit,
    ) -> PooledConnection<C> {
        PooledConnection {
            pool: Arc::clone(self),
            conn: Some(conn),
            _permit: permit,
            reusable: false,
        }
    }

    pub fn idle_count(&self) -> usize {
        self.idle.lock().expect("kilit zehirlenmez").len()
    }
}

/// Havuzdan ödünç alınmış bağlantı; düşünce (drop) havuza geri döner.
pub struct PooledConnection<C: Connect> {
    pool: Arc<NntpPool<C>>,
    conn: Option<C::Conn>,
    _permit: OwnedSemaphorePermit,
    reusable: bool,
}

impl<C: Connect> PooledConnection<C> {
    /// Üzerindeki NNTP komutunun yanıtı eksiksiz tüketildiyse bağlantının
    /// havuza dönmesine izin verir. Bu çağrıdan önce future iptal edilirse
    /// varsayılan güvenli davranış soketi kapatmaktır.
    pub fn mark_reusable(&mut self) {
        self.reusable = true;
    }
}

impl<C: Connect> Deref for PooledConnection<C> {
    type Target = C::Conn;
    fn deref(&self) -> &C::Conn {
        self.conn.as_ref().expect("bağlantı drop'a kadar hep var")
    }
}

impl<C: Connect> DerefMut for PooledConnection<C> {
    fn deref_mut(&mut self) -> &mut C::Conn {
        self.conn.as_mut().expect("bağlantı drop'a kadar hep var")
    }
}

impl<C: Connect> Drop for PooledConnection<C> {
    fn drop(&mut self) {
        if self.reusable {
            if let Some(conn) = self.conn.take() {
                self.pool.idle.lock().expect("kilit zehirlenmez").push(conn);
                self.pool.idle_available.notify_one();
            }
        }
        // _permit burada düşer ve semafordaki yer açılır.
    }
}

/// Gerçek fabrika: TLS bağlantısı kurar, AUTHINFO ile doğrular,
/// MODE READER'ı toleranslı dener.
pub struct TlsNntpConnector {
    config: ProviderConfig,
}

impl TlsNntpConnector {
    pub fn new(config: ProviderConfig) -> Self {
        TlsNntpConnector { config }
    }

    /// Yapılandırmadaki limite göre havuz kurar.
    pub fn into_pool(self) -> Arc<NntpPool<Self>> {
        let max = self.config.max_connections;
        NntpPool::new(self, max)
    }
}

impl Connect for TlsNntpConnector {
    type Conn = TlsNntpConnection;

    async fn connect(&self) -> Result<TlsNntpConnection, NntpError> {
        let mut conn = with_operation_timeout(
            "NNTP TLS bağlantısı",
            CONNECT_TIMEOUT,
            connect_tls(&self.config.host, self.config.port),
        )
        .await?;
        with_operation_timeout(
            "NNTP kimlik doğrulaması",
            AUTH_TIMEOUT,
            conn.authenticate(&self.config.username, &self.config.password),
        )
        .await?;
        with_operation_timeout("NNTP MODE READER", MODE_READER_TIMEOUT, conn.mode_reader()).await?;
        Ok(conn)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;

    /// Sahte fabrika: kaç bağlantı kurulduğunu ve aynı anda kaçının dışarıda
    /// olduğunu sayar.
    struct CountingConnector {
        created: AtomicUsize,
        active: Arc<AtomicUsize>,
        peak: Arc<AtomicUsize>,
    }

    struct FakeConn {
        active: Arc<AtomicUsize>,
    }

    struct SerializedConnector {
        calls: AtomicUsize,
        connecting: AtomicUsize,
        peak_connecting: AtomicUsize,
    }

    impl Connect for SerializedConnector {
        type Conn = ();

        async fn connect(&self) -> Result<Self::Conn, NntpError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            let connecting = self.connecting.fetch_add(1, Ordering::SeqCst) + 1;
            self.peak_connecting.fetch_max(connecting, Ordering::SeqCst);
            tokio::time::sleep(Duration::from_millis(10)).await;
            self.connecting.fetch_sub(1, Ordering::SeqCst);
            Ok(())
        }
    }

    struct LimitAfterFirstConnector {
        calls: AtomicUsize,
    }

    impl Connect for LimitAfterFirstConnector {
        type Conn = ();

        async fn connect(&self) -> Result<Self::Conn, NntpError> {
            let call = self.calls.fetch_add(1, Ordering::SeqCst);
            if call == 0 {
                Ok(())
            } else {
                Err(NntpError::ConnectionLimit {
                    code: 502,
                    text: "Too many connections".into(),
                })
            }
        }
    }

    impl Drop for FakeConn {
        fn drop(&mut self) {
            self.active.fetch_sub(1, Ordering::SeqCst);
        }
    }

    impl CountingConnector {
        fn new() -> Self {
            CountingConnector {
                created: AtomicUsize::new(0),
                active: Arc::new(AtomicUsize::new(0)),
                peak: Arc::new(AtomicUsize::new(0)),
            }
        }
    }

    impl Connect for CountingConnector {
        type Conn = FakeConn;

        async fn connect(&self) -> Result<FakeConn, NntpError> {
            self.created.fetch_add(1, Ordering::SeqCst);
            let now = self.active.fetch_add(1, Ordering::SeqCst) + 1;
            self.peak.fetch_max(now, Ordering::SeqCst);
            Ok(FakeConn {
                active: Arc::clone(&self.active),
            })
        }
    }

    #[tokio::test]
    async fn ardisik_kullanim_tek_baglanti_kurar() {
        let pool = NntpPool::new(CountingConnector::new(), 4);
        assert_eq!(pool.max_connections(), 4);
        for _ in 0..5 {
            let mut conn = pool.checkout().await.unwrap();
            conn.mark_reusable();
            drop(conn); // havuza geri döner
        }
        assert_eq!(pool.connector.created.load(Ordering::SeqCst), 1);
        assert_eq!(pool.idle_count(), 1);
    }

    #[test]
    fn sifir_baglanti_limiti_bire_yukseltilir() {
        let pool = NntpPool::new(CountingConnector::new(), 0);
        assert_eq!(pool.max_connections(), 1);
    }

    #[tokio::test]
    async fn isaretlenmeyen_baglanti_varsayilan_olarak_havuza_donmez() {
        let pool = NntpPool::new(CountingConnector::new(), 4);
        let conn = pool.checkout().await.unwrap();
        drop(conn);
        assert_eq!(pool.idle_count(), 0);
        // Sonraki checkout yeni bağlantı kurmak zorunda.
        let _conn = pool.checkout().await.unwrap();
        assert_eq!(pool.connector.created.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn eszamanlilik_limiti_asilmaz() {
        let pool = NntpPool::new(CountingConnector::new(), 2);
        let mut tasks = Vec::new();
        for _ in 0..8 {
            let pool = Arc::clone(&pool);
            tasks.push(tokio::spawn(async move {
                let mut conn = pool.checkout().await.unwrap();
                tokio::time::sleep(Duration::from_millis(5)).await;
                conn.mark_reusable();
                drop(conn);
            }));
        }
        for task in tasks {
            task.await.unwrap();
        }
        // Aynı anda dışarıda olan bağlantı sayısı limiti hiç aşmamalı.
        assert!(pool.connector.peak.load(Ordering::SeqCst) <= 2);
        // Yeniden kullanım: 8 görev için en fazla 2 bağlantı kuruldu.
        assert!(pool.connector.created.load(Ordering::SeqCst) <= 2);
    }

    #[tokio::test]
    async fn limit_doluyken_checkout_bekler() {
        let pool = NntpPool::new(CountingConnector::new(), 1);
        let mut held = pool.checkout().await.unwrap();
        let waiter = {
            let pool = Arc::clone(&pool);
            tokio::spawn(async move {
                let mut conn = pool.checkout().await.unwrap();
                conn.mark_reusable();
            })
        };
        // Bağlantı elimizdeyken bekleyen bitmemeli.
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert!(!waiter.is_finished());
        held.mark_reusable();
        drop(held);
        tokio::time::timeout(Duration::from_secs(1), waiter)
            .await
            .expect("bağlantı bırakılınca bekleyen açılmalı")
            .unwrap();
    }

    #[tokio::test]
    async fn eszamanli_checkout_baglanti_kurulumunu_serilestirir() {
        let pool = NntpPool::new(
            SerializedConnector {
                calls: AtomicUsize::new(0),
                connecting: AtomicUsize::new(0),
                peak_connecting: AtomicUsize::new(0),
            },
            4,
        );
        let mut tasks = Vec::new();
        for _ in 0..4 {
            let pool = Arc::clone(&pool);
            tasks.push(tokio::spawn(async move {
                let mut conn = pool.checkout().await.unwrap();
                tokio::time::sleep(Duration::from_millis(100)).await;
                conn.mark_reusable();
                drop(conn);
            }));
        }
        for task in tasks {
            task.await.unwrap();
        }
        assert_eq!(pool.connector.calls.load(Ordering::SeqCst), 4);
        assert_eq!(
            pool.connector.peak_connecting.load(Ordering::SeqCst),
            1,
            "TLS+AUTH kurulumları aynı anda başlatılmamalı"
        );
    }

    #[tokio::test]
    async fn baglanti_kotasinda_donen_idle_baglanti_yeniden_kullanilir() {
        let pool = NntpPool::new(
            LimitAfterFirstConnector {
                calls: AtomicUsize::new(0),
            },
            2,
        );
        let mut first = pool.checkout().await.unwrap();
        let waiter = {
            let pool = Arc::clone(&pool);
            tokio::spawn(async move { pool.checkout().await })
        };

        tokio::time::timeout(Duration::from_secs(1), async {
            while pool.connector.calls.load(Ordering::SeqCst) < 2 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("ikinci bağlantı denemesi başlamalı");
        first.mark_reusable();
        drop(first);

        let mut reused = tokio::time::timeout(Duration::from_secs(1), waiter)
            .await
            .expect("idle bağlantı backoff beklemeden kullanılmalı")
            .unwrap()
            .unwrap();
        reused.mark_reusable();
        drop(reused);
        assert_eq!(pool.connector.calls.load(Ordering::SeqCst), 2);
        assert_eq!(pool.idle_count(), 1);
    }

    #[test]
    fn baglanti_kotasi_backoff_sonlu_ve_kademelidir() {
        assert_eq!(
            connection_limit_backoff(0),
            Some(Duration::from_millis(250))
        );
        assert_eq!(connection_limit_backoff(3), Some(Duration::from_secs(2)));
        assert_eq!(connection_limit_backoff(4), None);
    }

    #[tokio::test]
    async fn iptal_edilen_kullanim_yarim_baglantiyi_havuza_dondurmez() {
        let pool = NntpPool::new(CountingConnector::new(), 1);
        let (checked_out_tx, checked_out_rx) = tokio::sync::oneshot::channel();
        let task = {
            let pool = Arc::clone(&pool);
            tokio::spawn(async move {
                let _conn = pool.checkout().await.unwrap();
                let _ = checked_out_tx.send(());
                std::future::pending::<()>().await;
            })
        };

        checked_out_rx.await.unwrap();
        task.abort();
        assert!(task.await.unwrap_err().is_cancelled());
        assert_eq!(pool.idle_count(), 0);

        // İptal edilen kullanımın soketi yerine yeni bağlantı kurulmalı.
        let _replacement = pool.checkout().await.unwrap();
        assert_eq!(pool.connector.created.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn operasyon_timeout_acik_hata_dondurur() {
        let result = with_operation_timeout::<()>(
            "test işlemi",
            Duration::from_millis(5),
            std::future::pending(),
        )
        .await;
        assert!(matches!(
            result,
            Err(NntpError::Timeout {
                operation: "test işlemi"
            })
        ));
    }
}
