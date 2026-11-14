# FEATURES

One entry per shipped feature (added by that feature's PR). Each entry records:
- what it changes for the user
- the hooked NaviMus symbols (demangled + mangled)
- how each symbol was verified (tool + output)
- the fail-safe behaviour
- what was tested, and **what was NOT tested**

Status vocabulary: **builds** / **passes CI** / **verified on device (by the user)**.

## Phase 1: no-op tweak + pipeline

- **User-visible:** only the home-screen look. The app is named **Frozio** (CI input `display_name`), and the cyan icon replaces Arpeggi's. White is registered as an alternate icon; its picker arrives with the Frozio settings panel in Phase 2.
- **Hooks:** none in NaviMus. One fix on a system class: the CloudKit guard, below.
- **Version gate:** requires CFBundleShortVersionString `1.6.1`, CFBundleVersion `173`, and main-executable LC_UUID `EF406BF6-6FAE-3B23-BA21-963FFBF19DB8`. Otherwise Frozio does nothing.
- **Signing:** done by the user's own signer. CI signing is optional and only runs when all 5 secrets are set.
- **Status:** **builds** and **passes CI** (run 43548694887, artifact `Frozio-NaviMus-1.6.1-r6-debug-unsigned.ipa`, draft release "Frozio build 6"). **Verified on device by the user** (2026-11-14, iPhone14,5, iOS 17.5.1, external signer): it installs, launches, adds the Navidrome server, and behaves as stock.
- **Device history:** build r3 crashed at launch on iOS 17.5.1 (`Library not loaded: @rpath/Frozio.dylib … unloadable mach-o file type 10`). CI had injected the dSYM's DWARF file (MH_DSYM) instead of the dylib. It's fixed in r5, and CI now asserts `MH_DYLIB` before and after injection.
- **CI verified:**
  - `cryptid=0`
  - the bundle is 1.6.1 (173)
  - `@rpath/Frozio.dylib` is in the main binary's load commands, and `LC_RPATH @executable_path/Frameworks` is present
  - `Frozio.dylib` is arm64-only and links no substrate, ElleKit or libhooker
  - the icon files are written, and `CFBundleIconName` is removed in favour of `CFBundleAlternateIcons.White`
- **Not tested:**
  - the version-gate log line in Console.app (not reported)
  - switching to the white alternate icon (no picker yet)
  - CarPlay, Siri and iCloud settings sync under the user's signer

### On-device checklist (user)

1. Sign `Frozio-NaviMus-1.6.1-r6-debug-unsigned.ipa` with your signer and install it. Expect the **cyan** icon labelled **Frozio** on the home screen.
2. Launch. In Console.app (device connected, filter `subsystem:com.frozio.tweak`), expect `[Frozio] loaded v0.1.0` and `[Frozio] version gate PASS: 1.6.1 (173) uuid EF406BF6-…`.
3. Log in to your Navidrome server. Expect a one-time login, because the keychain starts empty.
4. Browse Library, Album, Artist and Playlist screens, and search.
5. Play a song, lock the phone, and confirm audio keeps playing. Check the lock-screen controls.
6. Change a NaviMus setting, force-quit, relaunch, and confirm it persisted.
7. Report anything that differs from the stock app. Note: CarPlay, Siri, and iCloud settings sync depend on what your signer's profile grants.

## Fix: CloudKit guard (`Source/Fixes/FZCloudKitGuard.m`)

- **What it changes for the user:** a re-signed NaviMus no longer crashes once a server is added. The library cache stays on the device, as in the App Store build.
- **Root cause:** crash `Arpeggi-2026-11-14-034741.ips` (iOS 17.5.1, team 2LV8B87L2J). It's re-sign-induced, and the **stock IPA re-signed the same way crashes identically**:
  - SwiftData → `-[NSPersistentContainer(CoreDataSPI) load:]` → `-[NSPersistentCloudKitContainer _loadStoreDescriptions:withCompletionHandler:]`.
  - Then `-[NSCloudKitMirroringDelegate initWithCloudKitContainerOptions:]` → `CKFetchAPSEnvironmentFromServerOrEntitlements` throws → `abort()`.
  - The App Store entitlements have `com.apple.developer.icloud-container-identifiers = []`, so SwiftData's `.automatic` CloudKit setting never mirrors there. The signer's profile adds iCloud containers but no `aps-environment`.
  - The exact exception text isn't in the report; the cause is inferred from the backtrace.
- **Hooked symbols:** Apple public API, not NaviMus:
  - `-[NSPersistentStoreDescription cloudKitContainerOptions]` (`@16@0:8`) → returns `nil`
  - `-[NSPersistentStoreDescription setCloudKitContainerOptions:]` (`v24@0:8@16`) → stores `nil`
- **Mechanism:** `method_setImplementation`, ObjC runtime only. No hooking library is added.
- **Verification:** at runtime, the class and both selectors must exist and the type encodings must match. Otherwise it logs and skips.
- **Fail-safe:** the guard only installs after the version gate passes and the setting is on.
- **Setting:** `fz.cloudKitGuard`, default **on**.
- **Tested:** builds, passes CI (run 43548694887), and is **verified on device by the user**: adding a server no longer crashes, and the app behaves as stock.
- **Not tested:** the iCloud settings sync (KVS, separate from CloudKit) under the user's profile.

## Feature: Frozio settings panel + app icon picker (`feat/frozio-settings`)

- **What it changes for the user:**
  - A Frozio logo button sits at the top-right of NaviMus's **Settings** tab. It opens the Frozio settings sheet, in spoti.pw's redesign settings style (black page, grey cards, accent #37F200).
  - **App icon:** Cyan (default) or White, via `setAlternateIconName:`.
  - **Keep library on this iPhone:** the CloudKit guard switch, on by default.
  - **Frozio on GitHub:** a link to the repo.
- **Hooks:** `-[UIViewController viewDidAppear:]` (UIKit, `v@:B`), shared with the debug census. The button is added only when all four parts of the census-verified identity hold:
  - the class name is `_TtGC7SwiftUI32NavigationStackHostingControllerVS_7AnyView_`
  - it's the root of a `SwiftUI.UIKitNavigationController`
  - that controller sits under `SwiftUI.UIKitTabBarController`
  - the nav title is `Settings`
- **No NaviMus Swift symbols are hooked.**
- **Verification:** `frozio.log` from build 7 (census lines 99, 142, 150).
- **Fail-safe:**
  - Any mismatch leaves the screen untouched.
  - Exceptions are caught and logged.
  - Frozio's pages are presented in their own navigation controller and never pushed onto SwiftUI's stacks.
- **Code reuse:** the settings kit is adapted from taurus (GPL-3.0); see `LICENSES.md`.
- **Tested:** debug and release builds pass CI (runs 43552106493, 43552234088).
- **Not tested:**
  - Everything on device.
  - Whether SwiftUI later resets the injected bar button. The button is re-added on every appearance.
  - The icon switch under the user's signer.

### App icon: asset-catalog icons (build 14+)

- **Device finding:** `setAlternateIconName` with loose-PNG alternates failed with `NSOSStatusErrorDomain -54` (build 12, iOS 17.5.1, user's signer).
- **Fix:** `scripts/rebuild_assets.sh` runs in CI on macOS:
  - It confirms the catalog is NaviMus 1.6.1's (only `AccentColor` and `arpeggiLogo` besides the icon, per `assetutil --info`).
  - It extracts `arpeggiLogo` through CoreUI (`scripts/carextract.m`) and re-creates `AccentColor` with sRGB (0.996, 1, 1, 1).
  - It adds `AppIcon` (cyan) and `AppIcon-White` with `actool --alternate-app-icon --include-all-app-icons`.
  - It verifies the new catalog and merges actool's `CFBundleIcons` into Info.plist.
  - If any step fails, CI falls back to the loose-PNG patch and warns.
- **Side effect:** NaviMus's iOS 26 layered icon (`AppIcon.iconstack`) is replaced by Frozio's flat icons, as intended.
- **CI-verified:** run 43554106642 shows `icon mode: catalog`, and the new catalog holds `AccentColor`, `AppIcon`, `AppIcon-White` and `arpeggiLogo`.
- **Not tested:**
  - the icon switch on device
  - that NaviMus's accent colour and logo render as before

## Known issues

| Issue | Status |
|---|---|
| **App icon switching** fails on the user's re-signed install (iOS 17.5.1) with `NSOSStatusErrorDomain -54`. It fails with loose-PNG alternates (build 12) and with asset-catalog alternates (build 15) alike. | **Parked by the user, 2026-11-14.** The icon row is hidden (enable with `-DFROZIO_ICON_PICKER`). Cyan still installs as the primary icon through the rebuilt catalog. Likely cause: how sideloaded/re-signed apps are registered with LaunchServices (compare uYouEnhanced #1016, SideStore #1145). Not verified. |

## Feature: redesign kit + accent colour (`feat/frozio-settings`)

- **Kit:** `Source/Redesign/Kit/` holds tokens (`FZRTokens`), artwork palette (`FZRPalette`), glass (`FZGlass`, `FZRGlass`) and accent (`FZRAccent`). Adapted from taurus (GPL-3.0), see `LICENSES.md`. It's the shared theming layer every redesign feature uses.
- **User-visible:** Frozio settings → Appearance → **Accent colour** (system colour picker) and **Reset accent**, default #37F200. It applies to Frozio's own screens now. **Verified on device by the user** (build 23 log: picks #FFFFFF, #32C759, reset to #37F200).
- **NaviMus's own tint:** that's `Settings.appTintColorPreset` in NaviMus's `settings.json`. It isn't written yet; Share log (debug) attaches `settings.json` so the exact format can be confirmed first.
- **Hooks:** none added.
- **Not tested:** on device.

## Feature: accent in NaviMus (`Source/Redesign/FZNaviMusTint.m`)

- **What it changes for the user:** with Frozio settings → Appearance → **Use accent in NaviMus** on (default **off**), NaviMus's own tint becomes the redesign accent (default #37F200). It takes effect on the next launch. Turning it off restores NaviMus's previous tint.
- **Mechanism:** data layer, no hooks. Frozio's constructor runs before NaviMus's `main()` and edits `Application Support/Arpeggi/shared_data/settings.json`:
  - `appTintColorPreset` = `{"type":"custom","color":{red,green,blue,opacity}}`
  - `tintColorBasedOnAppearance` = false
  - `dateLastPersisted` = now, so the local copy wins over the iCloud KVS copy
  - The original values are backed up once to `settings.json.frozio-backup`.
- **Verification (user's device, 2026-11-14):**
  - the file path came from the Share log listing
  - the preset and custom JSON forms came from two `settings.json` samples
  - `settingsMigrationVersion.json` = 2
- **Fail-safe:** nothing is written if the file is missing, the migration version isn't 2, the JSON isn't a dictionary, or the tint has an unknown shape. No backup means no change. Exceptions are caught.
- **Verified on device by the user (build 26, 2026-11-14):** on → NaviMus uses the accent after a restart; off → NaviMus's own tint comes back.
- **Not tested:**
  - the iCloud KVS round trip
  - the order of a tint change made in NaviMus while the switch is on (Frozio wins on the next launch, by design)
