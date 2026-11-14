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
