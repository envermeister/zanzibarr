# UseNews

Usenet'ten içeriği indirmeden, seek edilebilir şekilde oynatan cross-platform
uygulama. UI Flutter, ağır motor Rust; ikisi
[flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) ile bağlı.

## Mimari

```
[Flutter UI] ←flutter_rust_bridge→ [Rust çekirdek]
                                     ├── NNTP istemcisi (TLS, auth, bağlantı havuzu)
                                     ├── yEnc decoder (multipart, CRC32)
                                     ├── NZB parser (XML → dosyalar → segmentler)
                                     ├── Segment ↔ byte-range eşleyici (seek'in kalbi)
                                     ├── 7z çok-cilt sanal kaynağı (STORE + AES, şifreli başlık)
                                     └── Localhost HTTP server (media_kit'e range ile besler)
[media_kit player] ←HTTP range← localhost server
```

## Dizin yapısı

- `lib/` — Flutter UI (`lib/src/rust/` FRB tarafından üretilir, elle düzenlenmez)
- `rust/` — Rust çekirdek crate'i (`rust_lib_usenews`); motor `rust/src/engine/`
- `rust_builder/` — cargokit build köprüsü (FRB tarafından üretildi)
- `tools/usenews-cli/` — geçici geliştirme aracı (kimlik → Keychain, bağlantı sınama)
- `flutter_rust_bridge.yaml` — codegen yapılandırması

## Geliştirme

```sh
# Rust API'si (rust/src/api/) değişince binding'leri yeniden üret:
flutter_rust_bridge_codegen generate

# Testler (Rust dylib'ini host için derler, köprüyü gerçek kütüphaneyle test eder):
cargo build --manifest-path rust/Cargo.toml
flutter test

# Uygulama (macOS için tam Xcode gerekir):
flutter run -d macos
```

## Platformlar ve paketleme

Rust çekirdeği her platformda [cargokit](https://github.com/irondash/cargokit)
ile `flutter build` sırasında otomatik derlenir; ayrı bir Rust build adımı
gerekmez. TLS `rustls` (ring) olduğundan OpenSSL bağımlılığı yoktur.

| Platform | Komut | Ön koşullar |
|---|---|---|
| macOS | `flutter build macos` | Xcode + Apple ID (otomatik imza; takım `AppInfo.xcconfig`'te) |
| Windows | `flutter build windows` | Visual Studio (C++ workload) + Rust (MSVC toolchain) |
| Linux | `flutter build linux` | `clang cmake ninja-build libgtk-3-dev libmpv-dev mpv` |
| Android | `flutter build apk` / `appbundle` | Android Studio/SDK + NDK; `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android` |
| iOS | `flutter build ipa` | Xcode + imza; `rustup target add aarch64-apple-ios` |

Platform notları:

- **Android:** `INTERNET` izni ana manifest'te hazır. Kimlik deposu Keystore
  (flutter_secure_storage) — ek kurulum gerekmez.
- **iOS:** `Info.plist`'te `NSAllowsLocalNetworking` hazır (media_kit,
  localhost server'dan okur). İmza için kendi takımını seç.
- **macOS:** Sandbox + Keychain için gerçek geliştirici imzası gerekir
  (ad-hoc imzada Keychain `-34018` verir). `AppInfo.xcconfig`'teki
  `DEVELOPMENT_TEAM`'i kendi takımınla değiştir; ilk seferde
  `xcodebuild -allowProvisioningUpdates` profil üretir.
- **Windows/Linux:** media_kit, libmpv'yi Windows'ta paketle getirir;
  Linux'ta sistem `libmpv` kullanılır.

## Geçici CLI (uygulama çalışana dek)

```sh
cd tools/usenews-cli
cargo run -q -- setup   # kimlik bilgilerini sorar (parola echo'suz), Keychain'e yazar
cargo run -q -- show    # kayıtları gösterir; parolayı asla yazmaz
cargo run -q -- check   # TLS + AUTHINFO + DATE ile bağlantı sınaması
cargo run -q -- fetch '<message-id>'  # tek article çek + yEnc çöz
cargo run -q -- probe <nzb> [offset]  # eşleyiciyle seek kanıtı (gerçek veri)
cargo run -q -- serve <nzb> [port]    # localhost HTTP Range server (curl/media_kit)
cargo run -q -- clear   # kayıtları siler
```

Parola hiçbir zaman komut satırı argümanı, dosya veya test içeriği olmaz;
gizli prompt'tan doğrudan Keychain'e gider.

## Sır yönetimi

Sağlayıcı kimlik bilgileri yalnızca OS secure storage'da tutulur
(`flutter_secure_storage`: macOS/iOS Keychain, Android Keystore). Hiçbir sır
kaynak koda veya repoya yazılmaz; `.gitignore` olası yerel sır dosyalarını da
dışlar.

## Faz durumu

- [x] **Faz 0** — İskelet ve köprü kanıtı: FRB kurulu, Dart→Rust çağrısı test
      edilmiş, secure storage'lı sağlayıcı ayar ekranı hazır.
- [x] **Faz 1** — Motorun dikey dilimi (yalnız STORE içerik):
  - [x] NZB parser (`rust/src/engine/nzb.rs`) — XML → dosyalar → segmentler
  - [x] yEnc decoder (`rust/src/engine/yenc.rs`) — tek parça + multipart + CRC32
  - [x] NNTP altyapısı (`rust/src/engine/nntp/`) — TLS :563, komut/yanıt,
        AUTHINFO, havuz; sahte sunucuyla test edildi (gerçek sunucu doğrulaması
        kullanıcı kimliğiyle yapılacak)
  - [x] Segment ↔ byte-range eşleyici (`rust/src/engine/locator.rs`) —
        çözülmüş ofsetler yalnız yEnc begin/end'ten; gerçek Easynews
        verisiyle seek kanıtlandı (`usenews-cli probe`)
  - [x] Localhost HTTP Range server (`rust/src/engine/server.rs` +
        `nntp_source.rs`) — 200/206/416, `bytes=a-b`/`a-`/`-suffix`, header
        gövdeden önce; gerçek Easynews mkv'siyle `curl --range` ile baştan,
        ortadan (759M), açık-uçlu, dosya-sonu ve segment-sınırı kanıtlandı
  - [x] media_kit entegrasyonu (`lib/player/player_screen.dart` +
        `rust/src/api/streaming.rs`) — FRB `start_stream` server'ı başlatıp
        localhost URL döner; libmpv (media_kit motoru) HTTP üzerinden 30.
        dakikaya seek + HEVC decode kanıtlandı; uygulama gerçek pencerede
        sağlıklı açılıyor. Uygulama içinde oynatma için kimlik ayar
        ekranından bir kez girilir (flutter_secure_storage; CLI'den ayrı alan).
- [x] **7z çok-cilt akışı** (`rust/src/engine/sevenzip.rs`) — `.7z.001…`
      ciltleri sıralanıp sanal tek dosya olarak sunulur; STORE ve AES şifreli
      içerik (şifreli başlıklar dahil) byte-range bazlı, diske indirmeden
      çözülür. LZMA gibi sıkıştırmalı içerik desteklenmez; eksik cilt/segment
      açık hata verir. Bağlantı yaşam döngüsü sağlamlaştırıldı: cilt
      hazırlığı sınırlı eşzamanlılıkla ilerler, oturum iptali tüm
      HTTP/NNTP görevlerini kapatır, `502 Too many connections` parola
      hatasından ayrı raporlanır.
- [x] **Oynatıcı katmanı** (`lib/player/`) — sade, gerektiğinde beliren
      kontrol yerleşimi; Smart Canvas (oran sürükleme, letterbox giderme,
      dosya başına kayıt), ekran üstü altyazı kontrolleri (boyut/konum/sync),
      hız kontrolü, A-B döngüsü, kare kare ilerleme, zoom, dönemsel oynatma
      bilgisi, sağ tık menüsü, HDR tone-mapping profili, macOS/Windows PiP,
      macOS'ta başlıksız pencere.
- [ ] **Faz 2+** — Newznab/Easynews arama; RAR stream; PAR2
      healthcheck+repair; 7z içinde LZMA vb. sıkıştırmalı içerik (NZBDav MIT
      kaynağı algoritma referansı, kod kopyalanmaz).
