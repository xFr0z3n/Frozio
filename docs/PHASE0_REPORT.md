# Frozio — Phase 0 report (NaviMus / Arpeggi 1.6.1, build 173)

Status: **recon only. No repo skeleton, no code.** Deliverables, written locally and not pushed:
- [CLASSES.md](CLASSES.md)
- [FEATURE_MATRIX.md](FEATURE_MATRIX.md)
- [DESIGN_TOKENS.md](DESIGN_TOKENS.md)
- [DISCREPANCIES.md](DISCREPANCIES.md)

Raw evidence lives in `work/dumps/` and `work/recon/`; the generator scripts are in `work/scripts/`.

**Tooling:**
- **REA MCP:** connected but unusable for Mach-O on Windows. Native tools need macOS, and none of the Ghidra/Hopper/IDA/Kuna providers can be used here.
- **otool, nm, class-dump, dsdump, swift-demangle, strings, Ghidra:** missing.
- **What I used instead:**
  - `ipsw` 3.1.745 (`work/tools/ipsw/`, SHA-256 matched against the release's `checksums.txt`) for `macho info`, `--ent`, `class-dump` and `swift-dump --demangle`.
  - Stdlib Python for the plist and for a `strings` equivalent.
  - `file` and `unzip`.

---

## 1. UI verdict and recommended strategy

**Verdict: predominantly SwiftUI, roughly 90% of screens.** UIKit is used only inside the long lists and a few utility controllers.

Evidence:
- `ArpeggiApp` conforms to `SwiftUI.App`.
- 237 `SwiftUI.View` conformances.
- 30 `ViewModifier`s.
- No `.storyboardc`/`.nib` files and no `UIMainStoryboardFile`.
- The scene manifest declares only the CarPlay scene.
- UIKit appears in:
  - 15 `UIViewRepresentable` wrappers (UITableView/UICollectionView lists)
  - 2 `UIViewControllerRepresentable` wrappers (`MailView`, `ActivityViewController`)
  - 2 `UIViewController` subclasses (`AirPLayViewController`, `StatusBarConfigurator.ViewController`)

Source: `grep -E '^extension Arpeggi\.[^:]+: _\$s7SwiftUI…' work/dumps/swift_dump_demangled.txt`

| Screen | Framework | Key types |
|---|---|---|
| Now Playing | SwiftUI | `PlayerView`, `PlayerViewWrapper`, `AppleMusicStylePlayerView` (+ Horizontal/Vertical), `ArpeggiPlayerControls`, `ElasticSlider` |
| Mini-player | SwiftUI | `MiniPlayerContent`, `MiniPlayeriOS26View`, `AccessoryMiniPlayer` |
| Tab bar | SwiftUI `TabView`, UIKit-backed | `TabViewiOS26`, `HomeTabView`, `ManageTabBarItemsView` |
| Library | SwiftUI shell + UIKit lists | `LibraryView`, `LibraryListView`, `*SectionedUITableViewUIViewRepresentable` |
| Album | SwiftUI + UIKit table | `AlbumDetailView`, `AlbumiPhoneView`, `AlbumTableView` (representable) |
| Artist | SwiftUI + UIKit collection | `ArtistDetailView`, `ArtistAlbumsView`, `ArtistCollectionView` (representable) |
| Playlist | SwiftUI | `PlaylistDetailView`, `PlaylistiPhoneView`, `PlaylistEditView` |
| Queue | SwiftUI + UIKit table | `AppleMusicStyleQueueView`, `QueueViewTableView` (representable) |
| Search | SwiftUI | `SearchView`, `LibrarySearchView` |
| Settings | SwiftUI | `SettingsView` + about 25 `*SettingsView`s |
| Lyrics | SwiftUI | `AppleMusicLyricsView`, `KaraokeLyricLine` |
| CarPlay | UIKit CPTemplate | `CarPlaySceneDelegate` (ObjC) |

**The critical constraint:** every Swift function in the binary is symbol-stripped.
- swift-dump reports 9,701 `<stripped>` entries, and the symbol table holds 0 `s7Arpeggi` symbols.
- Only **37 app classes expose ObjC selectors**: `AppDelegate`, `AudioManager` (9 selectors), `DownloadManager`, `CarPlaySceneDelegate`, the table/collection coordinators, `CachingResourceLoader`, `NetworkMonitor`, and a `UINavigationController(Arpeggi)` category.
- The other 52 app classes are pure Swift: `@Observable` managers and view models whose ivars are visible but whose methods are not.

**Options:**
- **(a) Model-layer hooks plus Frozio-owned views presented over or in place of NaviMus's SwiftUI.**
  - Pros:
    - Most hook points are robust ObjC: system classes (`AVQueuePlayer`, `AVPlayerItem`, `MPNowPlayingInfoCenter`, `NSURLSession`/`NSURLProtocol`, `UITabBar`, `UINavigationController`) and NaviMus's own OBJC selectors.
    - Frozio's views are ours, so design parity is fully under our control.
  - Cons:
    - It duplicates UI: the player, headers and so on get rebuilt.
    - Reading NaviMus's `@Observable` state means ivar reads, which have to be type-checked.
- **(b) Hook the `UIHostingController` boundary.**
  - Pros:
    - One robust ObjC seam (`UIWindow`/`UIHostingController`, `UINavigationController` push).
    - It lets us inject SwiftUI environment at the root (tint, colorScheme, `fontDesign`, materials), attach overlays or toolbar items to specific screens, and identify screens by the hosting controller's generic Swift type name (a verified class type, not a view index).
  - Cons:
    - It can't change the *inside* of a NaviMus SwiftUI view. Replacing a `View.body` would need witness-table patching of stripped code, and the `Body` associated type can't change.
- **(c) Patcher-style rebuild.**
  - Pros: total control.
  - Cons: we'd effectively rewrite a closed-source app, it's huge, and it breaks on every NaviMus update.

**Recommendation: (a) + (b) combined.** Use (b) as the shared theming and injection layer, done first per §6. Use (a) for every feature that needs new UI: a Frozio player, lyrics, a Live Activity and the settings panel. Use direct Swift vtable or witness patches only as a last resort, per feature, pinned by the version gate **and** LC_UUID `EF406BF6-6FAE-3B23-BA21-963FFBF19DB8`. That combination is also why "partial" is the most common feasibility in the matrix: many restyles of NaviMus's own screens can only be approximated through environment injection and overlays.

## 2. Re-signing risks

The bundle is as simple as it gets: one executable, **no `Frameworks/`, no `PlugIns/`, no app groups and no keychain-access-groups.**

Entitlements come from `ipsw macho info --ent` (Team `9QGVRRV7V8`):

| Entitlement | Breaks under a new Team ID? | What depends on it | Effect after re-sign |
|---|---|---|---|
| `application-identifier`, `team-identifier` | Re-derived | everything | Normal |
| *(implicit)* default keychain group = `<TEAM>.com.reillywilkinson.NaviMus` | Yes: a new group | Server passwords: `KeychainHelper`, `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | A fresh install starts with an empty keychain, so you **log in once**. It can't be installed over the App Store build anyway (different signer). Functional. |
| `com.apple.developer.ubiquity-kvstore-identifier` | Yes; needs the iCloud capability on your profile | `UbiquitousSettingsStore`: settings sync over iCloud KVS (`enableiCloudSync`) | If the profile lacks iCloud (e.g. a free account), sync silently does nothing and settings stay local in `Application Support/*.json`. Must not crash; **check on device.** |
| `com.apple.developer.icloud-container-identifiers` (empty array) | **Yes: confirmed crash** | SwiftData `ModelConfiguration…cloudKitDatabase: .automatic` | **Correction after device test:** if the signer's profile lists iCloud containers but no `aps-environment`, SwiftData turns on CloudKit mirroring and CloudKit aborts when a server is added. The stock IPA re-signed this way crashes too. Frozio's CloudKit guard (`docs/FEATURES.md`) keeps the store local-only, matching the App Store build. |
| `aps-environment` = production | Yes | `remote-notification` background mode (likely KVS change pushes) | Pushes from Apple to the new team only; local function is unaffected. Requires Push on the profile, otherwise strip it. |
| `com.apple.developer.carplay-audio`, `com.apple.developer.playable-content` | **Apple-granted only** | `CarPlaySceneDelegate` | **CarPlay is lost** unless your team holds the CarPlay entitlement. Must be stripped for most re-signs. |
| `com.apple.developer.siri` | Needs capability (paid account) | 12 `AppIntent`s and Siri | Without it, Siri voice control is lost; Shortcuts/AppIntents in-app still work. |
| `com.apple.developer.networking.wifi-info` | Needs capability (paid account) | `NetworkMonitor` WiFi-SSID home/remote server switching | Without it, auto-switching to the local server URL fails and the remote URL is used. |

Not entitlement-bound: `BGTaskSchedulerPermittedIdentifiers` (`com.reillywilkinson.NaviMus`), background audio and the `arpeggi://` scheme are all fine. If you must change the **bundle ID** (a free account), none of this gets worse, since no app group or shared keychain is involved.

**Bottom line:** a plain re-sign keeps the app functional (login, browse, play, background audio, local settings). CarPlay is lost unless your team has the entitlement. Siri, iCloud settings sync and WiFi auto-switching depend on your profile's capabilities.

## 3. Feature summary

[FEATURE_MATRIX.md](FEATURE_MATRIX.md) has 275 rows plus 3 proposed Subsonic-native rows:

| Feasibility | Count |
|---|---|
| yes | 35 |
| partial | 160 |
| no | 0 |
| N/A (Spotify-specific) | 79 |
| needs your decision | 1 |

- **Gating:** spoti.pw has **zero** licence or paywall gating. Its only prerequisites are iOS 26 for the redesign, iOS 17 for the Live Activity, and the look mode. The 36 taurus-only rows are later taurus additions, not code spoti.pw locks (`work/recon/taurus_features.md`). 17 shared features behave differently in taurus.
- **Spotify-specific (N/A):** remote-config flag pages (Labs/All flags), telemetry, ad and upsell hiding, Premium spoofing, Canvas, Spotify Connect, link cleaning.
- **Top risks:**
  1. **Stripped Swift.** Restyling NaviMus's own SwiftUI screens can't be done 1:1, only approximated through root environment injection and overlays; full parity means Frozio-owned replacement views.
  2. **Player redesign (38 rows):** the largest and riskiest block. It needs a Frozio player that drives NaviMus's `AudioManager` through state we don't own.
  3. **Live Activity:** needs a **new widget extension** added to the IPA (NaviMus has none), which adds signing complexity.
  4. **Audio effects and beat haptics:** an `MTAudioProcessingTap` on NaviMus's `AVQueuePlayer` items. The hooks are robust, but there's a gapless-playback interaction risk.
  5. **iOS 26 glass tokens on an iOS 17 app:** every token needs a pre-26 fallback.

## 4. Discrepancies

Eleven entries in [DISCREPANCIES.md](DISCREPANCIES.md). The notable ones:
- **"Completely SwiftUI"** is not quite true: lists are UIKit.
- **CrossFade** is on the roadmap but already has a model in the binary with no UI.
- **iCloud Sync** is on the roadmap but already implemented through KVS.
- **The privacy claim is inaccurate.** The binary calls lrclib.net (including a *publish* endpoint), the GitHub releases API and Google favicons.
- **A class named `GRDBService`** exists, but there's no GRDB or SQLite linkage.
- **Minimum iOS is 17.0** and the binary is **arm64 only**.

## 5. Settings inventory

- **NaviMus's store:**
  - **Settings manager:** `Arpeggi.SettingsManager` (an `@Observable` Swift class, SWIFT-CLS) holds Codable structs: `Settings`, `PlayerViewConfiguration`, `LyricsSettings`, `TabSettings`, `TranscodeSettings`, `ReplayGainSettings`, `CacheSettings` and about 15 more.
  - **On disk:** one **JSON file per key** under `URL.applicationSupportDirectory`, via `LocalFileManager`; 34 file names, e.g. `serverConfigurations.json`, `currentConfiguration.json`, `selectedTab.json`.
  - **iCloud:** the same keys are mirrored to iCloud KVS by `UbiquitousSettingsStore`.
  - **UserDefaults:** `@AppStorage` (with an optional `store:` suite) is used for some UI state, including `TabViewCustomization`.
  - **Keychain:** server passwords, generic-password items.
  - **Library cache:** SwiftData (`SchemaV1–V3`, 98 `@Model` classes across the versions).
- **Settings UI:** the SwiftUI `SettingsView` plus about 25 sub-views, reached from a tab or toolbar.
- **Where Frozio's settings go:** injecting a row *into* NaviMus's SwiftUI `Form` would need witness patching of stripped code, so it's not safe. Instead:
  - Add a Frozio entry (a nav-bar item or header) to the `UIHostingController` that hosts `SettingsView`, found by its verified generic type through the existing `UINavigationController` seam.
  - That entry opens a Frozio settings panel styled with spoti.pw's tokens.
  - Frozio stores its own keys in a dedicated `UserDefaults` suite (`com.frozio.tweak`) and never writes NaviMus's JSON files.

## 6. Open questions for you

1. **spoti.pw licence.** Current spoti.pw is **PolyForm Strict 1.0.0** (`spoti.pw/README.md:117-122`): no reuse in other projects, no redistribution. FROZIO_PROMPT §2.3 says "reuse code if possible". My proposal: **no spoti.pw code reuse at all**. Behaviour and design values only (recorded as facts), implemented clean. Code from releases **≤ v0.21.1** (GPL-3.0) could be used only if Frozio itself becomes GPL-3.0. Which do you want?
2. **GPL code.** amperfy and taurus are GPL-3.0. Borrowing any of their code makes Frozio GPL-3.0 (§7.5 says ask first). Is Frozio allowed to be GPL-3.0? If not, amperfy is reference-only.
3. **The "gating" premise doesn't hold.** spoti.pw has no gating, and taurus's extras are new features rather than ungated ones. Should the 36 taurus-only features be **in scope** (targeting taurus's behaviour, since spoti.pw has no "intended" version of them), or only spoti.pw's 239?
4. **Strategy.** Do you approve the **(a)+(b)** combination, accepting that NaviMus's own screens get restyled by approximation and only Frozio-owned replacement views reach full 1:1 design parity?
5. **iOS 26 look.** spoti.pw's main look is iOS 26 Liquid Glass, with older material blurs before iOS 26. NaviMus supports iOS 17. Should Frozio target spoti.pw's **redesign** look (glass on 26, blur fallback on 17–25), its **native** look, or both as a toggle like spoti.pw?
6. **Signing account.** Which account type: a paid team with CarPlay entitlement, a paid team without it, or a free account? This decides which entitlements CI strips (see §2).
7. **F60 "Lossless local FLAC swap-in"** with a Soulseek account page. It's out of scope unless you say otherwise.
8. **New extension.** May Phase 2+ add a Frozio widget extension to the IPA for Live Activities? It adds a second signed bundle.
9. **FrozenMusic layout.** FrozenMusic is a YTMusicUltimate fork (`Source/`, `layout/`, `control`, `ARCHS = arm64`, `TARGET = iphone:clang:16.5:13.0`, `.github/workflows/main.yml`). For Frozio I'd use `ARCHS = arm64` (the app has no arm64e slice) and `TARGET = iphone:clang:latest:17.0` instead of the prompt's `arm64 arm64e` / `15.0`. OK?

## 7. Proposed Phase 1 plan (pending approval)

1. **Repo skeleton in `xFr0z3n/Frozio`** mirroring FrozenMusic (`Source/`, `layout/`, `control`, `Makefile`, `Frozio.plist` filtered to `com.reillywilkinson.NaviMus`), with a diff against FrozenMusic and an explanation of each deviation.
   - `ARCHS = arm64`, `TARGET = iphone:clang:latest:17.0`.
   - Preference bundle stub.
   - `docs/` (the files above plus `FEATURES.md` and `LICENSES.md`).
   - `.gitignore` as specified.
2. **`FROZIO_DEBUG` logger:** os_log subsystem `com.frozio.tweak`, compiled out in release builds.
3. **Version gate:** require `CFBundleShortVersionString == 1.6.1`, `CFBundleVersion == 173`, and the main-image LC_UUID `EF406BF6-6FAE-3B23-BA21-963FFBF19DB8` (read from `_dyld_get_image_header(0)`). On mismatch, log once and install nothing. No hooking runtime is needed yet.
4. **GitHub Actions** (`workflow_dispatch`, macOS runner):
   - Takes an IPA URL or release-asset input.
   - Caches Theos and the SDK, then builds.
   - Injects with **insert_dylib** (`@rpath/Frozio.dylib`; the binary already has `LC_RPATH @executable_path/Frameworks`).
   - Signs inside-out with a temporary keychain and entitlements re-derived for `TEAM_ID`. CarPlay, Siri, wifi-info, aps and KVS are stripped or kept according to your answer to Q6.
   - Verifies with `codesign --verify --deep --strict`, `otool -L` and an entitlements dump.
   - Attaches the release asset and deletes the keychain in an `always()` step.
5. **Done when:** the CI run is green and you've confirmed on device that the app installs and launches, logs the gate line, and behaves like stock (login, browse, play, background audio, settings persist).

---

## 8. Decisions (user answers, 2026-11-14)

1. **Code reuse: yes.** Frozio is GPL-3.0, so code comes from GPL sources only: taurus, spoti.pw ≤ v0.21.1, amperfy. Current spoti.pw (PolyForm Strict) is not copied (`docs/LICENSES.md`).
2. **GPL-3.0: approved.**
3. **Gated features:** per the user, spoti.pw's released builds gate **Visualizer, Workshop (shaders), AutoMix and Web Player**. Visualizer and AutoMix exist in taurus. Workshop and Web Player have no code in either repo, and their matrix rows wait on a description.
4. **Strategy (a)+(b): approved.**
5. **Look:** redesign only. The 72 native-look rows are out of scope.
6. **Signing:** paid Apple certificate. CI keeps only the entitlements the provisioning profile grants (CarPlay is dropped unless granted) and never changes the bundle ID.
7. **F60 lossless/Soulseek:** dropped.
8. **New Frozio extension (Live Activity):** allowed.
9. **Layout and targets:** `ARCHS = arm64`, `TARGET = iphone:clang:latest:17.0`. Approved.

Extra request: a cyan default app icon, a white alternate icon selectable in Frozio settings, and the Frozio logo in the repo and in-app (`Frozio.bundle/logo.png`, for the settings header in Phase 2).
