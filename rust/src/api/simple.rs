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
    configure_bundled_vulkan_driver();
}

/// macOS'ta vf_libplacebo gibi Vulkan zorunlu filtrelerin gerçek bir sürücü
/// bulabilmesi için framework'e gömülen MoltenVK'nın ICD manifestini Vulkan
/// yükleyicisine tanıtır. Kullanıcı ortamda zaten bir ICD tanımladıysa
/// dokunulmaz; manifest yoksa (test/CLI ortamı) sessizce geçilir.
#[cfg(target_os = "macos")]
fn configure_bundled_vulkan_driver() {
    if std::env::var_os("VK_ICD_FILENAMES").is_some() {
        return;
    }
    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    // <App>.app/Contents/MacOS/<exe> -> Contents/Frameworks/Mpv.framework/...
    let Some(macos_dir) = exe.parent() else {
        return;
    };
    let manifest = macos_dir.join(
        "../Frameworks/Mpv.framework/Versions/A/Frameworks/MoltenVK_icd.json",
    );
    if manifest.exists() {
        std::env::set_var("VK_ICD_FILENAMES", &manifest);
    }
}

#[cfg(not(target_os = "macos"))]
fn configure_bundled_vulkan_driver() {}
