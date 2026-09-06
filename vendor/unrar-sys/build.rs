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
            // Paylaşımlı libc++ APK'ya ayrı .so paketlemeyi gerektirir
            // (yoksa dlopen "libc++_shared.so not found" ile düşer). Motorun
            // tek C++ bileşeni unrar olduğundan statik bağlarız; NDK'nın
            // statik kitaplık dizini sürüme göre değiştiğinden iki bilinen
            // düzeni de dener.
            println!("cargo:rustc-link-lib=static=c++_static");
            println!("cargo:rustc-link-lib=static=c++abi");
            if let Ok(ndk) = std::env::var("ANDROID_NDK_HOME") {
                let triple = match std::env::var("CARGO_CFG_TARGET_ARCH").as_deref() {
                    Ok("aarch64") => "aarch64-linux-android",
                    Ok("arm") => "arm-linux-androideabi",
                    Ok("x86_64") => "x86_64-linux-android",
                    Ok("x86") => "i686-linux-android",
                    _ => "",
                };
                if !triple.is_empty() {
                    let mut candidates: Vec<String> = Vec::new();
                    // Klasik düzen (≤ r25): sources/cxx-stl/llvm-libc++/libs/<abi>
                    let abi = triple
                        .replace("aarch64-linux-android", "arm64-v8a")
                        .replace("arm-linux-androideabi", "armeabi-v7a")
                        .replace("x86_64-linux-android", "x86_64")
                        .replace("i686-linux-android", "x86");
                    candidates.push(format!(
                        "{ndk}/sources/cxx-stl/llvm-libc++/libs/{abi}"
                    ));
                    // Yeni düzen (r26+): toolchains/llvm/prebuilt/<host>/sysroot/usr/lib/<triple>
                    for host in ["linux-x86_64", "darwin-x86_64", "darwin-arm64", "windows-x86_64"] {
                        candidates.push(format!(
                            "{ndk}/toolchains/llvm/prebuilt/{host}/sysroot/usr/lib/{triple}"
                        ));
                    }
                    for dir in candidates {
                        if std::path::Path::new(&format!("{dir}/libc++_static.a")).exists() {
                            println!("cargo:rustc-link-search={dir}");
                            break;
                        }
                    }
                }
            }
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
