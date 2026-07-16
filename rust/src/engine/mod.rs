//! UseNews'in Usenet motoru: saf Rust, FRB API'sinden bağımsız.
//!
//! Modüller `cargo test` ile ağsız test edilir; Dart'a açılacak yüzey
//! ayrıca `crate::api` altında tanımlanır.

pub mod locator;
pub mod nntp;
pub mod nzb;
pub mod yenc;
