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
