# REDESIGN_PLAN: chroma.pw's redesign, 1:1, on NaviMus

Approved by the user on 2026-11-14: Frozio **rebuilds NaviMus's screens** in the redesign instead of restyling them. Hooks can't change the inside of NaviMus's SwiftUI screens; its Swift code is symbol-stripped (`PHASE0_REPORT.md` §1). This is strategy (a) of Phase 0, which was already approved alongside (b).

- **Target look:** chroma.pw's redesign as on iOS 26 (Liquid Glass). On the user's iPhone 13 (iOS 17.5.1) every glass shape falls back to the redesign's grey translucent material (`material.glass.fallback`), exactly as chroma.pw itself does there.
- **Code:** adapted from taurus `tweak/Sources/Redesigned/` (GPL-3.0, about 26k lines: `Kit/`, `Album/`, `Artist/`, `Playlist/`, `Home/`, `Library/`, `Search/`, `Player/`, `NowPlayingBar/`, `Navbar/`, `Lyrics/`, `ContextMenu/`). chroma.pw's release dylibs (`work/dumps/spotipw-bin/`) give values and behaviour only (PolyForm Strict, `LICENSES.md`).
- **Default:** the "Redesigned look" switch stays off until the user confirms on device that the redesign works as intended, then it defaults to on.

## How a rebuilt screen works

1. **Interception.** NaviMus pushes a SwiftUI hosting controller for each screen. Frozio recognises the screen by the hosting controller's Swift type name (verified with the debug screen census, never by view index). With the redesign on, it pushes or presents its own page instead.
2. **Data.** Read-only from NaviMus's own library store: SwiftData, SQLite under `Application Support/Arpeggi/<database id>/database/` (folder case 5 in the 1.6.1 binary, see `FEATURES.md` "lock screen lyrics"). This works offline and needs no credentials. The schema (table and column names) comes from the user's device through Share log first (step R0a). Artwork comes from NaviMus's own cover cache (`cover_art`).
3. **Playback** goes through NaviMus, never around it:
   - Transport (play, pause, next, previous, seek, shuffle, repeat) uses NaviMus's own `MPRemoteCommandCenter` handlers, kept as they register. This is the same path as blocked artists, already verified on device.
   - State (title, artist, artwork, elapsed, rate) comes from NaviMus's Now Playing info (already hooked).
   - "Play this album/playlist/artist/song" is spike R0b: NaviMus's `arpeggi://` scheme and its App Intents (`PlayAlbumIntent`, `PlayPlaylistIntent`, `PlayArtistIntent`, `PlaySongIntent`, `OpenAlbumIntent`, …; `CLASSES.md`).

## Phases (one PR each, harness-tested, then a GitHub build for the device)

| # | What | Screens (user's comparison screenshots) | taurus source to adapt | Needs |
|---|---|---|---|---|
| R0a | Library store schema | none: a debug Share log section with table and column names, no data | none | one device log |
| R0b | "Play X" path | none: spike | none | disassembly of the `arpeggi://` handler and intents |
| R0c | Screen interception | none: the census names the hosting controller of every screen | none | debug build |
| R1 | Kit plus top chrome everywhere | round glass back and ⋯ buttons on every NaviMus bar, as on chroma.pw | `Kit/` (`SGRGlass`, `SGRField`, `SGRHeaderInfo`, `SGRActionRow`, …) | none |
| R2 | Mini player | Frozio's glass bar over the tab bar. Customizable: play/pause only, plus next, AirPlay, add. Progress line along its bottom edge | `NowPlayingBar/` | none (remote commands + Now Playing) |
| R3 | Player | artwork field, glass ⌄ and ⋯, cover, title plus add, scrubber, controls, timer, lyrics/AirPlay/queue row. The ⋯ menu lists every feature (gated ones too), each linked as it lands | `Player/` (Artwork, Controls, Footer, Header, Menu, Morph) | R1, R2 |
| R4 | Album, playlist and artist pages | full-bleed artwork hero, centred title, artist, "genre · type · year", shuffle / Play capsule / + (artist: info / play / follow), track rows with ⋯ | `Album/`, `Playlist/`, `Artist/`, `Kit/SGRActionRow` | R0a, R0b, R0c |
| R5 | Home | large "Home" title, glass filter + profile capsule, **speed dial** grid (two columns of pinned tiles: artists, albums, playlists, songs), Recents carousel, shelves (recently played, frequent, newest) | `Home/` | R0a, R0b |
| R6 | Library | the redesign's one-title library; **every sort option in every category** (e.g. Albums by year, which NaviMus can't do), kept per category | `Library/` | R0a |
| R7 | Search | glass search field, the redesign's results | `Search/`, `Navbar/SearchField` | R0a |
| R8+ | ⋯ menu features | speed, pitch and reverb; AutoMix; Music Haptics; artwork modes (animated, visualizer shaders); lyrics modes; … | `Player/`, `Lyrics/`, matrix rows | per feature |

Tab order needs no work: NaviMus's own tab settings can already reorder tabs, and the user arranges them like chroma.pw.

## Device findings (probe build 33, 2026-11-15)

- **Pages** (Swift reflection of the type-erased `NavigationStackHostingController<AnyView>`): album `Arpeggi.AlbumViewWrapper` (`album: Arpeggi.Album`, `albumID: String?`); artist `Arpeggi.ArtistWrapper` (`artist`, `role`, `artistId`); playlist `Arpeggi.PlaylistDetailViewWrapper` (`playlist`); every Library category `Arpeggi.Screen` (`library: Screen.LibraryRoutes`).
- **Intents:** `PlayAlbumIntent` (`album: AlbumEntity?`, `albumSearchTerm: String?`), `PlayArtistIntent`, `PlayPlaylistIntent`, `PlaySongIntent` (each an entity plus a name), `PlayGenreIntent` (`genre: String`), `OpenAlbumIntent` / `OpenArtistIntent` / `OpenPlaylistIntent` (`target`), `RandomMixIntent`, `ResumeMusicIntent`, `LikeSongIntent`. Entities have queries (`AlbumEntityQuery`, …) for looking them up by ID.
- **Player:** not a presented screen. On iOS 17 NaviMus draws the mini player and the full player in one SwiftUI overlay of the tab root (`SwiftUI._UIInheritedView`, y 692–844 on a 390×844 screen, over the 83 pt `UITabBar`). So Frozio's mini player (R2) opens Frozio's player (R3); they ship together.
- **Downloads:** NaviMus's `DownloadManager` exposes only its URLSession delegate. Frozio's download buttons trigger NaviMus's own download control through accessibility (labels logged by the album page probe), so NaviMus keeps doing the downloading.
- **Rebuilt pages lie over NaviMus's pages.** NaviMus still pushes its page and Frozio covers it, so back and swipe-back pop NaviMus's page and its SwiftUI navigation path never goes out of step. Navigating elsewhere from a rebuilt page uses NaviMus's `Open…Intent`s.
- **Server access** reuses the server address and token of NaviMus's own requests (captured in memory, never logged or stored), so Frozio never reads the keychain.

## User requests on top of chroma.pw (2026-11-15)

- **Download, not "+":** where chroma.pw has a "+" (add to library) next to Play, in the mini player and in the player, Frozio has a download button, as NaviMus's playlists do.
- **Everything customizable.** Every button of the mini player (play/pause, previous, next, AirPlay, download, progress line) and of the full player (sleep timer, AirPlay, lyrics, queue, shuffle, repeat, download, ⋯ menu entries, …) can be shown or hidden in Frozio settings, and so can each part of each rebuilt page (Home shelves, speed dial, meta line, …).

## Risks, said up front

- **Features of NaviMus's own screens** have to be carried over into each rebuilt screen (downloads, ratings, offline state, context actions), or that screen loses them. Each phase lists what it carries and what it doesn't.
- **The library store schema** is NaviMus's private SwiftData model. It's read-only and pinned by the version gate (1.6.1, `LC_UUID`). A NaviMus update means re-checking it.
- **"Play X"** depends on R0b. If neither the URL scheme nor the intents can be driven, rebuilt pages can still open NaviMus's own page for playback until a path is found. That is said in the PR, not hidden.
