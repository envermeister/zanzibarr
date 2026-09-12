# AGENTS.md — zanzibarr

**Living context document for every AI coding agent (Kimi, Claude, ChatGPT/Codex, …) that works on this repository.**

> ## Agent protocol — read first
> 1. Read this file **fully** before touching any code, then follow the onboarding order in §10.
> 2. **Keep this file alive.** At the end of every work session, before handing off: update §6 (Current state), §7 (Known issues / watch list), §8 (Roadmap) and append a dated entry to §9 (History). This file is the project's memory across different AI tools and sessions — if you skip the update, the next agent starts blind.
> 3. Obey the standing rules in §4. Each one was earned through a real production bug.

---

## 1. Project snapshot

- **zanzibarr** streams video from Usenet NZBs **without downloading**: seekable playback straight from NNTP segments, through a local range-aware HTTP server, into libmpv.
- Repo: <https://github.com/envermeister/zanzibarr> (public) · Site: <https://zanzibarr.app> (GitHub Pages, served from `docs/`, download links point at `releases/latest`)
- Local working copy: `~/Downloads/USENET/Zanzibarr` (renamed 2026-09-08; formerly `~/Downloads/CodexGPT/UseNews`). Sibling fork: **Usetopia** at `~/Downloads/USENET/Usetopia` (repo `envermeister/usetopia`) — a separate app developed with Claude/ChatGPT; never touch it during zanzibarr work.
- Current release: **v1.5** (`pubspec.yaml` → `version: 1.5.0+6`). `main` == release — see §6.
- Platforms: **macOS** (arm64, signed), **Windows**, **Android** (phone + Android TV leanback), **Linux** (new), **iOS** (unsigned package; no TestFlight yet). Web is intentionally out of scope (no raw NNTP in browsers).
- The owner communicates in **Turkish** → always reply in Turkish. Repo artifacts (code comments, docs, release notes) in **English**. Commit messages: **Turkish conventional commits** (`feat(engine): …`, `fix(android): …`).
- Donations: buymeacoffee.com/envermeister + ko-fi.com/envermeister (referenced in README/site only).

## 2. Architecture

- **UI:** Flutter (one codebase, no Electron). Entry `lib/main.dart`.
- **Engine:** Rust, bridged via `flutter_rust_bridge` (FRB). Crate root `rust/`, FRB glue generated into `lib/src/rust/`. After changing any `rust/src/api/*.rs` signature, regenerate with `flutter_rust_bridge_codegen generate`.
- **Player:** `media_kit` / libmpv, with **custom-built libmpv 0.41 + FFmpeg 8.1.2 + libplacebo** (TrueHD/Atmos, DTS-HD MA, AV1, Dolby Vision Profile 5). Android build produced in the separate repo `envermeister/libmpv-android-video-build` (local: `~/Downloads/USENET/libmpv-android-video-build`); vendored into `vendor/media_kit_libs_*_video/`.

```
 .nzb ─▶ NZB parser ─▶ segment map (yEnc begin/end)        rust/src/engine/nzb.rs, yenc.rs
                          │
             NNTP pool (TLS, pipelined, semaphore)          nntp/connection.rs, nntp/pool.rs
                          │
         fetch → yEnc decode → CRC32 verify                 locator.rs, seekable_decode.rs
                          │
   archive layer (RAR4/RAR5, 7z STORE/LZMA/AES,             archive.rs, rar.rs, rarcrypt.rs,
   compressed RAR via vendored libunrar)                    sevenzip.rs, rarcompressed.rs
                          │
   PAR2 verify + Reed-Solomon repair overlay                par2.rs, repair.rs
                          │
        localhost HTTP server (Range requests)              http.rs, server.rs
                          │
                 libmpv / media_kit                         lib/player/*
```

Key directories:

- `rust/src/engine/` — the whole streaming engine (see map above). `rust/src/api/` — FRB-exposed API surface (`streaming.rs`, `search.rs`, `repair.rs`, `simple.rs`).
- `lib/player/` — player screen, controls (`gyuni_player_controls.dart`), keyboard/remote handling, Smart Canvas, subtitle overlay, PiP, media prefs, playback history ("continue watching").
- `lib/settings/` — provider (NNTP) settings, indexer settings, UI prefs. `lib/search/` — Newznab search UI. `lib/cast/` — Chromecast/AirPlay discovery + session control (`dart_cast`). `lib/update/update_service.dart` — OTA update check. `lib/l10n/` — 14 locales (en default, tr, es, de, fr, pt, it, ru, zh, ja, ko, hi, ar, fa; ar/fa RTL).
- `vendor/` — `unrar-rs` + `unrar-sys` (**patched fork**, see §5), `media_kit_libs_android_video`, `media_kit_libs_macos_video`.
- `rust_builder/` — cargokit bridge. `tools/` — `zanzibarr-cli` (NNTP/keychain CLI), asset scripts.
- `docs/` — website (`index.html`, Vue via CDN), `docs/releases/vX.Y.md` (release notes, referenced by CI `body_path`), `docs/screenshots/`.
- `.github/workflows/` — `android|windows|linux|ios-build.yml` (`workflow_dispatch` + reusable `workflow_call`) and `release.yml` (see §5).

## 3. Provider, indexer, accounts

- Provider of record: **Easynews**, `secure-eu.news.easynews.com:563` (TLS). Connection limit configured to 60 — plan support for that number was never verified; lower if auth/throttle errors appear.
- NNTP engine (`:563`) and the Easynews **web search API** are separate code paths; web API integration is still on the roadmap.
- Indexer: any **Newznab-compatible** one (developed against Miatrix): `?t=caps` discovery → search → release-name parser (resolution/codec/HDR/audio/group) → NZB straight into the player. Cross-indexer dedup is still open.
- Metadata (TMDB + OMDb) is planned, not implemented.

## 4. Standing rules (non-negotiable)

1. **Secrets:** never in code, tests, files, CLI args, logs or `Debug` output. Credentials live only in the OS keychain (`flutter_secure_storage` in-app, `keyring` crate in the CLI, `rpassword` prompt). Test fixtures may use only the placeholder password `TESTPASS123`.
2. **Seek offsets come only from decoded yEnc `begin/end`** (`YencPart` / `record_part`). NZB `bytes` (encoded article size) is used for download planning/progress only — never for offsets.
3. **Lazy streaming:** serve segment-by-segment (`locator.decoded_span`); when the player pauses, network activity must stop. Never pre-fetch a whole open-ended range.
4. **LAN exposure is token-gated:** the engine's second listener (`bind_lan`, for casting) only serves paths under `/cast/<128-bit-token>/`; loopback stays unauthenticated. Never serve LAN requests without the token check.
5. **Test discipline:** every engine module is proven with offline unit tests before integration. Before calling any work done, the full gate must pass (§5). Fixture archives live in `rust/tests/fixtures/`.
6. **Minimal diffs**, match surrounding style; no speculative refactors. Don't touch unrelated files.
7. **Update this file** at the end of the session (see protocol at top).

## 5. Build, test, release

Verification gate (run all four, in order):

```bash
cd rust && cargo test                      # ~223 tests (run to confirm current count)
cd rust && cargo clippy --all-targets -- -D warnings
flutter analyze lib test
flutter test                               # ~148 tests
```

Release pipeline (v1.4+):

1. Write `docs/releases/vX.Y.md` (English release notes — CI uses it as `body_path`).
2. Bump `pubspec.yaml` version, commit, `git tag vX.Y`, `git push --tags`.
3. `release.yml` builds Windows / Android / Linux / iOS via the reusable `*-build.yml` workflows and publishes assets with `softprops/action-gh-release`.
4. **macOS asset is built locally** (signing requires the local keychain — paid dev cert, team `8665FDLXA6`, `keychain-access-groups` entitlement; ad-hoc signing fails with `-34018`) and uploaded manually: `gh release upload vX.Y dist/macos/zanzibarr-macos-arm64.zip`.
5. Sync `docs/index.html` (site) if features/roadmap changed — download URLs are `releases/latest`-based, so no link edits needed.

Debug hooks (developer-only, env vars): `ZANZIBARR_DEBUG_NZB=/path/to.nzb` (open NZB directly at startup), `ZANZIBARR_DEBUG_PROBE=1` (dump video params + audio tracks to stdout).

## 6. Current state (updated 2026-09-12)

**v1.5 shipped** (tag `v1.5`, release notes `docs/releases/v1.5.md`). `main` is ahead with **Chromecast/AirPlay casting** (v1.6 candidate, unreleased):

- `dart_cast` (MIT, pure Dart) added for discovery + remote control; Chromecast primary, AirPlay best-effort (dart_cast's AirPlay video path is unverified on real hardware; we have no Apple TV to test).
- Engine: `server.rs` gains `bind_lan` (0.0.0.0) + per-session 128-bit path token — LAN listener requires `/cast/<token>/` prefix (403 otherwise), loopback behavior unchanged. `StreamInfo.cast_url` carries the LAN URL (empty if LAN bind failed). dart_cast's MediaProxy is bypassed via a `_DirectUrlTransformer` — receivers fetch straight from the engine's range server.
- Flutter: `lib/cast/` (`cast_service.dart` `CastController` interface + `AppCastService`, `cast_device_picker.dart` dialog); cast button in the player top toolbar next to PiP; local playback pauses while casting, play/pause/seek/volume mirror to the receiver, cast position feeds `_position` so continue-watching stays correct; disconnect re-syncs the local player to the cast position.
- Platform plumbing: Android manifest gains `ACCESS_WIFI_STATE` / `CHANGE_WIFI_MULTICAST_STATE` / `ACCESS_NETWORK_STATE` / `NEARBY_WIFI_DEVICES`; iOS + macOS `Info.plist` gain `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_googlecast._tcp`, `_airplay._tcp`); macOS entitlements already had `network.server`.
- i18n: `cast*` keys added to all 14 locales (en+tr translated, rest English fallback).

Gate after the change: 223 Rust tests, clippy clean, flutter analyze clean, 148 Flutter tests. **Pending: on-device test** (Homatics Android TV box has Chromecast built-in) before any v1.6 cut.

## 7. Known issues / watch list

- *Pillarbox report* on `The.Runner.2026.1080p...` (16:9 content, bars on sides) — fit/fill button added in `3713b31`; if bars persist on a 16:9 TV, that's a render bug → get on-device logcat.
- Owner's Mac keychain still holds a stale `usenews` entry (old password) — CLI gets 502; the release app reads its own `zanzibarr` entries and is unaffected.
- Easynews 60-connection limit unverified (§3).

## 8. Roadmap (priority order, status)

| # | Item | Status |
|---|------|--------|
| 1 | Easynews web search API (separate code path) | open |
| 2 | Cross-indexer dedup | open |
| 3 | TMDB + OMDb metadata | open |
| 4 | iOS TestFlight distribution | open |
| 5 | OpenSubtitles integration | open |
| 6 | Chromecast / AirPlay | implemented on `main` — awaiting on-device test (§6) |
| 7 | HDR10+ detection | open |

Done since v1.0: Newznab indexer search (v1.1-era), RAR4/RAR5 STORE, split 7z STORE/LZMA + AES-256, PAR2 Reed-Solomon repair, custom libmpv (TrueHD/DTS-HD/AV1), DV Profile 5 on macOS+Android+Windows+Linux, Android TV leanback + remote, 14 languages, dark/light themes, OTA updates, compressed RAR seek, subtitle color, Smart Canvas, continue-watching.

## 9. History (append dated entries at the bottom — newest last)

- **v1.0 (2026-07)** — Phase 0–2: FRB skeleton; NZB parser + yEnc decoder; NNTP pool (rustls/tokio); segment↔byte-range locator from yEnc begin/end; lazy localhost range server; media_kit playback+seek proven against real Easynews. Newznab search, 14 locales, dark/light, GitHub Pages site, Reddit launch.
- **v1.1** — RAR5/RAR4 multi-volume STORE as one virtual seekable file; split 7z STORE + AES-256; PAR2 verify+repair (Reed-Solomon, byte-exact vs par2cmdline); Android TV leanback; Smart Canvas.
- **v1.2** — Dolby Vision Profile 5 fixed on Android: custom mpv 0.41 + FFmpeg 8.1.2 + libplacebo build (repo `libmpv-android-video-build`), GPU reshaping with 8-bit path that survives drivers lacking 16-bit linear sampling (Samsung Xclipse) and Adreno. End of the pink/green saga.
- **v1.3** — embedded-subtitle visibility fix on Android; TV remote key handling; released to all platforms.
- **v1.4 (2026-08)** — continue-watching history, subtitle color, DV Profile 5 on Windows/Linux, first Linux + iOS (unsigned) packages, tag-push CI release pipeline (`release.yml` + reusable builders).
- **v1.5 (2026-09-08)** — OTA updates (GitHub Releases check, in-app install on Android); compressed RAR stream-seek (vendored libunrar, decode-ahead); Android TV remote focus fix; Android silent-start fix + fit/fill toggle; `libc++_shared` APK packaging fix (friend-tested); debug hooks. README test badge corrected (220 Rust + 141 Flutter).
- **2026-09-08** — Cross-AI continuity: added `AGENTS.md` (this file), `CLAUDE.md`, `docs/HANDOVER_PROMPT.md`. Local layout: project moved to `~/Downloads/USENET/Zanzibarr` (parent `CodexGPT` → `USENET`, `UseNews` → `Zanzibarr`). Forked 1:1 into **Usetopia** (`~/Downloads/USENET/Usetopia`, repo `envermeister/usetopia`) — developed as a separate app with Claude/ChatGPT; zanzibarr continues here with Kimi.
- **2026-09-12 (unreleased, main)** — Chromecast/AirPlay casting: engine `bind_lan` + token-gated `/cast/<token>/` prefix, `StreamInfo.cast_url`; `dart_cast` for discovery/control with a direct-URL transformer (receiver fetches straight from the engine range server — no MediaProxy hop); cast button in the player toolbar, control mirroring, position sync into continue-watching; platform permissions for Android/iOS/macOS. Gate: 223 Rust + 148 Flutter. Awaiting on-device test (Homatics box).

### Key technical decisions (the *why* — don't relitigate without cause)

- **Rust + FRB, on-device, no server:** mature crate ecosystem (NNTP/yEnc/RAR/7z/PAR2), clean FFI, no runtime. NZBDav (C#, MIT) is reference blueprint only — algorithms ported, code never copied.
- **STORE first, archives later:** end-to-end playback was proven on STORE releases before any archive work; RAR/7z/AES/PAR2 came in phased afterwards. Keep this discipline for new media features.
- **Custom libmpv builds:** stock media_kit libs lack TrueHD/DTS-HD and botch DV P5 (pink/green). P5 is reshaped on GPU via libplacebo; HDR10-based profiles ride the natural decoder path. Never "fix" DV by forcing SDR silently.
- **Vendored unrar fork** (`vendor/unrar-rs`, `vendor/unrar-sys`): upstream unrar 0.5.8 + patches — `UCM_CHANGEVOLUMEW` handler must not touch `p1` (heisenbug SIGABRT), `USE_LUTIMES` off on Android, per-target link flags (`c++_shared` / `c++` / `stdc++`), `-fno-stack-check` on Apple targets. Prefer patching the fork over replacing the approach.
- **Android C++ runtime:** engine `.so` links `libc++_shared`, which must be *packaged into the APK* (`copyLibcxxShared` task) — static linking was tried and abandoned (`--undefined-version` hacks in CI).
- **OTA via GitHub Releases:** update check reads latest release; Android installs in-app through a FileProvider content URI; desktop links out.

## 10. Onboarding order for a fresh agent

1. This file.
2. `README.md` — product surface and feature wording.
3. `docs/releases/v1.4.md` (and any newer `v*.md`) — what shipped last.
4. `rust/src/engine/mod.rs` → `server.rs` / `http.rs` / `locator.rs` — the streaming spine.
5. `lib/main.dart` → `lib/player/player_screen.dart` — app shell and player wiring.
6. `pubspec.yaml`, `rust/Cargo.toml` — dependency ground truth (never assume a package exists).
7. `.github/workflows/release.yml` — how releases actually happen.

Working with the owner: replies in Turkish; test feedback arrives as screenshots/screen recordings from friends' devices (Samsung/Poco phones, Homatics Android TV box, Windows PC); test NZBs live under `~/Downloads/USENET/` (parent of this repo); use the §5 debug hooks to reproduce quickly. Commit + push is pre-authorized (Turkish conventional commits) — still never commit secrets, build outputs or the `kimi-export-*` session files.
