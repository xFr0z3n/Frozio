# LICENSES

Frozio is licensed under **GPL-3.0** (`LICENSE`), as decided in Phase 0 (the user approved GPL so GPL code can be reused).

## Code reuse policy

| Source | Licence | May Frozio copy code? |
|---|---|---|
| taurus (`github.com/xFr0z3n/taurus`) | GPL-3.0 (taurus/README.md: "no code under PolyForm Strict License 1.0.0 is distributed") | **Yes**, with attribution |
| spoti.pw **≤ v0.21.1** | GPL-3.0 (spoti.pw/README.md:119-121) | **Yes**, with attribution, taken from those tagged releases |
| spoti.pw **after v0.21.1** (current `main`, v0.50+) | PolyForm Strict 1.0.0 | **No.** Values and behaviour are recorded in `DESIGN_TOKENS.md` / `FEATURE_MATRIX.md`; no source is copied |
| amperfy | GPL-3.0 | **Yes**, with `// Adapted from amperfy/<path>:<lines> (GPL-3.0)` |
| FrozenMusic | GPL-3.0 | Structure and CI shape only |
| Kawarp (`github.com/better-lyrics/kawarp`, the fluid background chroma.pw credits) | MIT, Copyright (c) 2026 Better Lyrics | **Yes**, with the copyright and permission notice (below) |
| chroma.pw's dylibs (`SpotifyGlass*.dylib`, `work/dumps/`) | PolyForm Strict 1.0.0 | **No.** Values, names and behaviour only; their shaders and code are not copied |
| `pngs/patch-ipa-icon.py` (xFr0z3n) | the user's own | Adapted into `scripts/patch_icons.py` |

Every borrowed file or block carries a header comment `// Adapted from <repo>/<path>:<lines> (<licence>)`, and gets a row below.

## Borrowed code

| Frozio file | Origin | Licence |
|---|---|---|
| `scripts/patch_icons.py` | `pngs/patch-ipa-icon.py` | user-owned |
| `Source/Settings/Kit/FZPageStyle.h` | `taurus/tweak/Sources/Settings/SGPageStyle.h` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZPageStyle.m` | `taurus/tweak/Sources/Settings/SGPageStyle.m` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZPage.h` | `taurus/tweak/Sources/Settings/SGPage.h` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZPage.m` | `taurus/tweak/Sources/Settings/SGPage.m` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZModPage.h` | `taurus/tweak/Sources/Settings/SGModPage.h` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZModPage.m` | `taurus/tweak/Sources/Settings/SGModPage.m` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZGlowSwitch.h` | `taurus/tweak/Sources/Settings/SGGlowSwitch.h` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZGlowSwitch.m` | `taurus/tweak/Sources/Settings/SGGlowSwitch.m` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZViewTree.h` | `taurus/tweak/Sources/Core/SGViewTree.h` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/Kit/FZViewTree.m` | `taurus/tweak/Sources/Core/SGViewTree.m` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Lyrics/Taurus/BiniLyrics.m` | `taurus/tweak/Sources/Shared/LyricsSources/BiniLyrics.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/Musixmatch.m` | `taurus/tweak/Sources/Shared/LyricsSources/Musixmatch.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/Unison.m` | `taurus/tweak/Sources/Shared/LyricsSources/Unison.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/NetEase.m` | `taurus/tweak/Sources/Shared/LyricsSources/NetEase.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/LrcLib.m` | `taurus/tweak/Sources/Shared/LyricsSources/LrcLib.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/QQMusic.m` | `taurus/tweak/Sources/Shared/LyricsSources/QQMusic.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/KuGou.m` | `taurus/tweak/Sources/Shared/LyricsSources/KuGou.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/SGTTML.m` | `taurus/tweak/Sources/Shared/LyricsSources/SGTTML.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/LyricsSources.h` | `taurus/tweak/Sources/Shared/LyricsSources/LyricsSources.h` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/LyricsCommon.m` | `taurus/tweak/Sources/Shared/LyricsSources/LyricsSources.m (requests and shared parts)` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/Lyrics.h` | `taurus/tweak/Sources/Shared/Lyrics/Lyrics.h` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Lyrics/Taurus/KaraokeTiming.m` | `taurus/tweak/Sources/Shared/Lyrics/KaraokeTiming.m` @ fe3211c (imports changed, Spotify-only parts left out) | GPL-3.0 |
| `Source/Redesign/Kit/FZGlass.h` | `taurus/tweak/Sources/Core/SGGlass.h` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZGlass.m` | `taurus/tweak/Sources/Core/SGGlass.m` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRTokens.h` | `taurus/tweak/Sources/Redesigned/Kit/SGRTokens.h` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRTokens.m` | `taurus/tweak/Sources/Redesigned/Kit/SGRTokens.m` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRPalette.h` | `taurus/tweak/Sources/Redesigned/Kit/SGRPalette.h` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRPalette.m` | `taurus/tweak/Sources/Redesigned/Kit/SGRPalette.m` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRGlass.h` | `taurus/tweak/Sources/Redesigned/Kit/SGRGlass.h` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRGlass.m` | `taurus/tweak/Sources/Redesigned/Kit/SGRGlass.m` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Settings/FZAboutPage.h` | `taurus/tweak/Sources/App/About/About.h` @ fe3211c (renamed SG→FZ, Spotify-only parts removed) | GPL-3.0 |
| `Source/Settings/FZAboutPage.m` | `taurus/tweak/Sources/App/About/AboutSettings.m`, `Backup.m`, `Licenses.m` @ fe3211c (renamed SG→FZ, Spotify-only parts removed, Frozio settings suite) | GPL-3.0 |
| `Source/Lyrics/FZLockScreenLyrics.m` | `taurus/tweak/Sources/Shared/LockScreenLyrics/LockScreenLyrics.x` @ fe3211c (renamed SG→FZ, Logos → FZHook, Spotify karaoke state → NaviMus's saved lyrics) | GPL-3.0 |
| `Source/ArtistBlock/FZArtistSkip.m` | `taurus/tweak/Sources/Shared/ArtistBlock/ArtistSkip.x`, `ArtistBlock.m` @ fe3211c (renamed SG→FZ, Logos → FZHook, Spotify player → NaviMus's Now Playing info and next-track handler) | GPL-3.0 |
| `Source/ArtistBlock/FZArtistBlockPage.m` | `taurus/tweak/Sources/Shared/ArtistBlock/ArtistBlockSettings.m` @ fe3211c (renamed SG→FZ, names instead of URIs, Block by name added) | GPL-3.0 |
| `Source/Redesign/Album/FZRAlbumPage.m` | `taurus/tweak/Sources/Redesigned/Album/AlbumHeader.x`, `AlbumField.x`, `AlbumRows.x`, `Kit/SGRHeaderInfo.m`, `Kit/SGRActionRow.m` @ fe3211c (layout values and structure; rebuilt as a standalone page for NaviMus) | GPL-3.0 |
| `Source/Redesign/Kit/FZRField.h` | `taurus/tweak/Sources/Redesigned/Kit/SGRField.h` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRField.m` | `taurus/tweak/Sources/Redesigned/Kit/SGRField.m` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRFlow.h` | `taurus/tweak/Sources/Redesigned/Kit/SGRFlow.h` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRFlow.m` | `taurus/tweak/Sources/Redesigned/Kit/SGRFlow.m` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRFluid.h` | `taurus/tweak/Sources/Redesigned/Kit/SGRFluid.h` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRFluid.m` | `taurus/tweak/Sources/Redesigned/Kit/SGRFluid.m` @ fe3211c (renamed SG→FZ) | GPL-3.0 |
| `Source/Redesign/Kit/FZRAccent.m` | storage and picker from `taurus/tweak/Sources/Redesigned/Kit/SGRAccent.x` @ fe3211c (colour-swap hooks not ported) | GPL-3.0 |
| `Source/Redesign/Kit/FZRRoundButton.h`, `.m` | `taurus/tweak/Sources/Redesigned/Kit/SGRActionRow.m`, `Kit/SGRGlass.m` @ fe3211c (moved out of the album page) | GPL-3.0 |
| `Source/Redesign/Player/FZRMiniPlayer.m` | `taurus/tweak/Sources/Redesigned/NowPlayingBar/NowPlayingBar.x` @ fe3211c (card radius, glass, progress line values; rebuilt as Frozio's own bar) | GPL-3.0 |
| `Source/Redesign/Player/FZRPlayer.m` | `taurus/tweak/Sources/Redesigned/Player/PlayerHeader.x`, `PlayerArtwork.x`, `PlayerControls.x`, `PlayerFooter.x`, `PlayerField.x`, `PlayerLyrics.x`, `Lyrics/SGRKaraokeView.m`, `Lyrics/LyricsLook.m` @ fe3211c (layout and lyrics values and structure; rebuilt as a standalone player for NaviMus) | GPL-3.0 |
| `Source/Redesign/FZRBarButtons.m` | `taurus/tweak/Sources/Redesigned/Player/PlayerHeader.x`, `Kit/SGRGlass.m` @ fe3211c (the 44 pt round glass behind top bar buttons) | GPL-3.0 |
| `Source/Redesign/Kit/FZRKawarp.m` | `better-lyrics/kawarp@f4a4b29`, `packages/core/src/index.ts`, `defaults.ts` (shaders rewritten in Metal, same constants and passes) | MIT |

## Build-time tools (not shipped)

| Tool | Pin | Licence |
|---|---|---|
| Theos | `theos/theos@344ee59` | GPL-3.0 |
| insert_dylib | `Tyilo/insert_dylib@eb72781` | MIT |

## Kawarp's notice

MIT License

Copyright (c) 2026 Better Lyrics

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
