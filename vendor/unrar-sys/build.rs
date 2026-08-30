fn main() {
    // zanzibarr yaması: hedefe göre link bayrakları. Not: build.rs'te cfg!
    // makrosu HOST'a bakar; çapraz derlemede hedef CARGO_CFG_TARGET_OS'tan
    // okunur (aksi halde Android'e -lpthread gidip lld kırılır — Android'de
    // pthread libc'nin parçasıdır).
    //
    // Ayrıca bu crate `.cpp_link_stdlib(None)` ile cc'nin otomatik C++
    // stdlib bayrağını kapatır (windows-gnu uyumu); bu yüzden stdlib'i hedefe
    // göre kendimiz bağlarız: Apple'da c++, Android'de c++_shared,
    // gnu'da stdc++. MSVC zaten önceden çalışıyordu; dokunulmaz.
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    match target_os.as_str() {
        "windows" => {
            println!("cargo:rustc-flags=-lpowrprof");
            println!("cargo:rustc-link-lib=shell32");
            if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("gnu") {
                println!("cargo:rustc-link-lib=pthread");
            }
        }
        "android" => {
            println!("cargo:rustc-link-lib=dylib=c++_shared");
        }
        "macos" | "ios" | "tvos" | "watchos" | "visionos" => {
            println!("cargo:rustc-link-lib=c++");
        }
        _ => {
            println!("cargo:rustc-link-lib=pthread");
            println!("cargo:rustc-link-lib=stdc++");
        }
    }
    let files: Vec<String> = [
        "strlist",
        "strfn",
        "pathfn",
        "smallfn",
        "global",
        "file",
        "filefn",
        "filcreat",
        "archive",
        "arcread",
        "unicode",
        "system",
        #[cfg(windows)]
        "isnt",
        "crypt",
        "crc",
        "rawread",
        "encname",
        "match",
        "timefn",
        "rdwrfn",
        "consio",
        "options",
        "errhnd",
        "rarvm",
        "secpassword",
        "rijndael",
        "getbits",
        "sha1",
        "sha256",
        "blake2s",
        "hash",
        "extinfo",
        "extract",
        "volume",
        "list",
        "find",
        "unpack",
        "headers",
        "threadpool",
        "rs16",
        "cmddata",
        "ui",
        "filestr",
        "scantree",
        "dll",
        "qopen",
    ].iter().map(|&s| format!("vendor/unrar/{s}.cpp")).collect();
    cc::Build::new()
        .cpp(true) // Switch to C++ library compilation.
        .opt_level(2)
        .std("c++14")
        // by default cc crate tries to link against dynamic stdlib, which causes problems on windows-gnu target
        .cpp_link_stdlib(None)
        .warnings(false)
        .extra_warnings(false)
        .flag_if_supported("-stdlib=libc++")
        .flag_if_supported("-fPIC")
        .flag_if_supported("-Wno-switch")
        .flag_if_supported("-Wno-parentheses")
        .flag_if_supported("-Wno-macro-redefined")
        .flag_if_supported("-Wno-dangling-else")
        .flag_if_supported("-Wno-logical-op-parentheses")
        .flag_if_supported("-Wno-unused-parameter")
        .flag_if_supported("-Wno-unused-variable")
        .flag_if_supported("-Wno-unused-function")
        .flag_if_supported("-Wno-missing-braces")
        .flag_if_supported("-Wno-unknown-pragmas")
        .flag_if_supported("-Wno-deprecated-declarations")
        .define("_FILE_OFFSET_BITS", Some("64"))
        .define("_LARGEFILE_SOURCE", None)
        .define("RAR_SMP", None)
        .define("RARDLL", None)
        // zanzibarr yaması: arm64 Darwin'de clang büyük stack framelerine
        // ___chkstk_darwin üretir; o sembol libSystem'a ancak iOS 14'ten
        // girer, rustc'nin link tabanı 10.0 olduğundan çözülemez. Stack
        // probing'i kapatmak sembolü hiç üretmez ve min sürümü korumaz.
        .flag_if_supported("-fno-stack-check")
        .files(&files)
        .compile("libunrar.a");
}
