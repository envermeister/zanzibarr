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

## Geçici CLI (uygulama çalışana dek)

```sh
cd tools/usenews-cli
cargo run -q -- setup   # kimlik bilgilerini sorar (parola echo'suz), Keychain'e yazar
cargo run -q -- show    # kayıtları gösterir; parolayı asla yazmaz
cargo run -q -- check   # TLS + AUTHINFO + DATE ile bağlantı sınaması
cargo run -q -- fetch '<message-id>'  # tek article çek + yEnc çöz
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
- [ ] **Faz 1** — Motorun dikey dilimi (yalnız STORE içerik):
  - [x] NZB parser (`rust/src/engine/nzb.rs`) — XML → dosyalar → segmentler
  - [x] yEnc decoder (`rust/src/engine/yenc.rs`) — tek parça + multipart + CRC32
  - [x] NNTP altyapısı (`rust/src/engine/nntp/`) — TLS :563, komut/yanıt,
        AUTHINFO, havuz; sahte sunucuyla test edildi (gerçek sunucu doğrulaması
        kullanıcı kimliğiyle yapılacak)
  - [ ] Segment ↔ byte-range eşleyici
  - [ ] Localhost HTTP server (range) + media_kit oynatma + seek
- [ ] **Faz 2+** — Newznab/Easynews arama; RAR/7z/AES stream; PAR2
      healthcheck+repair (NZBDav MIT kaynağı algoritma referansı, kod
      kopyalanmaz).
