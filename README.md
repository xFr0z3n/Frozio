<p align="center">
  <img src="Resources/logo.png" width="160" alt="Frozio logo">
</p>

<h1 align="center">Frozio</h1>

<p align="center">spoti.pw's features and Liquid Glass design, rebuilt for <b>NaviMus / Arpeggi</b> (Subsonic / Navidrome client).</p>

---

> **Status: Phase 1.** This is a no-op tweak plus the build, inject and sign pipeline. Frozio doesn't change anything in the app yet.

## What it is

- A Theos tweak injected into a sideloaded **NaviMus 1.6.1 (build 173)** IPA.
- It targets spoti.pw's **redesign** look (iOS 26 Liquid Glass, with material fallbacks on iOS 17–25), with every feature ungated.
- It's version-locked: on any other NaviMus build, Frozio installs nothing.

See `docs/PHASE0_REPORT.md`, `docs/FEATURE_MATRIX.md` and `docs/DESIGN_TOKENS.md`.

## Building an IPA

Run the **Build, inject, sign and release Frozio** workflow (Actions → Run workflow).

**By default it produces an unsigned IPA**, like FrozenMusic. Sign it with your own signer (Sideloadly, Feather, ESign, …).

**Optional:** to have CI sign it, set all five of these repository secrets:

| Secret | Content |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Your Apple Development/Distribution certificate as a base64 `.p12` |
| `P12_PASSWORD` | The `.p12` password |
| `PROVISIONING_PROFILE_BASE64` | A base64 `.mobileprovision` for `com.reillywilkinson.NaviMus` (or a wildcard App ID) |
| `TEAM_ID` | Your 10-character Team ID (must match the profile) |
| `KEYCHAIN_PASSWORD` | Any random string (temporary CI keychain) |

The IPA comes from one of two places (it is never committed):
- **Either** `ipa_url`, a direct download URL,
- **or** an asset uploaded to a **draft** release named `ipa-source` in this repo (drafts are visible only to you).

There is one **draft** release, `Frozio build <n>` (tag `frozio-build`). Every run replaces its IPA and renames it to the newest build, so the Releases page only ever shows the latest one.

## Developing on macOS

Needs full Xcode (App Store), then the CI toolchain locally: Theos at CI's `THEOS_REF`, GNU make ≥ 4, `ldid`, `insert_dylib`, `ipsw`, `gh`. Check it and link Xcode's iPhoneOS SDK into Theos with:

```bash
scripts/setup_mac.sh
```

- **Tweak:** `make FROZIO_DEBUG=1` builds `Frozio.dylib` exactly as CI does.
- **Simulator UI:** `make -C Harness run` builds Frozio's sources into a small Simulator app (`Harness/`) and opens Frozio settings. NaviMus itself is an arm64 device binary and doesn't run in the Simulator, so the harness covers Frozio's own UI only. Hooks into NaviMus still need a device build.
- `xcrun simctl launch booted com.frozio.harness -FZHarnessLyricsDemo YES` plays a silent four-song demo queue (first song with saved lyrics, a next-track handler like NaviMus's; `-FZHarnessDemoStart <n>` starts at song n), so lock screen lyrics and artist block can be followed in `make -C Harness log` (the Simulator draws no Now Playing panel).
- `make -C Harness shot` saves a screenshot; `make -C Harness log` streams Frozio's log lines.
- The iOS 26 `UISwitch` ignores very short synthesized taps in the Simulator; hold a tap for ~0.2 s when driving it from a script.

## App icons

Cyan is the default icon. White is an alternate icon you'll be able to pick in Frozio settings.

## License

GPL-3.0. See `docs/LICENSES.md` for what code is borrowed and from where.
