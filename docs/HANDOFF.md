# HANDOFF: where Frozio stands (2026-11-15)

Read this first in a new session, then `REDESIGN_PLAN.md`, `FEATURES.md` (newest entries at the bottom), `DECISIONS.md` and `LICENSES.md`.

## The user and how to work

- Owner: **xFr0z3n**. They test on an **iPhone 13, iOS 17.5.1**, with an external signer. The target look is chroma.pw's **iOS 26 Liquid Glass** redesign; on iOS 17 glass falls back to the grey translucent material, as chroma.pw does.
- **Commit, PR and merge without asking** (standing permission). Never push to `main` directly; always use a branch and a PR.
- **Build IPAs only on GitHub** (`gh workflow run build.yml --ref main -f debug=true`). Never build the tweak locally with Theos and never download the IPA here. Give the user the release link. **The Simulator harness can always be built and run locally.**
- The user wants **everything 1:1 with chroma.pw** (spoti.pw), plus more options (everything customizable). They send device screenshots and `frozio.log` (Share log, debug build) after each build. Measure screenshots (pixel averages, Oklab) rather than eyeball them.

## Machine

- macOS 26.7 on an **AMD (x86_64) Mac**. Xcode 26.5, iOS 26.5 Simulator only. Homebrew doesn't support this Mac; tools are in `/usr/local/bin` (`ldid`, `insert_dylib`, `ipsw`, GNU make 4.4.1), Theos in `~/theos`, env in `~/.zprofile` (run shell builds via `zsh -lc`).
- **NaviMus (arm64 device-only) can't run in the Simulator here.** UI work uses `Harness/`: Frozio's sources plus a SwiftUI stand-in shaped like NaviMus (`Harness/NaviMusStandIn.swift`), a mock OpenSubsonic server (`python3 Harness/mockserver.py`, port 4533) and stand-in intents and a player.
- `xcrun -f` / `xcodebuild -find` crash (bus error) on this Mac, so `swiftc` is called by its toolchain path. `xcodebuild -downloadPlatform` crashes too.
- **The Simulator can't render Liquid Glass** (Apple's own glass is flat here too). Judge glass only on an iOS 26 device.
- Harness tips:
  - `make -C Harness`, then `xcrun simctl install booted Harness/build/FrozioHarness.app`, then launch `com.frozio.harness`
  - launch arguments: `-FZHarnessOpenSettings YES`, `-FZHarnessLyricsDemo YES` (+ `-FZHarnessDemoStart n`), `-FZHarnessLight YES`, `-FZHarnessMaterialBars YES` (pre-26 bars), `-FZHarnessForceTap YES` (iOS 17's tap path), `-FZHarnessShuffleProbe YES`
  - Verify with `xcrun simctl io booted screenshot` (the panel's screenshots lag). Switch taps need ~0.2 s duration.

## Done and verified on device

Phase 1 pipeline; Frozio settings; accent colour and accent in NaviMus; CloudKit guard; About page (licenses, export/import, reset); lock screen lyrics; blocked artists; rolling single draft release (`frozio-build`).

## Redesign (the current work, see `REDESIGN_PLAN.md`)

Approach: Frozio **rebuilds** NaviMus's screens (strategy a), laid **over** NaviMus's own pages, from taurus's GPL `Redesigned/` code. Default off ("Redesigned look") until the user confirms; then it defaults to on.

- **R1 app look** (dark, bars, accent): merged.
- **R4 album page** (`Source/Redesign/Album/FZRAlbumPage.m`): merged, latest **build 38**, awaiting the user's test. State:
  - Look: taurus `SGRArtworkField` port (`FZRField/FZRFlow/FZRFluid`); field constants tuned to chroma.pw's measured colour (Oklab ceiling 0.165, chroma lift 0.6); meta line Footnote semibold 90 % white; bare back chevron, glass ⋯; options page "Redesigned pages".
  - Play/Pause: NaviMus's `PlayAlbumIntent` / its play-pause handler. Track tap: `PlaySongIntent`. Artist: `OpenArtistIntent`.
  - Shuffle: NaviMus's own header shuffle (accessibility label **"Repeat"**); the page keeps the green state; off via NaviMus's `changeShuffleModeCommand` (MediaRemote shuffle mode 1 off, 3 items).
  - Download: the Download item of NaviMus's **album ⋯ menu**, tapped open at the rebuilt ⋯'s position and pressed as soon as it shows (SwiftUI menus have no items until shown).
  - Song ⋯: a real tap (`FZRTap`) on that row's NaviMus "More" button, aligned under the finger. **Verified working on device (build 37).**
  - Top back and ⋯: NaviMus's bar is masked (invisible) but touchable, so taps reach its own buttons.
- **Next phases:** R2 mini player plus R3 player together (NaviMus draws both in one SwiftUI overlay on iOS 17, a `SwiftUI._UIInheritedView` band over the tab bar). The user wants: a download button instead of "+", a customizable button set (play/pause, next, AirPlay, …), a progress line, and every player button hideable (sleep timer, AirPlay, …). Then the artist and playlist pages, Home (speed dial grid, Recents), Library (every sort in every category, e.g. albums by year), Search, and the ⋯ menu features.

## Key facts about NaviMus 1.6.1 (all in `FEATURES.md` / `REDESIGN_PLAN.md`)

- Every page is `NavigationStackHostingController<AnyView>`. `FZProbe`/`FZNaviMus` (Swift) read the root view: `Arpeggi.AlbumViewWrapper` (`albumID`), `ArtistWrapper` (`artistId`), `PlaylistDetailViewWrapper`, `Screen.LibraryRoutes`.
- SwiftUI's NavigationStack uses `setViewControllers:animated:` (hooked along with push).
- App Intents `Play{Album,Artist,Playlist,Song}Intent`, `Open…Intent`, with entities found by ID via their queries.
- Server access: Frozio reuses NaviMus's own login from its requests (`FZServer`, seen at `-[NSURLSessionTask resume]`; Swift async skips `dataTaskWith…`).
- The library store `Application Support/Arpeggi/<db>/database/db.sqlite` is a partial cache (songs only for opened albums).
- `arpeggi://` has no deep links.
- iOS 17 doesn't open SwiftUI menus on accessibility activation (needs a real tap). An alpha-0 bar drops out of accessibility. Pressing NaviMus's plain (non-button) "More" element triggers select mode, so only button-trait elements are pressed.
- Shared modules: `Core/FZRemote` (NaviMus's command handlers and Now Playing), `Redesign/FZRNaviMusControls` (page interception, control press/tap, bar masking, menu items), `Redesign/FZRTap`.

## License rule

Copy code from taurus (GPL-3.0), spoti.pw ≤ v0.21.1 and amperfy only, with attribution rows in `LICENSES.md`. chroma.pw / current spoti.pw (PolyForm Strict) give **values and behaviour only**; their dylibs aren't in the workspace (only string and class dumps in `work/dumps/spotipw-bin/`). `spoti.pw/harness/` is a visual reference only.
