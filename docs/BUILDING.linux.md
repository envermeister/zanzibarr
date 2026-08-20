# Building zanzibarr on Ubuntu 24.04

> **Note:** Linux desktop is **not** an officially supported target (see the
> roadmap in `README.md`) — this is a community-verified "got it compiling"
> record, not a maintained platform. Thanks to **@sanderjo** for figuring it
> out and documenting it ([issue #2](https://github.com/envermeister/zanzibarr/issues/2)).

## Prerequisites

Install build tooling and the Linux desktop dependencies Flutter needs:

```bash
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev \
    libsecret-1-dev libmpv-dev
```

- `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev` — required by
  `flutter doctor` for the Linux desktop toolchain.
- `libsecret-1-dev` — needed by the `flutter_secure_storage_linux` plugin
  (credentials-in-keychain storage).
- `libmpv-dev` — needed by `media_kit_video`'s CMake target
  (`PkgConfig::mpv`). See caveat below.

Rust toolchain (`cargo`/`rustc`) via [rustup](https://rustup.rs/) — needed to
build the `rust/` engine crate.

Flutter SDK — not packaged for this project, install the official SDK
yourself:

```bash
mkdir -p ~/development && cd ~/development
git clone -b stable https://github.com/flutter/flutter.git
export PATH="$PATH:$HOME/development/flutter/bin"   # add to ~/.bashrc too
```

Run `flutter doctor -v` and confirm the "Linux toolchain" section is green
before building (the first run also downloads the Dart SDK/engine
artifacts, ~250 MB).

## Build process

Rust engine (`rust/`):

```bash
cd rust
cargo build
cargo test      # 200+ tests
```

Flutter app:

```bash
flutter pub get
flutter gen-l10n
flutter build linux --debug
```

Output binary: `build/linux/x64/debug/bundle/zanzibarr`.

Use `flutter build linux --release` for a release bundle once the debug
build is confirmed working.

## Caveats

- **Not an officially supported target.** Only macOS, Windows, Android and
  Android TV are built/tested by the project (per `README.md`'s roadmap,
  Linux is still unchecked). There's no vendored/pinned media library for
  Linux, so `media_kit` falls back to whatever `libmpv` your distro ships.
- **libmpv version mismatch.** The app is designed around a custom
  **libmpv 0.41 + FFmpeg 8.1** build (for the Dolby Vision Profile 5 /
  HDR10 tone-mapping pipeline described in the README). Ubuntu 24.04's
  `libmpv-dev` is an older stock build — the app compiles and links against
  it, but advanced HDR/Dolby Vision handling may not behave as documented,
  or may fail at runtime.
- **Android toolchain missing is expected/fine** if you're only building
  the Linux desktop target — `flutter doctor` will still report it as an
  issue; ignore it unless you're also targeting Android.
- **Stale CMake cache after a failed configure.** If `flutter build linux`
  fails partway through (e.g. a missing dev package interrupts the CMake
  configure step), the next run can pick up an incomplete
  `build/linux/x64/debug/CMakeCache.txt` and mis-set `CMAKE_INSTALL_PREFIX`
  to `/usr/local` (causing a `Permission denied` on install instead of
  writing into the build bundle). Fix by wiping the build dir and retrying:
  ```bash
  rm -rf build/linux
  flutter build linux --debug
  ```
- **`sudo apt install` needs a real TTY.** If you're driving this from a
  non-interactive shell (e.g. an agent's tool-call shell) without a pty,
  `sudo` can't prompt for a password and fails immediately — run apt
  installs from an actual terminal.
- Package resolution reports several dependencies have newer versions
  available than the pinned constraints allow (`flutter pub outdated` for
  details) — none blocked the build, left as-is to match the project's
  lockfile.
