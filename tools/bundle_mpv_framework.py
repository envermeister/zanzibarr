#!/usr/bin/env python3
"""Homebrew libmpv'yi (tam FFmpeg ile) kendi içinde taşınabilir bir
Mpv.xcframework'e paketler.

Neden: media_kit_libs_macos_video'nun paketlediği FFmpeg minimal derlemedir;
TrueHD gibi çözücüler kapalıdır. Bu betik /opt/homebrew'daki libmpv + tam
FFmpeg (ve tüm dolaylı homebrew bağımlılıklarını) framework içine gömer ve
install_name'leri @rpath'e çevirir. Böylece uygulama paketi kendi kendine
yeterli olur.

Kullanım: python3 tools/bundle_mpv_framework.py
Girdi:    /opt/homebrew/lib/libmpv.2.dylib (+ homebrew bağımlılıkları)
Çıktı:    vendor/media_kit_libs_macos_video/macos/Frameworks/Mpv.xcframework
"""

import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC = "/opt/homebrew/lib/libmpv.2.dylib"
FW_DIR = (
    REPO_ROOT
    / "vendor/media_kit_libs_macos_video/macos/Frameworks/Mpv.xcframework/macos-arm64/Mpv.framework"
)
NESTED = FW_DIR / "Versions/A/Frameworks"
SYSTEM_PREFIXES = ("/usr/lib", "/System/")


def run(cmd, tolerate=False):
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0 and not tolerate:
        raise RuntimeError(f"komut başarısız: {' '.join(cmd)}\n{proc.stderr}")


def homebrew_refs(dylib, extra_lib_dirs=()):
    """otool -L çıktısından homebrew'e ait bağımlılık yollarını döndürür.

    Homebrew'de bazı dylib'ler birbirlerine @rpath/<ad> ile bağlanır; bunlar
    /opt/homebrew/lib altında çözülür. extra_lib_dirs verilirse @rpath
    referansları önce o dizinlerde aranır (özel ffmpeg derlemesinin kendi
    lib dizini gibi). Çıktı (referans dizesi, kopyalanacak gerçek dosya)
    çiftleridir.
    """
    out = subprocess.run(
        ["otool", "-L", str(dylib)], capture_output=True, text=True
    ).stdout
    refs = []
    for line in out.splitlines()[1:]:
        ref = line.strip().split(" ")[0]
        if not ref or ref.startswith(SYSTEM_PREFIXES):
            continue
        if ref.startswith("@rpath/"):
            for lib_dir in (*extra_lib_dirs, "/opt/homebrew/lib"):
                real = os.path.realpath(os.path.join(lib_dir, ref[7:]))
                if os.path.exists(real):
                    refs.append((ref, real))
                    break
        elif ref.startswith("/opt/homebrew"):
            refs.append((ref, os.path.realpath(ref)))
    return refs


def main():
    if not os.path.exists(SRC):
        sys.exit(f"kaynak yok: {SRC} (brew install mpv gerekli)")

    # Bağımlılık grafiğini BFS ile topla: referans dizesi -> gerçek dosya.
    closure = {}
    queue = [SRC]
    while queue:
        current = queue.pop(0)
        for ref, real in homebrew_refs(current):
            if ref == os.path.realpath(SRC) or ref.endswith("libmpv.2.dylib"):
                continue  # libmpv'nin kendi kimliği
            if ref in closure:
                continue
            if not os.path.exists(real):
                sys.exit(f"bağımlılık bulunamadı: {ref} -> {real}")
            closure[ref] = real
            queue.append(real)

    print(f"{len(closure)} homebrew bağımlılığı bulundu")

    # Tüm xcframework'ü temizle: iç framework yanında dilim dizininde kalan
    # eski Info.plist gibi artıklar CocoaPods doğrulamasını bozmasın.
    xcframework = FW_DIR.parent.parent
    if xcframework.exists():
        shutil.rmtree(xcframework)
    NESTED.mkdir(parents=True)

    # 1) Bağımlılıkları framework içine kopyala ve yeniden adlandır.
    for ref, real in sorted(closure.items()):
        name = os.path.basename(ref)
        dest = NESTED / name
        shutil.copyfile(real, dest)
        run(["chmod", "u+w", str(dest)])
        run(["install_name_tool", "-id", f"@rpath/{name}", str(dest)])
        for dep, dep_real in homebrew_refs(real):
            if dep.startswith("@rpath/"):
                continue  # zaten @rpath biçiminde; kardeş dosyaya işaret eder
            run(
                [
                    "install_name_tool",
                    "-change",
                    dep,
                    f"@rpath/{os.path.basename(dep)}",
                    str(dest),
                ]
            )
        run(["install_name_tool", "-add_rpath", "@loader_path", str(dest)], tolerate=True)
        run(["codesign", "--force", "--sign", "-", str(dest)])

    # 2) libmpv'nin kendisini framework köküne kopyala.
    mpv_dest = FW_DIR / "Versions/A/Mpv"
    shutil.copyfile(os.path.realpath(SRC), mpv_dest)
    run(["chmod", "u+w", str(mpv_dest)])
    run(
        [
            "install_name_tool",
            "-id",
            "@rpath/Mpv.framework/Versions/A/Mpv",
            str(mpv_dest),
        ]
    )
    for dep, dep_real in homebrew_refs(os.path.realpath(SRC)):
        if dep.endswith("libmpv.2.dylib"):
            continue
        if dep.startswith("@rpath/"):
            continue
        run(
            [
                "install_name_tool",
                "-change",
                dep,
                f"@rpath/{os.path.basename(dep)}",
                str(mpv_dest),
            ]
        )
    run(
        ["install_name_tool", "-add_rpath", "@loader_path/Frameworks", str(mpv_dest)],
        tolerate=True,
    )
    run(["codesign", "--force", "--sign", "-", str(mpv_dest)])

    # 3) Sembolik bağlar ve Info.plist'ler.
    os.symlink("A", FW_DIR / "Versions/Current")
    os.symlink("Versions/Current/Mpv", FW_DIR / "Mpv")
    os.symlink("Versions/Current/Frameworks", FW_DIR / "Frameworks")
    resources = FW_DIR / "Versions/A/Resources"
    resources.mkdir(exist_ok=True)
    plistlib.dump(
        {
            "CFBundleExecutable": "Mpv",
            "CFBundleIdentifier": "io.mpv.Mpv",
            "CFBundlePackageType": "FMWK",
            "CFBundleShortVersionString": "0.41.0",
            "CFBundleVersion": "2.0.0",
            "CFBundleInfoDictionaryVersion": "6.0",
        },
        open(resources / "Info.plist", "wb"),
    )
    plistlib.dump(
        {
            "AvailableLibraries": [
                {
                    "BinaryPath": "Mpv.framework/Versions/A/Mpv",
                    "LibraryIdentifier": "macos-arm64",
                    "LibraryPath": "Mpv.framework",
                    "SupportedArchitectures": ["arm64"],
                    "SupportedPlatform": "macos",
                }
            ],
            "CFBundlePackageType": "XFWK",
            "XCFrameworkFormatVersion": "1.0",
        },
        open(FW_DIR.parent.parent / "Info.plist", "wb"),
    )

    total = sum(f.stat().st_size for f in FW_DIR.rglob("*") if f.is_file())
    print(f"tamam: {FW_DIR} ({total / 1024 / 1024:.1f} MB)")


def rewrite_names(dylib):
    """Bir dylib'in homebrew/özel yollarını @rpath'e çevirir ve imzalar."""
    out = subprocess.run(
        ["otool", "-L", str(dylib)], capture_output=True, text=True
    ).stdout
    for line in out.splitlines()[1:]:
        ref = line.strip().split(" ")[0]
        if not ref or ref.startswith(SYSTEM_PREFIXES) or ref.startswith("@rpath/"):
            continue
        run(
            [
                "install_name_tool",
                "-change",
                ref,
                f"@rpath/{os.path.basename(ref)}",
                str(dylib),
            ],
            tolerate=True,
        )
    run(["install_name_tool", "-add_rpath", "@loader_path", str(dylib)], tolerate=True)
    run(["codesign", "--force", "--sign", "-", str(dylib)])


def override_ffmpeg(prefix):
    """FFMPEG_PREFIX ile verilen özel derlemedeki libav* dylib'lerini
    framework'tekilerin üzerine yazar (örn. --enable-libplacebo'lu çatal)."""
    if not prefix:
        return
    names = [
        "libavcodec.62.dylib",
        "libavdevice.62.dylib",
        "libavfilter.11.dylib",
        "libavformat.62.dylib",
        "libavutil.60.dylib",
        "libswresample.6.dylib",
        "libswscale.9.dylib",
    ]
    for name in names:
        src = os.path.join(prefix, "lib", name)
        if not os.path.exists(src):
            sys.exit(f"özel ffmpeg eksik: {src}")
        dest = NESTED / name
        shutil.copyfile(os.path.realpath(src), dest)
        run(["chmod", "u+w", str(dest)])
        run(["install_name_tool", "-id", f"@rpath/{name}", str(dest)])
        rewrite_names(dest)
    print(f"özel ffmpeg gömüldü: {prefix}")

    # Özel derleme, homebrew mpv'nin ffmpeg'inden farklı özelliklerle
    # derlenmiş olabilir ve yeni bağımlılıklar getirebilir (örn. x11grab'ın
    # libxcb/libX11 zinciri). Framework'te karşılığı olmayan her homebrew
    # referansını BFS ile kapatla; yoksa dyld ilk eksikte uygulamayı düşürür.
    prefix_lib = os.path.join(prefix, "lib")
    queue = [NESTED / name for name in names]
    while queue:
        current = queue.pop(0)
        for ref, real in homebrew_refs(current, (prefix_lib,)):
            dep_name = os.path.basename(ref)
            dest = NESTED / dep_name
            if dest.exists():
                continue
            shutil.copyfile(real, dest)
            run(["chmod", "u+w", str(dest)])
            run(["install_name_tool", "-id", f"@rpath/{dep_name}", str(dest)])
            rewrite_names(dest)
            queue.append(dest)
            print(f"ek bağımlılık gömüldü: {dep_name}")


def bundle_moltenvk():
    """MoltenVK'yı ve ICD manifestini framework'e gömer.

    vf_libplacebo gibi Vulkan zorunlu filtreler uygulama içinde gerçek bir
    sürücü bulamaz; MoltenVK, Metal üzerinden Vulkan sağlar. Manifest,
    dylib ile aynı dizinde durur ve göreli yolla ona işaret eder; çalışma
    zamanında VK_ICD_FILENAMES bu dosyaya yönlendirilir (Rust tarafı).
    """
    src = os.path.realpath("/opt/homebrew/lib/libMoltenVK.dylib")
    if not os.path.exists(src):
        sys.exit("libMoltenVK.dylib yok (brew install molten-vk gerekli)")
    dest = NESTED / "libMoltenVK.dylib"
    shutil.copyfile(src, dest)
    run(["chmod", "u+w", str(dest)])
    run(["install_name_tool", "-id", "@rpath/libMoltenVK.dylib", str(dest)])
    rewrite_names(dest)
    (NESTED / "MoltenVK_icd.json").write_text(
        '{\n'
        '    "file_format_version" : "1.0.0",\n'
        '    "ICD": {\n'
        '        "library_path": "./libMoltenVK.dylib",\n'
        '        "api_version" : "1.4.0",\n'
        '        "is_portability_driver" : true\n'
        "    }\n"
        "}\n"
    )
    print("MoltenVK + ICD manifesti gömüldü")


if __name__ == "__main__":
    main()
    override_ffmpeg(os.environ.get("FFMPEG_PREFIX"))
    bundle_moltenvk()
