//! Bağlantı havuzu iskeleti.
//!
//! Sağlayıcının eşzamanlı bağlantı limiti ([`super::ProviderConfig`]
//! `max_connections`) semaforla uygulanır: aynı anda en fazla o kadar
//! bağlantı dışarıda olabilir. Bırakılan bağlantılar boşta listesine döner
//! ve yeniden kullanılır; hatalı bağlantılar [`PooledConnection::discard`]
//! ile havuz dışına atılır.

use std::future::Future;
use std::ops::{Deref, DerefMut};
use std::sync::{Arc, Mutex};

use tokio::sync::{OwnedSemaphorePermit, Semaphore};

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
    idle: Mutex<Vec<C::Conn>>,
}

impl<C: Connect> NntpPool<C> {
    pub fn new(connector: C, max_connections: usize) -> Arc<Self> {
        Arc::new(NntpPool {
            connector,
            semaphore: Arc::new(Semaphore::new(max_connections.max(1))),
            idle: Mutex::new(Vec::new()),
        })
    }

    /// Bağlantı alır: limit doluysa yer açılana dek bekler; boşta bağlantı
    /// varsa onu kullanır, yoksa yenisini kurar.
    pub async fn checkout(self: &Arc<Self>) -> Result<PooledConnection<C>, NntpError> {
        let permit = Arc::clone(&self.semaphore)
            .acquire_owned()
            .await
            .expect("havuz semaforu kapatılmaz");
        let idle_conn = self.idle.lock().expect("kilit zehirlenmez").pop();
        let conn = match idle_conn {
            Some(conn) => conn,
            // Kurulum başarısızsa permit düşer; limit sızmaz.
            None => self.connector.connect().await?,
        };
        Ok(PooledConnection {
            pool: Arc::clone(self),
            conn: Some(conn),
            _permit: permit,
            discard: false,
        })
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
    discard: bool,
}

impl<C: Connect> PooledConnection<C> {
    /// Bağlantıyı yeniden kullanılmayacak diye işaretler (G/Ç hatası,
    /// protokol karışıklığı vb. sonrası çağrılır).
    pub fn discard(&mut self) {
        self.discard = true;
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
        if !self.discard {
            if let Some(conn) = self.conn.take() {
                self.pool
                    .idle
                    .lock()
                    .expect("kilit zehirlenmez")
                    .push(conn);
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
        let mut conn = connect_tls(&self.config.host, self.config.port).await?;
        conn.authenticate(&self.config.username, &self.config.password)
            .await?;
        conn.mode_reader().await?;
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
        for _ in 0..5 {
            let conn = pool.checkout().await.unwrap();
            drop(conn); // havuza geri döner
        }
        assert_eq!(pool.connector.created.load(Ordering::SeqCst), 1);
        assert_eq!(pool.idle_count(), 1);
    }

    #[tokio::test]
    async fn discard_edilen_baglanti_havuza_donmez() {
        let pool = NntpPool::new(CountingConnector::new(), 4);
        let mut conn = pool.checkout().await.unwrap();
        conn.discard();
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
                let conn = pool.checkout().await.unwrap();
                tokio::time::sleep(Duration::from_millis(5)).await;
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
        let held = pool.checkout().await.unwrap();
        let waiter = {
            let pool = Arc::clone(&pool);
            tokio::spawn(async move {
                let _conn = pool.checkout().await.unwrap();
            })
        };
        // Bağlantı elimizdeyken bekleyen bitmemeli.
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert!(!waiter.is_finished());
        drop(held);
        tokio::time::timeout(Duration::from_secs(1), waiter)
            .await
            .expect("bağlantı bırakılınca bekleyen açılmalı")
            .unwrap();
    }
}
