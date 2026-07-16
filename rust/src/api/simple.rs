#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Merhaba {name}, Rust çekirdeği ayakta! 🦀")
}

#[flutter_rust_bridge::frb(sync)]
pub fn engine_info() -> String {
    format!("{} v{}", env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION"))
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
