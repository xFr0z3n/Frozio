# LAYOUT: Frozio vs FrozenMusic

FrozenMusic (`github.com/xFr0z3n/FrozenMusic`) is the structural template. This file lists every deviation and why.

| FrozenMusic | Frozio | Why |
|---|---|---|
| `Source/`, `Source/Prefs/` | same | — |
| `layout/Library/Application Support/YTMusicUltimate.bundle` | `layout/Library/Application Support/Frozio.bundle` | Name. CI copies it into `Arpeggi.app/Frozio.bundle` |
| `YTMusicUltimate.plist` filter | `Frozio.plist` → `com.reillywilkinson.NaviMus` | Target app |
| `Resources/` (icon, depiction) | `Resources/` (logo, `AppIcons/cyan`, `AppIcons/white`) | Logo and app icons |
| `ARCHS = arm64` | `ARCHS = arm64` | Same. FROZIO_PROMPT asked for `arm64 arm64e`, but NaviMus has no arm64e slice (approved in Phase 0, Q9) |
| `TARGET = iphone:clang:16.5:13.0` | `TARGET = iphone:clang:latest:17.0` | NaviMus MinimumOSVersion is 17.0 (approved in Phase 0, Q9) |
| `Frozio_LOGOS_DEFAULT_GENERATOR` unset (MobileSubstrate) | `internal` | No hooking runtime until one is approved in Phase 2 |
| Bundled static libs (`Source/Utils/lib`, FFmpeg, MBProgressHUD) | none | Not needed |
| `.github/workflows/main.yml`: cyan inject, **unsigned**, draft release | `.github/workflows/build.yml`: insert_dylib inject, icon patch, **signed** with a temporary keychain and re-derived entitlements, verified, draft release | FROZIO_PROMPT §5 requires signing and verification. The draft release keeps the signed NaviMus IPA private to the repo owner |
| SDK from `theos/sdks` (16.5) | Xcode's iPhoneOS SDK linked into `$THEOS/sdks` | theos/sdks has nothing at or above 17.0 |
| — | `scripts/` (`patch_icons.py`, `derive_entitlements.py`) | CI helpers |
| — | `docs/` | Required by FROZIO_PROMPT §5 |
| — | `scripts/setup_mac.sh` | Local macOS toolchain check; links Xcode's SDK into Theos like CI |
| — | `Harness/` | Simulator host app for Frozio's UI. NaviMus is arm64-device-only, so it can't be run in the Simulator; not part of the tweak or CI |

## Local build (macOS)

The project moved from Windows to an x86_64 Mac on 2026-11-14. Homebrew no longer supports Intel Macs, so the CI toolchain is installed by hand:

| Tool | Source | Where |
|---|---|---|
| Theos | `theos/theos` at CI's `THEOS_REF` (`344ee59`) | `~/theos` (`THEOS` in `~/.zprofile`) |
| GNU make 4.4.1 | ftp.gnu.org source build | `/usr/local/bin/gmake`, `make` via `/usr/local/opt/make/libexec/gnubin` on `PATH` |
| ldid v2.1.5-procursus7 | ProcursusTeam/ldid release | `/usr/local/bin/ldid` |
| insert_dylib | Tyilo/insert_dylib at CI's `INSERT_DYLIB_REF` | `/usr/local/bin/insert_dylib` |
| ipsw 3.1.745 | blacktop/ipsw macOS x86_64 release (SHA-256 checked) | `/usr/local/bin/ipsw` |
| Xcode | App Store | `/Applications/Xcode.app` |
