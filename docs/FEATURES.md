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

## Feature: About page — licenses, settings backup, reset all (`feat/settings-basics`)

Matrix rows `about-links`, `backup`, `reset-all`. Adapted from taurus `App/About/AboutSettings.m`, `Backup.m`, `Licenses.m` (GPL-3.0, see `LICENSES.md`); spoti.pw's current code is not copied.

- **What it changes for the user:** Frozio settings → About → **About** opens a page with:
  - **Version** and **NaviMus** (the host's `CFBundleShortVersionString`)
  - **Frozio on GitHub** (moved here from the root page) and **Licenses** (Frozio GPL-3.0, taurus GPL-3.0)
  - **Export settings**: writes `frozio-settings.json` (`{frozio, navimus, settings}`) and opens the share sheet
  - **Import settings**: picks a JSON file, confirms, replaces Frozio's settings with the file's, then closes NaviMus
  - **Reset all settings** (red): confirms, removes every Frozio setting so each is back at its default, then closes NaviMus
- **Scope:** only Frozio's own suite (`com.frozio.tweak`, keys `fz.*`). `fz.appIcon` is left out of backups and reset because it mirrors what iOS shows. NaviMus's own settings, servers and downloads are never touched. A setting that's off after a reset or an import undoes itself on the next launch as it always does (e.g. "Use accent in NaviMus" off restores NaviMus's tint).
- **Differences from spoti.pw:** no Website or Discord rows, because Frozio has neither yet. No "stock mode" on reset (Frozio has none; defaults are the stock state). "Close" instead of "restart": iOS can't relaunch an app, so Frozio exits like taurus does and the user opens NaviMus again.
- **Import fail-safe:** a file that isn't a JSON object with a `settings` dictionary is refused. Each key must be an `fz.` setting, a plist-valid value, and the same type as the stored one (if any); others are skipped and counted in the log.
- **Hooks:** none.
- **Fix found while testing:** an alert presented while the document picker is still dismissing came up half drawn (title only, no buttons). The import confirmation now waits for the picker's dismissal to finish.
- **Tested (Simulator harness, iPhone 17 Pro, iOS 26.5):** export writes `{"fz.redesign.accent.navimus": true}` with versions; Save to Files; reset empties the suite and closes the app; import of that file restores the key (`import: set 1 keys, skipped 0`) and closes the app; Licenses page renders. Release and debug Theos builds pass.
- **Verified on device by the user (build 27, 2026-11-14):** export, import and the About page work inside NaviMus.
- **Not tested:**
  - importing a file from another Frozio version with different keys

## Feature: lock screen lyrics (`feat/lockscreen-lyrics`)

Matrix row `lockscreen-lyrics`. Adapted from taurus `Shared/LockScreenLyrics/LockScreenLyrics.x` (GPL-3.0, see `LICENSES.md`).

- **What it changes for the user:** Frozio settings → Lyrics → **Lock screen lyrics** (default **off**). While a song plays, the line being sung replaces the artist in the system Now Playing info: lock screen, Control Center, CarPlay. Long lines are split into pieces of about 30 characters, shown in turn. Between lines (an empty line, more than 8 s into a line with the next still far off, or past the last line) NaviMus's own artist comes back. The switch applies right away.
- **Lyrics source:** the synced lyrics NaviMus has already saved on the device; Frozio fetches nothing. A song shows lines once NaviMus has loaded its lyrics (opening the lyrics view, or however NaviMus pre-fetches them). Server lyrics beat LRCLib when both are saved, as in NaviMus's "Auto" order. Plain (unsynced) lyrics are ignored.
- **Verified in the 1.6.1 binary** (`otool -tV`, `work/dumps/disasm.txt`; Swift small strings decoded from `mov`/`movk` immediates):
  - loader at `0x1008f46f4`: "Lyrics folder not found", error domain "LyricsLoader"
  - folder helper `0x1008e9f80` → `NSApplicationSupportDirectory` (`0xe`) + `0x1008e87e4`, which maps case 6 → `"lyrics"`, case 5 → `"database"`, under `"Arpeggi/" + <database id>`
  - file name: CryptoKit SHA-256 (`0x1008ebc6c`) of `"<songID>_<source>"` + `".json"`; Frozio doesn't recompute it and indexes files by their `songID` field instead
  - decoded with `JSONDecoder` (`0x1008f522c`) into `Arpeggi.CachedLyrics` (`songID`, `offset`, `synced`, `syncedLines{start, value}`, `source`; `swift_dump_demangled.txt:2592`)
  - song identity: NaviMus sets `MPNowPlayingInfoPropertyExternalContentIdentifier` (`0x100297bb4`); it matches the cache file's `songID` (confirmed on device, build 27).
- **Hooks:** `-[MPNowPlayingInfoCenter setNowPlayingInfo:]` (`v@:@`) and `-[MPNowPlayingInfoCenter nowPlayingInfo]` (`@@:`), public MediaPlayer API via `FZHook` (ObjC runtime). No NaviMus symbols are hooked. NaviMus reads back its own dictionary, never the edited one.
- **Fail-safe:** either hook missing or with other types → both stay off (the setter is restored if the getter fails) and NaviMus's info goes out untouched. No ID, no saved file, unreadable JSON or `synced: false` → the artist stays. Switch off → the artist is put back at once. The timer runs only while the reported rate is above 0.
- **Offset:** applied as OpenSubsonic documents it (positive shows lyrics sooner). Not verified against NaviMus's own lyrics view.
- **Debug log:** each change logs the elapsed time and "a line (N chars)" or "(artist)"; the text itself is logged only in the Simulator harness. `lyrics: none saved by NaviMus for the playing song yet` means no cache file matched the song's ID.
- **Tested (Simulator harness, iPhone 17 Pro, iOS 26.5, `-FZHarnessLyricsDemo YES`):** the harness writes a CachedLyrics file under `Application Support/Arpeggi/harness-db/lyrics/`, plays silent audio and sets Now Playing info the way NaviMus does. The hooks install, the file is indexed, and the log shows each line at its time (1.0, 5.0, 9.0 s), the 78-character line split into three pieces (9.0, 10.5, 11.8 s), the empty line restoring the artist (13.0 s), and the artist returning 8 s into the last line (31.0 s). Release and debug Theos builds pass.
- **Verified on device by the user (build 27, 2026-11-14):** the sung line shows in place of the artist on the lock screen and advances with the song, which also confirms that NaviMus's `ExternalContentIdentifier` matches the cache file's `songID`.
- **Not tested:**
  - CarPlay
  - a song with a non-zero offset (sign of the offset)

## Feature: blocked artists (`feat/artist-block`)

Matrix row `artist-block`. Adapted from taurus `Shared/ArtistBlock/` (GPL-3.0, see `LICENSES.md`).

- **What it changes for the user:** Frozio settings → Playback → **Blocked artists** (row shows the count, or Off). The page has the **Skip blocked artists** switch (default off), **The main artist** / **Main or featured**, **Block from what's playing…** (the playing credit, then each name in it), **Block by name…**, and the list (swipe to unblock). A song by a blocked artist is skipped as it starts playing. Applies right away.
- **Matching:** by name, as NaviMus reports it in Now Playing (`MPMediaItemPropertyArtist`); NaviMus exposes no artist IDs here. Case-, accent- and width-insensitive. A song is blocked when its whole credit is blocked, or its first name is, or (Main or featured) any name in it. Credits split on `,` `;` `&` `/` `feat.` `ft.` `featuring`.
- **Skip:** NaviMus's own next-track handler. `-[MPRemoteCommand addTargetWithHandler:]` is hooked so the handler NaviMus registers on `MPRemoteCommandCenter.nextTrackCommand` is kept (Frozio's constructor runs before NaviMus registers it). Skipping calls that handler with an event from `+[MPRemoteCommandEvent eventWithCommand:mediaRemoteType:options:]`, typed by the command's own `-mediaRemoteCommandType`. That's the same path the lock screen's Next button takes, so NaviMus's queue stays in step.
  - The factory is private MediaPlayer API. It's looked up at run time and used only if its types are exactly `@@:@I@` (and `I@:` for the type getter); otherwise nothing is skipped and the log says so. `-[MPRemoteCommandEvent init]` aborts, which is why it isn't used.
- **When:** once per song (`ExternalContentIdentifier`), only while the reported rate is above 0, so a paused song restored at launch isn't skipped until it plays. After 25 blocked songs in a row it stops skipping until an unblocked song plays.
- **Hooks:** `-[MPRemoteCommand addTargetWithHandler:]` (`@@:@?`) and `-[MPNowPlayingInfoCenter setNowPlayingInfo:]` (`v@:@`), public MediaPlayer API via `FZHook`. Installed after lock screen lyrics, so it sees NaviMus's own info (lyrics re-sends go straight to the original setter). No NaviMus symbols.
- **Tested (Simulator harness, iPhone 17 Pro, iOS 26.5):** the harness demo has a four-song queue and registers a next-track handler as NaviMus does. With "Blocked Band" blocked (typed lowercase, stored as typed with auto-capitalisation): "Second Song" by "Blocked Band feat. Guest Singer" was skipped to "Third Song" by "Guest Singer & Harness Artist", which stayed (main artist not blocked). With Main or featured and "Harness Artist" also blocked, every song was blocked: 25 skips, then `25 blocked songs in a row; not skipping any more`. The page, Block by name, Block from what's playing (already-blocked names greyed out) and the root row render. Release and debug Theos builds pass.
- **Found while testing:** the first version created the event with `-[MPRemoteCommandEvent init]`, which killed the app; replaced by the factory above.
- **Verified on device by the user (build 28, 2026-11-14, iOS 17.5.1):** a blocked artist's song is skipped by NaviMus's own handler, so the event factory exists and NaviMus accepts its event on iOS 17 too.
- **Not tested:**
  - NaviMus's credit format for multi-artist songs

## Feature: redesigned look, slice 1: app-wide look (`feat/redesign-app-look`)

Matrix rows `redesign-ui`, `redesign-amoled`, `redesign-tabbar` (partial). Strategy (b), the hosting boundary: system UIKit seams only, no NaviMus symbols.

- **What it changes for the user:** Frozio settings → Appearance → **Redesigned look** (glow switch, default **off** until confirmed on device; then it becomes the default). Read at launch: flipping it offers "Close NaviMus". With it on:
  - NaviMus is always dark, whatever its own appearance setting says, so its pages are black with cards one step lighter (the redesign's field and elevated surfaces).
  - Tab bar: the selected tab is the redesign accent (default #37F200), the others secondary white.
  - iOS 26: the system's Liquid Glass tab and navigation bars, as spoti.pw's redesign uses them (tokens `tabbar.system`, `navbar.liquidGlass`).
  - Before iOS 26 (the user's iOS 17): the redesign's fallback material (`material.glass.fallback`, SystemChromeMaterialDark) behind the tab bar and behind the navigation bar once scrolled; at the top the navigation bar is transparent with a white 34 pt bold large title on black.
- **Hooks (ObjC runtime via FZHook, only when the switch was on at launch):**
  - `-[UIViewController setOverrideUserInterfaceStyle:]` and `-[UIWindow setOverrideUserInterfaceStyle:]` (`v@:q`) → always dark. Seen in the harness: SwiftUI's `preferredColorScheme` (NaviMus's appearance setting) lands on the root `UIHostingController`, not the window.
  - `-[UIWindow becomeKeyWindow]` (`v@:`) → each window dark as it becomes key.
  - `-[UITabBar setTintColor:]` (`v@:@`) → the accent. SwiftUI's `.tint` (NaviMus's tint) sets the tab bar's own tint and beats the appearance proxy.
  - `UITabBar` / `UINavigationBar` appearance proxies, set in the constructor before NaviMus builds its UI.
- **Not changed (by design for this slice):** the inside of NaviMus's screens (rows, player, mini player). Back buttons and other controls keep NaviMus's tint (white by default). Use "Use accent in NaviMus" to make those the accent too.
- **Tested (Simulator harness, iPhone 17 Pro, iOS 26.5):** the harness now hosts a SwiftUI stand-in shaped like NaviMus (`Harness/NaviMusStandIn.swift`: TabView of NavigationStacks, plain and inset grouped lists, a Settings form, NaviMus's tint). The real `FZSettingsEntry` recognises its Settings tab ("added to NaviMus Settings"). With the stand-in asking for light mode (`-FZHarnessLight YES`): off → light pages and bars; on → black pages, dark glass tab bar with the accent on the selected tab, Library's cards elevated on black, a pushed album page with a white inline title. With `-FZHarnessMaterialBars YES` (the pre-26 path previewed on iOS 26): transparent bar with a large title at the top, chrome blur once scrolled, blurred tab bar. The switch row, glow and restart prompt work.
- **Not tested:**
  - on device (iOS 17.5.1): the real material bars, and NaviMus's own screens (player, mini player, sheets)
  - an iOS 17 Simulator: the runtime couldn't be installed from the command line here (`xcodebuild -downloadPlatform` dies with a bus error on this Mac)

## Redesign R0a: library store schema in Share log (`feat/redesign-plan-r0a`)

The plan for the full 1:1 redesign is in `REDESIGN_PLAN.md`. Step R0a: debug builds' **Share log** now first writes the layout of NaviMus's library store to `frozio.log`. That's every SQLite file under `Application Support/Arpeggi/` (except lyrics, covers and songs): its tables, their columns with declared types, and row counts. No row content is read. Files are opened `SQLITE_OPEN_READONLY`. Links `libsqlite3`.

- **Tested (harness):** a seeded store under the harness's `Arpeggi/harness-db/database/` logs its 2 tables with columns and counts.
- **Needed from the device:** one Share log from a debug build, to learn NaviMus's real SwiftData schema.

## Redesign R0b/R0c: probe build (`feat/redesign-probe`)

Findings so far, and a debug probe for what only the device can show.

- **Library store (from the user's Share log, build 32):** `Application Support/Arpeggi/<database id>/database/db.sqlite`, 35 tables. Main entities: `ZALBUMMODEL` (175 rows; year, genre, play count, created, played, starred, cover art …), `ZARTISTMODEL` (238), `ZSONGMODEL` (109), `ZPLAYLISTMODEL` (1), plus the downloaded and link tables. **It's a partial cache.** Songs are stored only for albums NaviMus has opened (109 songs vs 822 in the user's library), so rebuilt pages also need the server. NaviMus's server config is in `shared_data/serverConfigurations.json` and `currentConfiguration.json`, and its password in the keychain. Frozio, running inside NaviMus, can call the same OpenSubsonic API.
- **`arpeggi://` has no deep-link routes.** The scheme check in the binary (`0x100208958`) is `arpeggi-cache`, NaviMus's audio caching loader; the `URLComponents.host` parser (`0x1008b1fc8`) validates server addresses. "Play this album" therefore has to go through NaviMus's App Intents.
- **Every NaviMus page is `NavigationStackHostingController<AnyView>`** (device census), so the class can't identify an album page. **FZProbe** (`Source/Probe/FZProbe.swift`, the tweak's first Swift file) reflects the SwiftUI root view inside the `AnyView` with `Mirror`: type metadata names survive the stripping. Harness check: a pushed album page reports `…AlbumDetail` with field `album: …Album`.
- **Debug probe logs (census):**
  - each page's root view type and its field names and types (never values)
  - NaviMus's App Intent and entity types with their fields (`_typeByName` + `Mirror`; creating an intent instance doesn't run it)
  - the views in the bottom 220 pt of the tab bar controller (mini player, tab bar)
  - the navigation bar's views (bar buttons): class, frame, touch
- **Needed from the device:** one Share log after opening an album, an artist, a playlist, Home, each Library category, Search and NaviMus's player.

## Redesign R4a: the album page (`feat/redesign-album-page`)

The first rebuilt page of the 1:1 redesign (`REDESIGN_PLAN.md`), laid over NaviMus's own album page when **Redesigned look** is on.

- **What it changes for the user:**
  - full-bleed album artwork dissolving into a page colour taken from the cover
  - glass back and ⋯ circles in place of NaviMus's bar
  - the title (Title 1 bold), the artist (tap: NaviMus opens the artist), and "genre · type · year"
  - the action row: shuffle, the white **Play** capsule, and **download** (the user's choice in place of chroma.pw's "+")
  - track rows (title; explicit badge plus artists; ⋯)
  - pull down to stretch the cover
- **How:** values from taurus `Redesigned/Album/AlbumHeader.x`, `AlbumRows.x` and `Kit/SGRHeaderInfo.m` / `SGRActionRow.m` (GPL-3.0): 20 pt sides, 148 pt Play, 16 pt spacing, 48 pt row, 46 % dissolve, 140 pt top scrim at 28 %, 44 pt glass circles 16 pt from the corners.
  - **Interception:** `-[UINavigationController setViewControllers:animated:]` (SwiftUI's NavigationStack sets the whole stack; it doesn't push) and `pushViewController:animated:`. A page whose root view is `….AlbumViewWrapper` gets the rebuilt page as a child view controller over it. NaviMus's bar is faded out while it's on top and back after, so back and swipe-back pop NaviMus's page and its path stays in step. `viewDidLayoutSubviews` keeps the page above views SwiftUI adds later.
  - **Data:** `getAlbum` and `getCoverArt` from the user's server with NaviMus's own login (`FZServer`). The server address and auth parameters come from NaviMus's requests: seen at `-resume` on the session task class, since Swift's async URLSession API skips `dataTaskWith…`, which the harness proved. Kept in memory only, never logged.
  - **Play, track tap, artist tap:** NaviMus's `PlayAlbumIntent`, `PlaySongIntent` and `OpenArtistIntent`, the entity looked up by ID through its query (`FZNaviMus.swift`).
  - **Shuffle, download, ⋯:** NaviMus's own controls on its page, activated through accessibility. The page and NaviMus's bar step aside for the instant of the call, because SwiftUI only activates reachable controls.
- **Fail-safe:** no album ID → NaviMus's page stays; a failed load or action → a short message and a log line; each hook is type-checked by FZHook.
- **Tested (harness, iPhone 17 Pro, iOS 26.5, `Harness/mockserver.py`):** the stand-in logs in with an async request (captured via `-resume`); opening an album covers the stand-in's `AlbumViewWrapper`; the page loads album, songs and cover from the mock server and colours itself from the cover; Play ran `PlayAlbumIntent(al-1)`, a track `PlaySongIntent(so-1)`, the artist `OpenArtistIntent(ar-1)`; download activated the page's own Download control; ⋯ opened the page's own menu; back popped the page and restored the bar.
- **Not tested:**
  - on device with NaviMus's real intents, controls and server
  - NaviMus's real control labels: debug builds log them when the page opens
  - the song tap plays that song through `PlaySongIntent`; whether NaviMus queues the rest of the album after it is NaviMus's own behaviour, to be checked on device

## Redesign R4b: the album page 1:1 (`feat/redesign-album-1to1`)

Fixes from the user's device test of build 34, with chroma.pw's own page as the reference.

- **1:1 with taurus's album page (GPL-3.0):**
  - **Field:** the page's field is now taurus's `SGRArtworkField`, ported as `FZRArtworkField` / `FZRFlow` / `FZRFluid`. It's the cover's field colour fading to black down the page, which gives chroma.pw's deep brown, not a flat colour.
  - **Hero:** the cover fills the top down to 56 pt below the title's top (`SGRHeaderInfoTitleRise`), measured at 472 pt on a 390 pt screen.
  - **Info (`SGRHeaderInfo`):** Title 2 bold primary, Body secondary, Footnote tertiary, gaps 2 / 4.
  - **Play capsule (`SGRPlayCapsule`):** Subheadline semibold up to Large, the glyph in a 44 pt box, the glyph and word in the field's colour.
  - **Top buttons:** back is a bare chevron and ⋯ is pinned in a glass circle, as chroma.pw shows on iOS 17.
- **Play ⇄ Pause:** the capsule reads Pause while one of this album's songs plays. Tapping it then runs NaviMus's own play/pause handler; otherwise NaviMus's `PlayAlbumIntent`.
- **Playing row:** the playing song's title is in the accent, with three moving bars, which hold still while paused. Shuffle's glyph is in the accent while NaviMus shuffles.
- **Shuffle, download, ⋯, and each row's ⋯ now reach NaviMus's own controls.** On device the search had returned the rebuilt page's own elements instead of NaviMus's. It now skips hidden views and the rebuilt page, walks UIKit subviews as well as the accessibility tree, and anchors a row's ⋯ to that song's title (NaviMus labels a row "title", "circle.dotted", "More").
- **NaviMus's back and ⋯ no longer show through:** a flag on its navigation bar makes `-setAlpha:` and `-layoutSubviews` keep it hidden while a rebuilt page is on top, through UIKit's and SwiftUI's own updates.
- **New options** (Frozio settings → Appearance → **Redesigned pages**): circle behind back (off), circle behind ⋯ (on), circles behind shuffle and download (on), shuffle button, download button, genre / type / year line.
- **FZRemote** (`Source/Core/FZRemote.{h,m}`): one owner for NaviMus's command handlers (all commands, not just next-track) and its Now Playing info. Blocked artists now uses it.
- **Tested (harness):** the stand-in now has NaviMus's row labels and a player that sets Now Playing and handles play/pause. Play → `PlayAlbumIntent`, then Pause with the first row in the accent and moving bars; Pause → NaviMus's toggle ("paused"); Shuffle → NaviMus's own shuffle (glyph in the accent, the shuffled song highlighted); Download → NaviMus's own; ⋯ on "Face The Flame" → that row's own ⋯; back restores the bar.
- **Not tested:** on device. A debug build logs every NaviMus control it considers, with its class.

## Redesign R4c: NaviMus's bar controls (`fix/redesign-naviMus-controls`)

The user's device log of build 35: the top ⋯ stopped working, and shuffle, download and each row's ⋯ found nothing.

- **Cause 1:** on NaviMus's album page Shuffle, Play, Download, Back and More are **items of the navigation bar** (device log, build 34). Build 35 kept the bar at alpha 0 against show-through, and iOS 17 then leaves an alpha-0 view out of accessibility, so those controls were never listed. The bar is now hidden with an **empty layer mask** and doesn't take touches meanwhile. It draws nothing but stays visible to iOS, so its items are listed and activated. `-layoutSubviews` re-applies the mask if UIKit or SwiftUI resets it. Leaving the page, the bar fades in with the pop.
- **Cause 2:** a row's "More" was found but didn't activate. Controls were found and activated in two separate steps, and NaviMus's page was shown and hidden again in between, so SwiftUI rebuilt its accessibility nodes and the ones found first were stale. Now they're found and activated in one step, and buttons are tried before plain elements.
- **The rebuilt page's top buttons** are pinned under the status bar (the window's inset), because the page's own inset now includes NaviMus's bar.
- **Harness:** the stand-in's Shuffle, Download and More moved into its navigation bar, as on NaviMus. The top ⋯ opens NaviMus's menu from the masked bar; shuffle, download and the ⋯ of "Face The Flame" activate NaviMus's own controls on the first try; back restores the bar.
- **Not tested:** on device (iOS 17.5.1). If anything still isn't found, the debug log lists every element with the bar's alpha and item counts.

## Redesign R4d: album page colours and NaviMus's controls on iOS 17 (`fix/redesign-album-match`)

From the user's device test of build 36 (only the top ⋯ worked) and a side-by-side with chroma.pw.

- **Colours, measured on the user's screenshots of the same album** (pixel averages and Oklab):
  - **Field:** chroma.pw is (24, 10, 8) at the foot of the cover, L 0.165 C 0.025; ours was (49, 17, 7), L 0.226 C 0.055, from an uncapped source. The field's lightness ceiling is now 0.165 (0.145 with Increase Contrast), and its chroma lift 0.6 (was 0.34 and 1.3, taurus's). chroma.pw's current field is darker and duller than the fork's.
  - **Genre / type / year line:** chroma.pw draws it at about 90 % white (brightest pixels 234, 216, 213) and semibold, not taurus's tertiary regular. Now Footnote semibold, white 90 %.
  - **Circles:** chroma.pw's read (37, 26, 23) on a (24, 10, 8) field, with a ring (58, 47, 44). Before iOS 26 they're now the redesign's control fallback, thin dark material with a 12 % white ring; the Chrome material used before was invisible on a dark field.
- **NaviMus's controls on iOS 17:**
  - **Song ⋯** is a SwiftUI `Menu`, and iOS 17 opens one only on a touch: activation returned NO on device. Frozio now delivers a **real tap** (`FZRTap`: a UITouch with a digitizer HID event through `-[UIApplication sendEvent:]`, as KIF and EarlGrey do on devices; private selectors and IOKit symbols checked at run time). NaviMus's list first scrolls that row's ⋯ to where the user tapped, past its range if need be, so NaviMus's menu opens there.
  - **Buttons only:** activating NaviMus's plain "More" element (a row's context menu) had put its list into select mode on device, so only elements with the button trait are pressed.
  - **Shuffle**, as Control Center does it: NaviMus plays the album (`PlayAlbumIntent`), then its own `changeShuffleModeCommand` handler gets an `MPChangeShuffleModeCommandEvent` with `kMRMediaRemoteOptionShuffleMode` 3 (items; 1 is off, 2 collections; the harness probe read `shuffleType` 1, 0, 2 for 3, 1, 2). Tapped again while this album shuffles, it turns shuffle off.
  - **Top back and ⋯:** NaviMus's bar stays masked but touchable, so a tap there is a real tap on NaviMus's own back and ⋯, which sit under the rebuilt page's glass ones. That's how the user's ⋯ worked on device.
  - **Download:** NaviMus's Download control if the page shows one (pressed, or tapped); otherwise NaviMus's own ⋯ menu opens and its Download item is picked. If it's named differently, the menu stays open for the user and the log lists its items.
- **FZRemote:** `FZRemoteSendWithOptions` and `FZRemoteEvent` (events with MediaRemote options).
- **Tested (harness, with `-FZHarnessForceTap YES` forcing iOS 17's tap path on iOS 26):** the stand-in's rows now use SwiftUI `Menu`s and its player handles `changeShuffleModeCommand`. A song's ⋯ opened NaviMus's row menu at that row, and its "Play Next" ran. Shuffle → `PlayAlbumIntent` and NaviMus's shuffle handler type 1, with the glyph in the accent and the capsule on Pause. Download → NaviMus's Download tapped in its masked bar. The top ⋯ → NaviMus's menu. Field, meta line and circles as measured.
- **Not tested:** on device. NaviMus's ⋯ menu item names for Download are unknown until the debug log of the first try.

## Redesign R4e: shuffle toggle, download from NaviMus's menu, glass, bars (`fix/redesign-album-actions`)

From the user's device test of build 37 (song ⋯ worked; shuffle played but never stayed green; download opened the wrong menu; the bars didn't move) and the remark that the circles should be Liquid Glass.

- **Shuffle is a toggle.** NaviMus's own shuffle on its album page does the shuffle-play: its header's left button, the crossed arrows in the user's screenshot, which NaviMus labels "Repeat" for accessibility. NaviMus doesn't report shuffle state to the system, so the page keeps it: green until the album is played in order or another album plays. Tapped while green, NaviMus's own `changeShuffleModeCommand` handler gets shuffle mode 1 (off). Harness: green after 3 s (55, 242, 0), white after the second tap, handler type 0.
- **Download is the Download item of NaviMus's album ⋯ menu.** The device log showed the old fallback opened a song's menu: the first "More" button is a row's, since the bar's ⋯ isn't in accessibility. Frozio now taps the ⋯ under the rebuilt page's own ⋯ (the user's finger point) and presses the item the moment it exists. A SwiftUI menu has no items until it shows: its `ViewBasedUIButton` has an empty placeholder `menu`, and its interaction's configuration is empty too. So the menu shows for about 0.26 s (harness). Menu items that refuse accessibility activation are tapped.
- **Glass:** the circles are now made exactly as taurus makes control glass (`FZRGlassInside`: dark style, system capsule shape, no clipping), with `UIGlassEffect` set interactive like the system's glass buttons. Before iOS 26 they keep the measured thin material with a ring. **This Simulator can't render Liquid Glass:** Apple's own `.buttonStyle(.glass)` and `.glassEffect()` also come out as flat tints here (reference in the stand-in's Settings tab), so real glass can only be judged on an iOS 26 device.
- **Bars move with Reduce Motion on too** (three small bars, as chroma.pw's). The page logs Reduce Motion and Reduce Transparency when it opens.
- **Stand-in:** NaviMus's shapes from the logs: the bar carries only ⋯ (a SwiftUI menu with Download), and the header has shuffle ("Repeat"), Play and Love.
- **Not tested:** on device.

## Redesign R4f: download in one tap, no menu on screen (`fix/redesign-download-one-tap`)

From the user's device test of build 38: Download needed three taps and NaviMus's ⋯ menu showed at the top right.

- **Cause (device log):** NaviMus's ⋯ is a SwiftUI menu whose button carries an empty placeholder menu until the menu has shown once ("menu has 0 children"). The first tap opened the menu, but its items never showed up in accessibility, so nothing was pressed; the second tap only closed the menu; the third found the button's menu filled and performed "Download".
- **Fix:** `FZRPerformMenuActionUnseen` (`FZRNaviMusControls`). If the button's menu is still empty, Frozio taps NaviMus's ⋯ and hides the menu's presentation from its first frame (`viewWillAppear:` / `viewDidAppear:` of the `…ContextMenu…` controller: the controller's view and its container at alpha 0, no touches). As soon as it appears, "Download" is performed from the now-filled button menu and the menu is dismissed. Only a menu opened this way is hidden; every other menu shows as before. If the menu has no Download item, it's shown so the user can pick one, and the old accessibility pick runs.
- **Tested (harness, `-FZHarnessForceTap YES`):** one tap → the stand-in's "Download album" ran (try 0, ~60 ms), no menu on screen; a second tap downloaded again; a song's ⋯ afterwards opened its menu normally.
- **Not tested:** on device.

## Redesign R2 + R3: mini player and player (`feat/redesign-player`)

chroma.pw's mini player and player, rebuilt and laid over NaviMus's, with the user's additions: download in place of chroma.pw's +, and every button optional (Frozio settings → Appearance → **Redesigned pages** → Player, Mini player, Player buttons). On whenever the redesigned look is on; "Rebuilt mini player and player" off brings NaviMus's back right away.

- **NaviMus's own hidden:** on iOS 17 NaviMus draws its mini player and player in a `SwiftUI._UIInheritedView` band inside each tab's hosting view (692 → bottom, device probe build 33). Frozio finds it (breadth first, the outermost band reaching the tab bar or the bottom, 40–320 pt tall, or taller while its player is open) and hides it like NaviMus's bar under a rebuilt page: an empty layer mask, no touches. It stays laid out and in accessibility.
- **Mini player (`FZRMiniPlayer.m`):** a glass card 8 pt from the sides and 8 pt above the tab bar, 56 pt tall, radius 24 (taurus's NowPlayingBar values), the iOS 17 grey material with a faint ring. Cover 40 pt (radius 6, or round), title Subheadline semibold, artist Footnote secondary, buttons from the right: next, play/pause, previous, AirPlay, download; the 2 pt progress line with a 24 % track. Tap or swipe up opens the player; swipe left/right changes song. Defaults: play/pause, next, download, progress on; previous, AirPlay, round cover off.
- **Player (`FZRPlayer.m`), presented over the app:** the field from the cover (`FZRArtworkField`), glass ⌄ and ⋯, "Playing from album" line, the cover (radius 12, shadow plate, 0.84 while paused), title Title 2 bold and artist with download beside them, scrubber (seeks with NaviMus's change-position handler, `kMRMediaRemoteOptionPlaybackPosition`), elapsed/remaining in monospaced digits, shuffle / previous / white play circle / next / repeat, footer AirPlay, sleep timer, lyrics, queue. Swipe down closes it.
  - **Shuffle / repeat:** NaviMus's own handlers. MediaRemote options checked in the harness: shuffle 3 → items, 1 → off; repeat 3 → all, 2 → one, 1 → off.
  - **Lyrics:** NaviMus's saved synced lyrics (`FZNaviMusSyncedLyrics`): the sung line bright, the rest at 35 %, following the song unless the user scrolled in the last 3 s; a tapped line seeks there. Without synced lyrics, it offers NaviMus's own player.
  - **Sleep timer (Frozio's own):** 5–60 minutes or end of song, then NaviMus's pause handler. The moon is in the accent while it runs.
  - **⋯ menu:** download, lyrics, sleep timer, "Queue and more in NaviMus's player", and greyed "Coming" entries (speed and pitch, reverb, AutoMix, Music Haptics, artwork modes) until they land.
  - **Queue:** NaviMus's own player, shown as it is; Frozio's bar steps aside and comes back when it closes.
- **Download of the playing song:** NaviMus's player opens out of sight (its band stays masked; the tap is aimed into the tab bar controller's view, and Frozio's player lets touches through meanwhile), its control labelled Download is pressed, or the Download item of its ⋯ menu through the unseen menu (`FZRPerformMenuActionUnseen`), and it's closed with its Close/Dismiss control. The labels are guesses until the device log: the debug log lists NaviMus's player's elements before, open and if left open.
- **Shared pieces:** `FZRRoundButton` moved to `Redesign/Kit` (with `setSymbol:` and a tap menu); `FZRemote` gained elapsed (run on at the rate), duration, artwork and seek; `FZRTapIn` taps what a given view has at a point, whatever lies over it.
- **Tested (harness, iPhone 17 Pro, iOS 26.5, `-FZHarnessLegacyMini YES -FZHarnessForceTap YES`):** the stand-in now has NaviMus's iOS 17 shape (the nested `_UIInheritedView`, 152 pt) that grows into a player with Close and a ⋯ menu with Download, and handlers for next, previous, position and repeat. NaviMus's band hidden, Frozio's bar shown; the player opened from it; pause shrank the cover; next, shuffle (type 1), repeat all/one (types 2/1), seek (144.8 s) reached the handlers; download ran "Download song" in NaviMus's player out of sight in 0.5 s and showed a check; queue showed NaviMus's player and Frozio's bar came back after it closed; sleep timer "end of song" paused at 3:18; swipe down closed the player; the options switches changed the bar live; lyrics followed the demo song.
- **Not done / not tested:** on device. iOS 26's NaviMus mini player (a tab bar accessory) isn't hidden yet, since the user's device is iOS 17. NaviMus's real player labels (Download, Close) come from the first device log. Frozio's player shows no queue of its own (NaviMus doesn't expose it).

## Redesign R2/R3 fixes, bar buttons, album sorts (`fix/redesign-player-device`)

From the user's device test of build 40: NaviMus's own mini player still showed over Frozio's, the tab bar often turned see-through, the mini player and player didn't match chroma.pw's, there were no glass back / ⋯ buttons on NaviMus's pages, and Albums couldn't be sorted by year.

- **Why NaviMus's mini player still showed (device log, build 40):** the band Frozio hid in each tab is only NaviMus's backdrop behind the mini player and the tab bar. NaviMus draws its visible card in the **root hosting view, over the tabs**, so it covered Frozio's bar, which sat in the tab bar controller's view. Taps on the bar never reached Frozio (no "opening Frozio's player" in the log).
  - Frozio now also finds NaviMus's card in the root view (SwiftUI views there, outside the tabs, at least 80 % of the width, 40–320 pt tall, reaching the tab bar's top; or taller while its player is open) and hides it and any NaviMus views within it (SwiftUI may draw the card's contents as loose siblings).
  - Frozio's bar now sits in the window just over NaviMus's root view and under anything presented. Inside the root hosting view, SwiftUI's own gestures also took every touch on the bar (harness: each tap on Frozio's buttons also tapped the card underneath).
  - The debug log lists the root view's bottom views (`player: root … bottom:`) so the next device log shows NaviMus's real card.
- **See-through tab bar:** hiding the whole band took away NaviMus's backdrop behind the tab bar, whose own background SwiftUI makes transparent. The band is now hidden only above the tab bar, and the redesign's material goes back on the tab bar whenever it has no background of its own (before iOS 26).
- **Mini player as chroma.pw's** (the user's screenshot, measured at 390 pt): 55 pt card 8 pt from the sides, corners 18 pt, a 40 pt round cover, "Title • Artist" on one line, the output device under it in the accent (the headphones' name with a glyph; nothing on the phone's speaker), the 2 pt progress line flush along the bottom edge, clipped by the corners. Buttons from the right: play/pause, next (before play/pause, as the user asked), previous, download, AirPlay (in the accent while the sound goes elsewhere). Round cover is now on by default. The bar's own tap and swipes leave its buttons alone.
- **Player as chroma.pw's** (the user's screenshot, 390 × 844): the blurred cover behind everything (option: blurred cover, colours, fluid, the cover), the album name between the glass ⌄ and ⋯, the cover 24 pt from the sides with its top 84 pt under the header's centre, the title Title 1 bold with the explicit badge before the artist, download as an outlined circle, a 4 pt scrubber with no knob until touched, shuffle (accent with a dot when on) / previous / a bare 44 pt play-pause glyph / next / sleep timer at 36, 112, 195, 278, 354 pt, and lyrics, AirPlay and queue at 20, 50 and 80 % of the width. "Right of next" can be the sleep timer (chroma.pw's) or repeat; repeat is also in ⋯.
- **Out-of-sight download fixes (harness):** the polling block read the bar through a weak reference after releasing itself, so the bar stayed untouchable after a download; it now keeps strong locals. The action starts on the next run-loop turn, outside UIKit's delivery of the user's touch. The hidden menu is closed through its interaction (dismissing its controller as well left the status bar hidden), and the status bar is refreshed afterwards.
- **Bar buttons on every NaviMus page** (`Redesign/FZRBarButtons.m`, on each bar layout): back as a bare chevron, every bar button (back, ⋯, NaviMus's sort and filter buttons) in a 44 pt glass circle with the iOS 17 ring, 16 pt from the bar's sides and 8 pt apart, and white (a colour-matrix filter on the button's layers, since NaviMus's SwiftUI items draw in its own tint). A wide text button gets a capsule. Options under Redesigned pages → Bars: circles, white, back without the page's name. Frozio's own settings pages are left alone; on iOS 26 the system's glass stays and only the white applies.
- **Album sorts** (`Redesign/FZRLibrarySorts.m`, Frozio settings → Library → More sort options, on): NaviMus's Albums sort menu gains Year (newest first), Year (oldest first) and Favourites. NaviMus's list type already has `byYear` and `starred` (`Arpeggi.SubsonicAPI.AlbumListType`) and stores the choice in `@AppStorage("albumType")`, so choosing one sets that value and NaviMus loads the list itself. Its `getAlbumList2?type=byYear` request gets `fromYear`/`toYear` (9999→0 newest first, 0→9999 oldest first) when it has none (hooked at `-[NSURLRequest initWithURL:cachePolicy:timeoutInterval:]` and `-setURL:`). The other categories' sorts need the rebuilt Library (R6): NaviMus has no other sort for artists or playlists.
- **Tested (harness, iPhone 17 Pro, iOS 26.5, legacy mini player, stand-in with a root-level card):** NaviMus's card and band hidden, Frozio's bar on top and opening Frozio's player; mini download and player download ran NaviMus's Download out of sight, nothing on screen, status bar kept, the bar tappable afterwards; player layout as measured; bar buttons in circles, white, 16 pt / 8 pt, the sort menu still opening from the moved button; the sort menu showed the three new entries, Year (newest first) stored `byYear` and the request went out with `fromYear=9999&toYear=0`.
- **Not tested:** on device. Whether NaviMus's card is found as the stand-in's is (the root-view log line will show it); `albumType`'s stored raw type and suite on device (logged at launch); NaviMus's player labels for Download and Close.

## Fluid artwork, chroma.pw's ⋯ menu, circle switches, year sort fix (`fix/redesign-player-chroma`)

From the user's device test of build 41 (the player now shows as Frozio's) and chroma.pw's screenshots.

- **Year sort did nothing, and its check showed beside NaviMus's own (device log, build 41: `albumType` empty).** NaviMus's `@AppStorage` key for the album sort isn't `albumType`, and Swift keeps short key literals inside its code, so it can't be read from the binary. Frozio now learns it: at launch from the one standard-defaults key holding an `AlbumListType` case, or when NaviMus writes one (`-[NSUserDefaults setObject:forKey:]`), and keeps it (`fz.library.albums.storageKey`, forgotten if it holds nothing). Year and Favourites write that key, so NaviMus's own picker has no check and only Frozio's entry has one. Before the key is known, choosing Year says to pick one of NaviMus's sorts once. Harness (a stand-in key Frozio didn't know): the hint showed, Recently Played taught the key, Year stored `byYear` and NaviMus's request went out with `fromYear=9999&toYear=0`, one check in the menu.
- **Library bar glitches while scrolling (the user's "old buttons seep through"):** reproduced in the harness. Once the bar had its scrolled blur, the back chevron vanished in its circle; the circle inside UIKit's back button, which also carries a `destIn` mask view, blanked it. Back's circle now sits inside the chevron's own view (`_UIModernBarButton`), behind it, and the white filter goes on the chevron's images. A filter on the mask view is never set. The buttons are moved without resetting their transform on every pass (no jumping). Checked at the top, scrolled, after popping back to Library (no leftover circle) and after pushing again.
- **Circle switches everywhere** (Redesigned pages → Bars): circle behind back (also ⌄ in the player and back on the album page; now on by default), circle behind ⋯ (player and album page too), circles behind other bar buttons (NaviMus's sort and others beside ⋯), white bar buttons, back without the page's name.
- **Frozio's own Settings button** (top right of NaviMus's Settings) gets no circle and keeps its look.
- **Fluid artwork, chroma.pw's player background** (`Redesign/Kit/FZRKawarp.m`): chroma.pw's credits name Kawarp (`better-lyrics/kawarp`, MIT) for its fluid background. Frozio ports it to Metal: the cover at 128 × 128, dark areas tinted (0.157, 0.157, 0.235) at 15 %, 8 Kawase passes (offset i + 0.5), then per frame a two-octave simplex domain warp weighted to the centre and an output pass with vignette, saturation 1.5 and grain 0.008; a new cover crossfades over 1 s on a cosine. 30 fps, one pixel per point, held under Reduce Motion. It's the player's default background (others: blurred cover, colours, cover). **Fluid artwork** page: chroma.pw's preset names (Default, Soft, Calm, Slow, Vivid, Bright, Fast) and Speed, Warp, Grain, Blur, Saturation, Brightness as percents of Kawarp's defaults. chroma.pw's own preset numbers aren't in its strings, so the presets other than Default are Frozio's readings of their names.
- **⋯ menu as chroma.pw's** (its screenshot): Add to playlist, Add to Queue and Share as a row; Speed, pitch and reverb (NaviMus's own rate handler, 0.5–2×, when it has one); AutoMix (None); Music Haptics; Artwork (Cover Art; Animated, Visualizer, Auto and the shaders greyed); Lyrics (Default); Love (NaviMus's `LikeSongIntent`, in place of Spotify's taste-profile entry); More (download, sleep timer, repeat, NaviMus's player). Add to playlist and Add to Queue press NaviMus's own items in its player out of sight (the playlist one closes Frozio's player first, as NaviMus presents its picker). Share sends title, artist and cover.
- **chroma.pw's dylibs in the folder** (`SpotifyGlassAppGroups`, `SpotifyGlassAutoMix`, `SpotifyGlassAutoMix26`) are its app-group storage and AutoMix transition planner; its player code isn't among them. They're PolyForm Strict: values, names and behaviour only, no code.
- **Tested (harness):** as above, plus the menu's Add to Queue ran NaviMus's item out of sight and Speed 1.5× reached the rate handler; the Fluid artwork page and its sliders.
- **Not tested:** on device; whether NaviMus registers a rate handler (otherwise Speed is greyed); NaviMus's real item names for Add to Playlist / Add to Queue. Animated artwork, the visualizer and its shaders, AutoMix, Music Haptics and lyrics shaders are greyed until built (chroma.pw's shaders are PolyForm and can't be copied).

## Queue in the player, chroma.pw's lyrics look, album scroll blur, bar fixes (`feat/redesign-queue-lyrics`)

From the user's device test of build 42 and chroma.pw's lyrics screenshot.

- **Queue in Frozio's player** (`Player/FZRQueue.m`, `FZNaviMus.queue`): NaviMus's `Arpeggi.AudioManager` is an NSObject; Frozio keeps it from its own `-handleItemChanged`, `-updateCurrentRoute` and `-playerDidFinishPlaying:` and reads `_currentQueueItem`, `_primaryQueue`, `_secondaryQueue`, `_continuousQueue`, `_queueHistory` (Deques of `QueueItem { song: Song }`) by Swift reflection, read-only. The queue button no longer opens NaviMus's player: the cover moves up into a 72 pt thumbnail with the title beside it, and the list fills the space above the bar in NaviMus's sections ("Playing Next", "Next from: <album>", "Autoplay"), covers from the server. A song tapped is reached with NaviMus's own next-track handler, once per song before it. The list follows NaviMus's changes.
- **Lyrics as chroma.pw's** (its screenshot): the same compact header (72 pt thumbnail, title and artist beside it, download at the right, never over the title), then big bold lines on the left: the sung one white, the others at 30 % and blurred by 1.4 pt per line of distance up to 6 pt, the sung line 28 % down, a 10 % fade at the top and bottom, 3 s before following again after a scroll. Values from taurus `SGRKaraokeView.m` / `LyricsLook.m` (GPL-3.0; its "Apple Music" look: 30 pt, 24 pt apart). The thumbnail brings the cover back.
- **Album page:** the cover blurs as the list scrolls over it, up to 24 pt once half the hero has gone by.
- **Year sort direction:** going from Year (newest first) to Year (oldest first) wrote the same `byYear` again, which NaviMus didn't see as a change (device log, build 42; its key is `directAlbumsSort`). The value is now cleared for 0.15 s and set again, so NaviMus reloads with the other range.
- **Bar buttons:** Frozio's Settings button is now a button of Frozio's own carrying its identifier, so it never gets a circle or the white filter (it did on device). Circles centre on the glyph SwiftUI draws (⋯ wasn't always in the middle of its item).
- **On licences:** the user asked to take chroma.pw's code regardless of its licence. Frozio doesn't copy PolyForm Strict code; it rebuilds the look and behaviour, with taurus's GPL code where taurus has it.
- **Tested (harness):** the queue read from the stand-in AudioManager (same field names), shown in sections, a tap three songs ahead reached it; lyrics look with the demo song; Frozio's Settings button without a circle and still opening Frozio settings; Year newest → oldest sent `fromYear=0&toYear=9999`.
- **Not tested:** on device, in particular reading NaviMus's real AudioManager (the debug log prints the queue's counts).

## Lyrics blur, queue on device, library chips, NaviMus's cover bug, bar lift (`fix/redesign-device-43`)

From the user's device test of build 43.

- **Lyrics blur came out as blobs in dark boxes** (CAFilter's gaussian blur on the UILabels' own layers, with normalized edges). Each line now sits in a view of its own with 12 pt of room around its text and the blur goes on that view, eased over 0.6 s from where it is on screen, as taurus's `SGRKaraokeLineView` does. Harness: soft blur, no boxes.
- **Queue said "shows once a song has started" on device** (log: AudioManager never found). Swift calls AudioManager's own methods directly, so hooking them never ran. Frozio now finds it when it registers for notifications at launch (`-[NSNotificationCenter addObserver:selector:name:object:]` with an AudioManager observer), and the open queue reloads whenever the song changes. Harness: the stand-in now calls its methods directly too and registers an observer; the queue showed 6 + 1 songs.
- **NaviMus's wrong covers in Library** (the same cover on several albums, changing while scrolling): NaviMus's `HostingCollectionViewCell<V>` reuses its `hostingController` for the next album and its `CoverArtView` loads the cover into `@State` once on appear, so a reused cell keeps the old cover. When such a cell is about to be reused Frozio takes its hosting controller away (ivar `hostingController`), so NaviMus makes a fresh one; table rows hosted with `UIHostingConfiguration` get their configuration cleared before reuse (SwiftUI's own list cells are left alone). Frozio settings → Library → **Fix wrong covers in lists** (on). Harness: the bug reproduced with the same shapes (album 20 showing cover #1) and was gone with the fix (album 22 shows #22).
- **Library section chips** ("#", "A", "2017") in the same glass as the bar buttons: SwiftUI draws the chip's fill in the header as a round layer with a background colour; Frozio hides it and puts a glass circle behind the header's content, under the chip's text (headers told by their supplementary kind, not class; styled after SwiftUI draws them). Off with "Circles behind other bar buttons".
- **Bar buttons on pages with a search field** sit 4 pt higher, clear of the field once the large title has collapsed.
- **Search's account button flickering:** not reproduced in the harness (its button stayed in place through scrolling). The debug log now lists every page's bar buttons (class, label, frame, drawn views) once, to find what NaviMus's is.
- **Not tested:** on device.

## Album rows queue the album, lyrics always, queue covers at once, mini player artist, bar top (`fix/redesign-device-44`)

From the user's device test of build 44.

- **A song tapped on the album page played alone** (NaviMus's PlaySongIntent): no queue in Frozio's player or NaviMus's. Frozio now taps NaviMus's own row for that song on its page under the rebuilt one (its title, a plain element, scrolled under the finger, tapped rather than activated), on the next turn of the run loop; NaviMus plays the album from there with the rest queued. PlaySongIntent stays as the fallback. Harness: the stand-in's row was tapped and played the album from that song.
- **Lyrics "No synced lyrics yet" for most songs:** Frozio fetches them itself (`Player/FZRLyricsFetch.m`): NaviMus's saved lyrics, then the user's server (OpenSubsonic `getLyricsBySongId`, synced structured lyrics), then LRCLIB (title, artist, album and length only; generic user agent; Frozio settings → Lyrics → "Look up lyrics on LRCLIB", on). Fetched as each song starts, so they open at once; kept for the session. When a song changes with the lyrics open, the new song's are fetched instead of closing them.
- **Queue covers appeared after a music-note placeholder:** one session-wide cover cache; the playing song's artwork goes in at once under its cover ID, every queued cover loads in the background as each song starts (open or not), and a plain dark tile stands in until one arrives.
- **Mini player:** title and artist are separate labels; the artist keeps up to 60 % of the line and the title truncates first, so the artist shows beside a long title.
- **Top buttons cut off** (build 44 lifted them 4 pt on pages with a search field, past the bar's top): the lift now applies only once the large title has collapsed, and the views between a lifted button and the bar no longer clip it.
- **Wrong covers in Library:** the reuse fix didn't run on device (no reused cell matched). The debug log now names each kind of reused cell, its content configuration and ivars once, to find the one NaviMus's lists use.
- **Not tested:** on device.

## NaviMus's wrong covers (in-place reconfigure), Library back button (`fix/redesign-device-45`)

From the user's device test of build 45.

- **Wrong covers in Library** (an album showing another album's cover, e.g. one from 2093): the build 45 debug log showed NaviMus's list cells are plain `UITableViewCell` / `UICollectionViewCell` / `UICollectionViewListCell` with `UIHostingConfiguration` (`UIKit._UICustomContentConfiguration` in ObjC). NaviMus re-sorts and reconfigures the visible cells in place, without reuse; SwiftUI keeps the old row's `@State` and so the old cover. Frozio now clears the cell's configuration first whenever a new SwiftUI configuration replaces one on a NaviMus cell, so the row starts fresh. Same setting (Library → Fix wrong covers in lists). Harness: re-sorting in place showed "album 39" with cover #0 before, #39 after; scrolling unaffected.
- **Library's back button** was a wide capsule with the previous page's name ("Library"): the bare chevron is now set on the page before as well, the back button's title is hidden while circled, and back is always a 44 pt circle. Harness: a bare circle at the top and when scrolled.
- **Not tested:** on device.

## Playlists like albums, taurus's lyrics sources, playing bars, artist page bar (`feat/redesign-device-46`)

From the user's device test of build 46.

- **Playlist page** (NaviMus's `Arpeggi.PlaylistDetailViewWrapper { playlist }`, device log): the album page, laid over it the same way, from `getPlaylist`: the playlist's cover as the hero, its name, owner and "24 songs · 1 h 13 min", shuffle / Play / download, and every song row with its own cover at the start (as in the user's screenshot), loaded once per session. Play uses NaviMus's own Play on its page, falling back to PlayPlaylistIntent; a row tap taps NaviMus's own row, so the playlist queues. Frozio settings → Redesigned pages → Album → **Playlists like albums** (on).
- **The playing bars stood still** after leaving the app and coming back (iOS drops a view's animations in the background): they start again when the app is active again, on album and playlist pages.
- **Lyrics sources from taurus** (`Source/Lyrics/Taurus`, GPL-3.0 @ fe3211c): BiniLyrics, Musixmatch, Unison, NetEase, LRCLIB, QQ Music and KuGou, asked by the song's title, artist, album and length (NaviMus's songs have no Spotify id, so every song is asked as taurus asks a local file). The player's ⋯ has **Lyrics Source** as in taurus: Automatic (NaviMus's saved lyrics, your server, then taurus's sources in taurus's order, the first with timed lines answering), NaviMus, Your server, each of taurus's sources, and **Imported LRC** (an .lrc file picked for the song). A song's choice is kept for good and the lyrics reload from it at once. Spicy Lyrics is left out: it matches only by Spotify's track id. "Look up lyrics online" (Frozio settings → Lyrics) switches the online sources off in Automatic.
- **Artist page:** an empty glass capsule sat in the middle of the bar: NaviMus puts the artist's name there as the bar's title item, hidden until the list scrolls, and Frozio gave it a capsule. Items wider than 100 pt are now left alone.
- **Tested (harness):** playlist page from a mock `getPlaylist` (covers on every row, row tap played the song, bars moving after leaving and reopening the app); artist page stand-in with a hidden 220 pt title, no capsule; Lyrics Source menu, choosing LRCLIB kept and asked at once. Each source asked for a well-known song: LRCLIB 39 lines, Musixmatch 39, BiniLyrics 38, QQ Music 53, KuGou 49; Unison and NetEase had none for it (Unison's catalog is small; NetEase wants the length within 3 s).
- **Not tested:** on device.

## Search account button, the user's settings as defaults, album field colour (`fix/redesign-device-47`)

From the user's device test of build 47.

- **Search's account button flickered or vanished while scrolling.** The device log showed it is a UIKit bar button (`_UIButtonBarButton`) holding a 26 pt picture. NaviMus adds and rebuilds it inside the bar's button row, which lays out only that row, not the bar, so Frozio styled it only on the bar's next layout (while scrolling) and it jumped between its own place and Frozio's. Frozio now also styles the bar whenever its button row lays out (`_UIButtonBarStackView layoutSubviews`), centres the circle on such a button's middle rather than on its picture (which moves while UIKit lays it out), and leaves pictures out of the white glyph filter. Harness: the stand-in now has NaviMus's sort button and a picture account button; before, the account button wasn't styled at all; after, it sits in its circle, steady through 12 frames of scrolling.
- **Defaults** are the user's own settings export: redesign on, accent 0x07D2FF also in NaviMus, lock screen lyrics on, circles behind back, ⋯ and other bar buttons but not behind shuffle and download, mini player without download and swipe, player with the Fluid background, sleep timer on, the right slot's second choice, no AirPlay or download button. Settings already changed on a device keep their values.
- **Album page colours (chroma.pw's ADL page, the user's screenshot):** chroma.pw's field is rgb(32, 10, 6) there (Oklab L 0.179, C 0.040) and stays that colour from under the hero down past the rows; Frozio's faded to black from mid-screen. The album page's field is now flat, and the lightness ceiling is 0.175 (between this and the earlier measurement, 0.165).
- **Not tested:** on device.

## Animated covers, Visualizer, Lyrics shaders (`feat/redesign-motion`)

The user's picks from the player's greyed-out ⋯ items (AutoMix, Crossfade, speed/pitch/reverb and Music Haptics skipped for now).

- **Animated covers** (`Player/FZRAnimatedCovers.m`): from a folder on the user's own WebDAV or web server holding the dumped motion covers as `Artist - Album.mp4`. Frozio settings → Appearance → Redesigned pages → **Animated covers**: the folder's address, and a user name and password if the server asks (the password in the Keychain, not in exported settings); "Covers found" shows how many it listed and looks again on a tap. The folder is listed by WebDAV PROPFIND, else from the server's HTML index, every 15 min at most. Matching is loose: case, accents, punctuation, bracketed parts ("(Deluxe)", "(Unreleased)") and featured artists don't count; any of an album's credited artists will do; the file's album may be the start of the album's name ("Yeat - 2093.mp4" for "2093 (Unreleased)"). A match is downloaded once into the caches and loops muted in place of the still cover: in the player (⋯ → Artwork → **Auto**, the default: animated when the album has one, else the cover; **Animated**; **Cover Art** keeps the still) and in the album page's hero, under its scrim and dissolve.
- **Visualizer** (`Kit/FZRVisualizer.m`, Frozio's own Metal shaders under chroma.pw's names): ⋯ → Artwork → Visualizer shows, in the cover's place, **Bars** (a mirrored 28-bar spectrum), **Nebula** (domain-warped clouds), **Halo** (the cover in a circle ringed by the spectrum), **Poster** (the cover posterised into its own colours, pushed by the beat) or **Cut** (the cover in strips sliding with their part of the spectrum); **Shuffle Shaders** (default) moves on every 20 s with a crossfade. Colours come from the cover's palette.
- **The music's levels** (`Player/FZRAudioLevels.m`): an MTAudioProcessingTap on NaviMus's AVQueuePlayer items (added to NaviMus's own audio mix when it sets one, else to a mix of Frozio's once the item's audio track is known), passing the sound through untouched; a 1024-point FFT into 32 octave-spaced bands, bass/mid/treble, level and a beat. Without a tap (AirPlay, a stream it can't see) a steady made-up pulse keeps the visuals moving while music plays.
- **Lyrics shaders:** ⋯ → Lyrics → **Lyrics shaders** puts the Nebula shader, moving with the music, behind the lyrics (Default leaves the background as it is).
- **Tested (harness):** loose matching (8 cases: "2093 (Unreleased)", "Yeat, Drake", "Donda" ↔ "Donda (Deluxe)", "MUSIC - SORRY 4 DA WAIT" ↔ "MUSIC" matched; "Lyfë" and another artist's "2093" didn't); a mock WebDAV folder with a generated video: the album page's hero and the player played it; Artwork menu with every Visualizer style (Bars, Halo, Cut checked on screen); the tap on an AVQueuePlayer playing a 220 Hz + 3 kHz tone lit the matching bands; Lyrics shaders behind the demo song's lyrics.
- **Not tested:** on device: the tap on NaviMus's real items and streams, and the user's own server.
- **Animated covers full screen** (the user's follow-up; on by default): in the player the video fills the whole screen behind everything, darkened at the top and bottom for the controls, and the cover's window steps aside; lyrics and the queue keep the small thumbnail. ⋯ → Artwork → Animated covers → **In the cover window** (or Frozio settings → Player → "Animated covers full screen" off) keeps it in the cover's window. Harness: the test video filled the player with the controls readable over it.

## Shaders behind the player, lyrics styles, still cover per album, no zoom on pause (`feat/redesign-motion-2`)

From the user's screenshots of chroma.pw's Workshop page.

- **The cover zoomed in and out on play/pause** ("Smaller cover while paused"): now off by default (Frozio settings → Player can turn it back on).
- **Visualizer behind the player:** as chroma.pw's shaders, it now draws behind the whole player with the cover on top, darkened at the edges for the controls, and leans with the phone (CoreMotion gravity). Bars became an LED wall lit from the middle by the spectrum; Halo became rings stepping out from the cover, quicker with the music and on each beat; Nebula is smoke thickening with the bass; Poster and Cut spread the cover across the screen.
- **Lyrics styles** (⋯ → Lyrics; `Player/FZRLyricsStyle.m`): Default; chroma.pw's built-in Poster, Neon, Highlighter, Subtitles and Novel, from the values its app ships for them (font, weight, case, tracking, sung/unsung colours and gradient, outline, alignment, anchor, glow, dim, blur, highlight or pill); and Frozio's own Inferno (fire), Hologram (projector cone and scanlines), Chrome (synthwave sun and grid, metallic letters) and Blueprint (blue grid, outlined lines), each with a shader behind the lines that moves with the music. chroma.pw's Workshop shaders and lyrics shaders are downloaded from chroma.pw's own service with an account (lyrics shaders with its Plus) and written against its PolyForm code, so Frozio doesn't fetch or include them.
- **Still cover for an album** (⋯ → Artwork → Animated covers → "Still cover for this album", e.g. "2093 (P3)" matched by "Yeat - 2093.mp4"): kept for good for every song of that album, in the player and on the album page; "Animate this album again" undoes it; Frozio settings → Animated covers → "Albums on their still cover" counts them and animates them all again on a tap.
- **Tested (harness):** Halo's rings around the cover behind the player; Neon, Inferno and Chrome on the demo song's lyrics (Inferno darkened under the controls after the first look).
- **Not tested:** on device; Hologram, Blueprint, Poster, Highlighter, Subtitles and Novel only built, not looked at.
