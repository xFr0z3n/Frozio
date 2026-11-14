# DESIGN_TOKENS — spoti.pw design language, as the Frozio target

Extracted from `spoti.pw/` (read-only). Evidence paths are relative to `spoti.pw/tweak/Sources/` unless a path says otherwise. spoti.pw keeps its tokens in one module, `Redesigned/Kit/SGRTokens.h/.m`; everything else either uses those tokens or hard-codes local constants, which are flagged below.

> **Licence note:** Frozio is GPL-3.0 (Phase 0 decision). Code may be reused from GPL-3.0 sources only: taurus, spoti.pw releases up to v0.21.1, and amperfy. Current spoti.pw (after v0.21.1) is PolyForm Strict 1.0.0 (`spoti.pw/README.md:117-122`), so its code is not copied. This file records values and behaviour.

## How these tokens map onto NaviMus

NaviMus is SwiftUI-dominant (see `docs/CLASSES.md`), while spoti.pw's tokens are UIKit/CoreAnimation values. Planned mapping:

| spoti.pw construct | NaviMus/Frozio equivalent |
|---|---|
| `UIColor` white with alpha | SwiftUI `Color.white.opacity(a)`, or the same `UIColor` in UIKit overlays and the representable tables |
| `UIBlurEffect SystemChromeMaterialDark` (pre-26) / `UIGlassEffect` (26) | SwiftUI `.background(.ultraThinMaterial)` / `.glassEffect()` (iOS 26), or the same UIKit effects in Frozio's UIKit views |
| `cornerCurve = .continuous` + radius | `RoundedRectangle(cornerRadius:, style: .continuous)` |
| spring (duration, damping) | `.spring(duration:bounce:)`, where bounce = 1 - damping (approx.) |
| text styles capped at max content size | `.font(.system(.body))` + `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` |
| `overrideUserInterfaceStyle = .dark` on glass | `.environment(\.colorScheme, .dark)` / `.preferredColorScheme(.dark)` on Frozio surfaces |

NaviMus's own minimum is iOS 17, so every iOS 26 token (glass, `UICornerConfiguration`, scroll-edge effect) needs an `if #available(iOS 26, *)` path and a pre-26 fallback (the blur materials below). spoti.pw does the same.

---
---

## 1. Colors

### 1a. Core semantic palette (Redesigned/Kit/SGRTokens.m)

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `color.text.primary` | white `#FFFFFF` a=1 | All redesigned text/glyphs; header title, glyph buttons | Redesigned/Kit/SGRTokens.m:22-24; SGRGlyph.m:16; SGRHeaderInfo.m:44 (~20+ uses) |
| `color.text.secondary` | white a=0.65 (0.80 Increase Contrast) | creator line, about text, lyrics button off-state | SGRTokens.m:26-28; SGRHeaderInfo.m:47; PlayerFooter.x:92 |
| `color.text.tertiary` | white a=0.40 (0.60 IC) | header duration/length line, meaning-sheet count | SGRTokens.m:30-32; SGRHeaderInfo.m:49; Lyrics/MeaningSheet.m:93 |
| `color.accent` | user pick; default stored pick `#37F200` ("the redesign's own green"); fallback when user picks "Spotify's green" = `#1ED760` | tab bar tint, action row content, shuffle on-state, toggles | Kit/SGRAccent.x:19 (`kDefaultAccent = 0x37F200`); SGRTokens.m:35-37 (fallback 1ED760); Navbar/TabBar.x:357; Kit/SGRActionRow.m:114,283 |
| `color.brand.spotifyGreen` | `#1ED760` (also legacy `#1DB954`) | detected/replaced brand greens; settings green | Kit/SGRAccent.x:14; Native/Appearance/Accent.x:13; Settings/SGPageStyle.m:87 |
| `color.field.neutral` | `#121212` | page field before artwork color arrives (AMOLED -> black) | SGRTokens.m:39-41 |
| `color.glass.solidFallback` | white a=0.16 | glass shape under Reduce Transparency; pre-26 lyrics extras button bg | SGRTokens.m:43-45; Kit/SGRGlass.m:28; Lyrics/SGRKaraokeView.m:1416 |
| `color.glass.prominentFilm` | white a=0.14 film inside glass (solid mode: white16% * 0.26) | playlist Play capsule ("prominent") | Kit/SGRGlass.m:54; Kit/SGRGlass.m:43 |
| `color.hairline` | white a=0.12 (0.20 IC), 0.5pt | list row separators | SGRTokens.m:47-49; Playlist/PlaylistRows.x:29,46; Album/AlbumRows.x:22 |
| `color.surface.elevated` | field color lifted 12% toward white (fallback white a=0.08) | home tiles / cards on field | SGRTokens.m:51-57; Home/HomeTiles.m:33 |

### 1b. Derived (algorithmic) colors – Redesigned/Kit/SGRPalette.m

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `color.field.fromArtwork` | artwork bottom-edge average, saturation <= 0.55, rel. luminance <= 0.07 (0.04 IC) | page background on player/album/playlist/artist | SGRPalette.m:8-9, 76-97 |
| `color.tint.tile` | dominant artwork color at luminance 0.05, mixed 35% into surface; never darker than surface | home tiles tinted by cover | SGRPalette.m:15, 243-272 |
| `color.flow.*` (5 colors) | per-quadrant dominant colors, sat x1.25 (cap 0.9), luminance 0.03-0.13 | animated "flow" field (moving blurred discs) | SGRPalette.m:18-19, 211-241 |
| `color.search.cardFar` | category color brightness x0.55, diagonal gradient | search category card plate | Search/SearchCards.x:23, 94-98, 140 |

### 1c. Overlay / scrim alphas

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `overlay.scrim.headerTop` | black a=0.28 over 140pt, to clear | album/artist/playlist hero header | Album/AlbumHeader.x:33,143; Artist/ArtistHeader.x:35,114; Playlist/PlaylistHeader.x:38,134 (3x) |
| `overlay.dissolve.header` | field color a=0 -> 0.72 (album/artist); black 1,1,0.28,0 (playlist); dissolve start 0.46 | hero image dissolving into field | AlbumHeader.x:171-172; ArtistHeader.x:141-142; PlaylistHeader.x:138-139 |
| `overlay.backdrop.dim` | blurred artwork dimmed black 0.25 top -> 0.45 (0.55 AMOLED) at 55% height, transparent below | palette backdrop bitmap | Kit/SGRPalette.h:15-18 (SGRPalette.m:157, 293) |
| `overlay.field.toBlack` | field fades to black from 55% to 100% of window height | all redesigned fields (AMOLED) | Kit/SGRField.m:14, 61 |
| `overlay.flow.shade` | base 0.55, shade 0 -> 0.35 from 45% | flow field | Kit/SGRFlow.m:27-29, 84 |
| `overlay.native.backdrop` | black 0.40 -> 0.60 -> bottomAlpha, under UltraThin blur | native player / playlist backdrop | Core/SGBackdrop.m:48-53 |
| `overlay.modal.dim` | black 0.55 (donate), 0.85 (tour) | modal backdrops | App/Donate/Donate.m:333; App/Onboarding/Tour.m:201 |
| `overlay.pressRow` | white a=0.10 (menu row highlight), 0.08 (speed menu) | playlist sort menu, speed/pitch menu | Playlist/PlaylistMenu.x:205; Shared/Player/SpeedPitchMenu.x:311 |
| `overlay.track.inactive` | white a=0.16 (sliders), 0.20 (speed track), 0.25 (download ring) | sliders / progress rings | Settings/SGModPage.m:345; SpeedPitchMenu.x:149; Kit/SGRDownload.m:187 |
| `overlay.lyrics.dim` | white a=0.30 unsung, translation lit 0.6, credit 0.4, underline 0.35, bubble 0.75 | karaoke lyrics | Lyrics/SGRKaraokeView.m:20,29,28,31,628 |
| `color.badge.accentTint` | accent a=0.2 | meaning sheet badge | Lyrics/MeaningSheet.m:87 |

### 1d. Mod-chrome / non-redesign colors

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `color.settings.pageBg` | `#121212` (black with AMOLED) | mod settings pages | Settings/SGPageStyle.m:90 |
| `color.settings.cardBg` | `#2A2A2A` (`#1C1C1C` AMOLED) | settings cards | Settings/SGPageStyle.m:92 |
| `color.settings.grey` / `color.navbar.item` | `#B3B3B3` | settings subtitles; tab item color | Settings/SGPageStyle.m:6; Redesigned/Navbar/Navbar.x:42; Native/Navbar/Navbar.x:41 |
| `color.destructive` | `#F15E6B` | settings red | Settings/SGPageStyle.m:88 |
| `color.discord` | `#5865F2` | settings link | Settings/SGPageStyle.m:89 |
| `color.kofi` | `#FF5E5B` (+ `#FFB4A2`, `#FF7A73`, `#FF8A7A`, `#E8434B` gradients) | donate sheet, tinted glass a=0.85 | App/Donate/Donate.m:21,38-40,89,97,293 |
| `color.glowSwitch.rainbow` | `#FF375F #FF9F0A #FFD60A #30D158 #64D2FF #0A84FF #BF5AF2` (iOS system colors, dark) | settings glow switch rim | Settings/SGGlowSwitch.m:19 |
| `color.native.homeTints` | `#0B4110 #0B4138 #0B2B41 #160B41 #330B41 #410B2E #410B10 #412A0B` | native home gradient choices | Native/Home/HomeGradient.x:31 |
| `color.liveActivity.green` | SwiftUI `Color(0.12,0.84,0.38)` (~#1FD661); idle white 0.08; bg black 0.75; on-state green 0.22 | Live Activity / Dynamic Island | extension/LiveActivity/LiveActivityWidget.swift:12-13,51,251,285 |

**Inconsistencies (color)**
- Accent default: SGRTokens.m:36 comments/falls back to Spotify `#1ED760`, but SGRAccent.x:19 stores `#37F200` as default pick, so the effective default is `#37F200`; Settings (SGPageStyle.m:87) and Live Activity (LiveActivityWidget.swift:12) hard-code `#1ED760`-ish green independent of the accent.
- Secondary text: SpeedPitchMenu.x:40-45 re-implements primary/secondary (same 0.65/0.80) instead of calling SGRSecondary (duplicate, consistent value).
- Press highlight fill: 0.10 (PlaylistMenu.x:205) vs 0.08 (SpeedPitchMenu.x:311).
- Inactive track: 0.16 / 0.20 / 0.25 in three controls.
- Hairline: token SGRHairline() exists but PlaylistRows.x:46 hard-codes white 0.12 (ignores IC 0.20); SGPage.m:22 uses 0.10.
- Modal dim 0.55 vs 0.85.
- No dynamic light/dark `UIColor colorWithDynamicProvider` anywhere: everything is forced dark via `overrideUserInterfaceStyle = Dark` (SGRGlass.m:31; TabBar.x:345; NowPlayingBar.x:119; SearchCards.x:126; SGRKaraokeView.m:1421). Only `UIColor.systemBackgroundColor` at MeaningSheet.m:75.

---

## 2. Corner radii

All rounded views set `cornerCurve = kCACornerCurveContinuous` (squircle) – ~25 sites; glass on iOS 26 uses `UICornerConfiguration` (capsule or `fixedRadius`) instead of layer radius (Core/SGGlass.m:52-71).

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `radius.thumb` | 6 | row thumbnails <= 64pt (playlist, library, search) | SGRTokens.m:11; Playlist/PlaylistRows.x:70-72; Library/LibraryRows.x:68; Search/SearchCards.x:166 |
| `radius.cover` | 8 | release covers in lists/carousels, lyrics thumbnail target | SGRTokens.m:10; Home/HomeCards.x:31,53; Library/LibraryRows.x:69; Player/PlayerLyrics.x:281 |
| `radius.artwork` | 12 | player cover + its shadow plate; morph target | SGRTokens.m:8; Player/PlayerArtwork.x:148; Kit/SGRRestyle.m:291; Player/PlayerMorph.x:194; Native/Player/Player.x:29 |
| `radius.card` | 16 | content cards, search category cards (+ glass) | SGRTokens.m:9; Home/HomeCards.x:65; Search/SearchCards.x:194-201; Native/Player/LyricsCard.x:11 |
| `radius.nowPlayingCard` | min(24, h/2) | floating now-playing bar glass card | NowPlayingBar/NowPlayingBar.x:18,110,122 |
| `radius.capsule` | h/2 (UICornerConfiguration.capsule on 26) | glass circles (44), Play capsule, search field, library search, karaoke bubble, NPB artwork (circle) | Kit/SGRGlass.m:99; Kit/SGRActionRow.m:83; Navbar/SearchField.x:105,113; Library/LibrarySearch.x:31; NowPlayingBar.x:71-77 |
| `radius.screen` | device `_displayCornerRadius`, fallback 55 | player morph sheet end state | Player/PlayerMorph.x:37, 53-60, 160-164 |
| `radius.homeTileCover` | 4 | home shortcut tile cover inset 5 | Home/HomeTiles.m:20 |
| `radius.settings.tile` | 7 (28x28 icon tile), 10 (tour icon), 18 (gesture preview), 22 (tour card) | mod settings/onboarding | Settings/SGPageStyle.m:100; App/Onboarding/Tour.m:9,64; Shared/Gestures/GesturesSettings.m:36 |
| `radius.donateCard` | 44 on iOS 26, 28 before | donate sheet glass card | App/Donate/Donate.m:271-274 |
| `radius.liveActivity` | 12 / 10 continuous | LA buttons, chips | LiveActivityWidget.swift:285,299,363 |

**Inconsistencies (radius)**: NPB card 24 is outside the token set; Home tile cover 4 vs `radius.thumb` 6; settings uses 7/10/18/22 ad hoc; Donate card radius switches 44/28 by OS.

---

## 3. Typography

All system font (SF Pro); no `UIFontDesignRounded` anywhere. `SGRFont(style, weight, maxCategory)` = text-style size capped at a content size category, then `systemFontOfSize:weight:` (SGRTokens.m:59-65).

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `font.pageTitle` | LargeTitle, Bold, cap Large (34pt) | Home, Library, Search page titles | Home/HomeHeader.x:127; Library/LibraryHeader.x:164; Search/SearchPage.x:126 |
| `font.sectionHeading` | Title2, Bold, cap Large | home section headings | Home/HomeHeadings.x:93 |
| `font.hero.title` | Title2, Bold, cap XL | album/playlist/artist hero title (center, 2 lines) | Kit/SGRHeaderInfo.m:43 |
| `font.hero.creator` | Body, Regular, cap XL | hero creator line (secondary color) | SGRHeaderInfo.m:46 |
| `font.hero.meta` | Footnote, Regular, cap XL | duration (tertiary), about (secondary) | SGRHeaderInfo.m:48,50 |
| `font.action` | Subheadline, Semibold, cap Large | action-row capsule label (Play) | Kit/SGRActionRow.m:112 |
| `font.menuRow` | Body size, Regular | playlist sort/filter menu rows | Playlist/PlaylistMenu.x:173 |
| `font.lyrics` | 30pt Bold (translation Semibold), backing vocals x0.62 | karaoke lyrics | Lyrics/SGRKaraokeView.m:19,224,231,240 |
| `font.lyrics.credit` | 12pt Semibold | lyrics credit | SGRKaraokeView.m:31,1108 |
| `font.meaning.quote` | 20 Bold; body = preferred Body; count 13 Regular; badge 15 Semibold | meaning sheet | Lyrics/MeaningSheet.m:64,81,92,93 |
| `font.digits.monospaced` | font + `kMonospacedNumbersSelector` feature | player elapsed/remaining labels, speed menu values | SGRTokens.m:67-72; Kit/SGRRestyle.m:150,158; Player/PlayerControls.x:214; SpeedPitchMenu.x:58-62 |
| `font.speedMenu` | Body Regular / Subheadline Regular+Semibold, cap XL | speed & pitch menu | Shared/Player/SpeedPitchMenu.x:123,196,198,209 |
| `font.tabLabel` | 10pt (or Spotify's tab font) | tab bar labels | Redesigned/Navbar/Navbar.x:112 |
| `font.settings.title` / `.subtitle` | 13 Bold / 11 Regular (Spotify fonts if found) | mod settings | Settings/SGPageStyle.m:7-8 |
| `font.onboarding` | 30 Bold heading; 17 Semibold buttons/names; 13 body | tour | App/Onboarding/Tour.m:216,37,69,73 |
| `font.donate` | 26 Bold title; 12 Bold eyebrow; 15 body; 17 Semibold button | donate | App/Donate/Donate.m:354-365,114 |
| `font.liveActivity` | .title3 bold, .subheadline semibold, .caption semibold, 34 bold monospacedDigit (timer) | Live Activity | LiveActivityWidget.swift:110,116,162,385 |

**Inconsistencies**: max-size caps differ (Large for page titles/action, ExtraLarge for hero info/speed menu); App/Settings screens use fixed point sizes (no Dynamic Type) while Redesigned uses text styles; karaoke lyrics fixed 30pt.

---

## 4. Materials / blur / glass

| Token | Value / API | Min iOS | Where used | Evidence |
|---|---|---|---|---|
| `material.glass` | `UIGlassEffect effectWithStyle:0` (Regular) via NSClassFromString | 26.0 | every SGGlass pane: NPB card, lyrics page, search-field button, tour/donate cards, native player circles | Core/SGGlass.m:7-12; NowPlayingBar.x:116; Navbar/SearchField.x:108; Lyrics/LyricsPage.x:47 |
| `material.glass.fallback` (Core) | `UIBlurEffectStyleSystemChromeMaterialDark` | 13 | SGGlassEffect pre-26 | Core/SGGlass.m:11 |
| `material.glass.fallback` (Redesign controls) | `UIBlurEffectStyleSystemThinMaterialDark` | 13 | SGRGlassInside pre-26 | Kit/SGRGlass.m:24 |
| `material.glass.solid` | white 0.16 fill (Reduce Transparency) | any | control glass | Kit/SGRGlass.m:12,26-28 |
| `material.glass.clearTinted` | `UIGlassEffect effectWithStyle:UIGlassEffectStyleClear`, `tintColor` = category color a=0.35 | 26.0 | search category cards | Search/SearchCards.x:22,142-146 |
| `material.glass.tinted` | UIGlassEffect + `setTintColor:` Ko-fi a=0.85 | 26.0 | donate button | App/Donate/Donate.m:85-89 |
| `shape.glass` | `UICornerConfiguration capsuleConfiguration` / `configurationWithUniformRadius:[UICornerRadius fixedRadius:]` | 26.0 | all glass shapes | Core/SGGlass.m:52-71 |
| `button.glass` | `UIButtonConfiguration glassButtonConfiguration` (capsule) / `prominentGlassButtonConfiguration` | 26.0 | lyrics translate extras button; tour primary button | Lyrics/SGRKaraokeView.m:1412-1418; App/Onboarding/Tour.m:31 |
| `scrollEdge.soft` | `UIScrollEdgeEffectStyle.softStyle` on top edge | 26.0 | redesigned + native scroll views | Kit/SGREdgeEffect.x:10-15; Native/Appearance/EdgeEffect.x:9-14 |
| `navbar.liquidGlass` | `prefersLiquidGlassNavigationBar -> YES` + Spotify flags (`ios-reprise-liquid-glass-properties…`, sheet-style NPV, bottom-sheet queue/Connect) | 26 (Spotify) | hub pages, player | Kit/SGRGlassDesign.x:8-24 |
| `tabbar.system` | real `UITabBar` subclass (system glass tab bar), forced dark, tint accent | 26 | tab bar | Navbar/TabBar.x:340-357 |
| `material.backdrop.native` | `UIBlurEffectStyleSystemUltraThinMaterialDark` over 48px cover | 13 | native player/playlist backdrop | Core/SGBackdrop.m:5,40 |
| `blur.precomputed` | CoreImage Gaussian σ=12 (backdrop, 160px wide) / σ=5 (dissolve, 96px) | – | field backdrop instead of live blur | Kit/SGRPalette.m:10-11,124-135 |
| `blur.lyrics.depth` | private `CAFilter gaussianBlur`, 1.4/line, max 6, animated 0.6s | – | karaoke out-of-focus lines | Lyrics/SGRKaraokeView.m:23,48,708,724-728 |
| `blur.glow` | private CAFilter gaussianBlur glow | – | glow switch, donate rim | Settings/SGGlowSwitch.m:82; App/Donate/Donate.m:78 |

No `UIVibrancyEffect`, no `UIGlassContainerEffect`. `SGRGlassSpacing = 16` ("how near two glass shapes merge in one container", SGRTokens.m:15) is declared but never used.

---

## 5. Spacing / sizes

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `space.sideMargin` | 16 | page side margin (headers, hairlines, rows) | SGRTokens.m:6; Album/AlbumRows.x:41; Library/LibraryHeader.x:198; PlaylistRows.x:53 (~8 uses) |
| `space.grid` | 8 (all gaps multiples) | title/trailing gaps | SGRTokens.m:7; Home/HomeHeader.x:130; LibraryHeader.x:168,219; PlayerLyrics.x:166 |
| `size.glassCircle` | 44 | glass circle behind top-bar buttons (player minimize/context menu), mirror button | SGRTokens.m:12; Player/PlayerHeader.x:41; Kit/SGRActionRow.m:214,469 |
| `size.minTouch` | 44 | glyph button hit area | Kit/SGRGlyph.m:5; PlayerFooter.x:207 |
| `size.actionHeight` | 48 | action-row buttons under hero | SGRTokens.m:13; SGRHeaderInfo.m:158,181 |
| `size.playCapsule` | width 148 | hero Play capsule | SGRHeaderInfo.m:13 |
| `space.heroInfo` | side 20, row spacing 16, row above 16, about above 14, bottom 14, title rise 56 | hero info block | SGRHeaderInfo.m:9-13 |
| `size.actionGlyph` | glyph box 44, capsule lead 4 / trail 20, mirror glyph 24, corner 16 | action row | Kit/SGRActionRow.m:17,19,417 |
| `size.player.glyph` | skip 32pt, play 44pt, lyrics 20pt (max width 30) | player transport/footer | Player/PlayerControls.x:23; PlayerFooter.x:26,31 |
| `space.player.footer` | 20 above safe area, min bottom 34 | player bottom row | PlayerFooter.x:37 |
| `size.player.coverMin` | 200 | player cover min width | PlayerArtwork.x:19; PlayerField.x:30 |
| `size.lyrics.thumb` | 72 thumb, gaps 16/12, top 8, lyrics top 20, bottom 8, title fade 20 | lyrics-open player layout | Player/PlayerLyrics.x:33-39 |
| `size.hero.min` | min hero 120, min cover 80 | album/playlist/artist header | AlbumHeader.x:36; PlaylistHeader.x:41; ArtistHeader.x:37 |
| `size.nowPlayingBar` | card <= 80 high; progress line 226x2 at x52, 6 from bottom; artwork circle 36-48 | floating bar | NowPlayingBar.x:85-86,107,69 |
| `size.menuRow` | 56 row, margin 16, glyph 24, glyph gap 16 | playlist menu; speed menu rows (56, slider 72) | Playlist/PlaylistMenu.x:44; SpeedPitchMenu.x:32,36 |
| `space.row` | hairline gap 12 after 48pt thumb; library text gap 12; row inset 8 | list rows | PlaylistRows.x:29,67; Library/LibraryRows.x:21; LibraryHeader.x:54 |
| `space.lyrics` | margin 24, line gap 24, anchor 28% height, edge fade 10% | karaoke | SGRKaraokeView.m:19,21,22 |
| `size.lyrics.extras` | 44 button, glyph 17, bottom 12 | lyrics translate button | SGRKaraokeView.m:34 |
| `space.search.cardTitle` | 12 | search category title inset | Search/SearchCards.x:25 |
| `space.homeTile` | cover inset 5 | home tiles | Home/HomeTiles.m:20 |
| `space.sheet` | side 24, top 28, gap 12 | meaning sheet | Lyrics/MeaningSheet.m:6 |
| `size.tabbar.stockRow` | 49 | tab bar height math | Navbar/TabBar.x:300 |

Dead tokens: `SGRActionSpacing = 12` and `SGRGlassSpacing = 16` (SGRTokens.m:14-15) have no references.
Inconsistency: hero side inset 20 (SGRHeaderInfo.m:13) vs `space.sideMargin` 16.

---

## 6. Shadows

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `shadow.artwork` | black, opacity 0.45, radius 32, offset (0,12), path = rounded rect r12 | player cover "shadow plate" (redesign) and native player cover | Kit/SGRRestyle.m:294-297,314; Native/Player/Player.x:159-163 (2x identical) |
| `shadow.knob` | black 0.3, r3, (0,1) | settings glow switch knob | Settings/SGGlowSwitch.m:99-102 |
| `shadow.handle` | black 0.35, r2, (0,1) | EQ curve handles | Shared/AudioEffects/SGDSPCurveView.m:137-140 |
| `shadow.glow.kofi` | Ko-fi color 0.75, r24, offset 0 (0 under Reduce Transparency) | donate disc | App/Donate/Donate.m:297-301 |

Note: the redesign deliberately avoids borders ("Never a border around anything", SGRTokens.h:36); only the artwork casts a shadow.

---

## 7. Motion

| Token | Value | Where used | Evidence |
|---|---|---|---|
| `motion.layout` | UIView spring duration 0.45, damping 1.0, velocity 0, AllowUserInteraction+BeginFromCurrentState | cover pause-shrink, lyrics layout move | SGRTokens.m:19, 96-97; Player/PlayerArtwork.x:130; PlayerLyrics.x:347 |
| `motion.press` | spring duration 0.32, damping 0.62 | press scale on glyph buttons, action row, search cards | SGRTokens.m:19-20, 99-100; Kit/SGRGlyph.m:107; SGRActionRow.m:144,387; Search/SearchCards.x:219 |
| `motion.fade` | 0.35 ease-in-out (`SGRCrossfade`), kept under Reduce Motion | image/field color crossfade, tile tint, download tint | SGRTokens.m:16, 102; Kit/SGRField.m:184-185,235; Home/HomeTiles.m:108 |
| `motion.press.scale` | glyph 0.9 + alpha 0.5; capsule 0.94; mirror 0.92; search card 0.96; donate 0.95; disabled alpha 0.35 | press feedback | SGRGlyph.m:5; SGRActionRow.m:144,387; SearchCards.x:26; Donate.m:178 |
| `motion.player.pausedScale` | cover scale 0.84 paused (0.92 Reduce Motion), via motion.layout | player cover | Player/PlayerArtwork.x:17 |
| `motion.player.morph` | driven by Spotify's own transition progress (its spring); sheet radius lerp card->screen; player alpha smoothstep 0.08-0.55; sheet alpha 0-0.15; bar alpha out by 0.25; cover flies circle->r12 | now-playing bar -> player | Player/PlayerMorph.x:1-22, 49-53, 159-194 |
| `motion.lyrics.enter` | lines fade in 0.30 after 0.12 delay, out 0.16, ease-in-out; enter scale 0.96 | player lyrics open/close | PlayerLyrics.x:42-43,349 |
| `motion.symbol.replace` | `NSSymbolReplaceContentTransition` (speed 2) / `replaceDownUpTransition` | glyph swaps (play/pause, lyrics, download, action row) | Kit/SGRGlyph.m:36; SGRActionRow.m:277; SGRDownload.m:287 |
| `motion.symbol.bounce` | `NSSymbolBounceEffect` | onboarding hero, donate cup/heart | App/Onboarding/Tour.m:293; Donate.m:426-429 |
| `motion.karaoke` | blur ease 0.6; line settle spring 0.9/d1.0; follow-song spring 0.7/d0.9; line move spring 0.7/d0.86 + stagger min(0.3, n*0.04); whole-line fade 0.35; translation 0.3/0.5; restyle 0.3; dim scale 0.97 lift 2.5 | karaoke lyrics | SGRKaraokeView.m:20,35,39,727,738,761,1210,1556-1557 |
| `motion.karaoke.breath` | instrumental-break dots: in 0.4, breathe 0.85-1.12 over 4s halves, swell 1.2, out 0.35 | lyrics break dots | SGRKaraokeView.m:62-63 |
| `motion.flow` | discs drift 29-53s loops, breathe 0.85-1.18 over 11-23s, recolor 1.2s ease-in-out | animated field | Kit/SGRFlow.m:16-25,154-213 |
| `motion.download` | ring progress ease 0.5; ring close 0.22 ease-out; spin 1s linear; symbol in spring 0.5 d0.58 delay 0.08; out 0.16 ease-in | download button | Kit/SGRDownload.m:129,131,237,320,333,355-359 |
| `motion.menu.open` | spring 0.45 d1.0 | speed/pitch menu | Shared/Player/SpeedPitchMenu.x:37,71 |
| `motion.crossDissolve` | 0.2-0.3 `TransitionCrossDissolve` | action-row glyph, meaning sheet, settings tables, native player | SGRActionRow.m:368; MeaningSheet.m:143; UpdatePage.m:232; Native/Player/Player.x:83 |
| `motion.app` | donate card spring 0.62 d0.8, dismiss 0.28 ease-in; glow switch spring 0.4 d0.72; rainbow turn 3.2-4s | mod chrome | Donate.m:419-437; SGGlowSwitch.m:5,223 |

**Haptics** (Shared/Haptics/SGFeedback.m:22-35, intensity via `impactOccurredWithIntensity:`)

| Token | Style, intensity | Used for | Evidence |
|---|---|---|---|
| `haptic.play` | Rigid 0.8 | play | SGFeedback.m:24; ControlHaptics.x:87 |
| `haptic.pause` | Soft 1.0 | pause | SGFeedback.m:25 |
| `haptic.skip` | Light 1.0 | next/prev, lyrics line tap/hold seek | SGFeedback.m:26; SGRKaraokeView.m:1145,1165 |
| `haptic.toggle` / `.detent` | Selection (detent via Rigid 0.5 tick when strength scaled) | shuffle/repeat, scrub detents, speed=1/pitch=0 | SGFeedback.m:27,30,41; SpeedPitchMenu.x:352,367 |
| `haptic.add` | Medium 0.8 | add to library | SGFeedback.m:28 |
| `haptic.grab` / `.release` / `.edge` | Light 0.7 / Soft 0.8 / Rigid 0.6 | scrubber grab, release, hitting ends | SGFeedback.m:29,31-32; ControlHaptics.x:143-181 |
| `haptic.music` | CoreHaptics transient + continuous rumble synced to audio | "music haptics" | Shared/Haptics/MusicHaptics.x:331-405 |
| `haptic.settings` | Light impact (switch), Medium (donate), Selection (EQ detents) | mod chrome | SGGlowSwitch.m:105; Donate.m:135; SGDSPCurveView.m:104 |

**Inconsistencies (motion)**: several hand-rolled springs bypass SGRAnimate (karaoke 0.7/0.86, 0.7/0.9, 0.9/1.0; download 0.5/0.58; speed menu reimplements motion.layout as 0.45/d1 independently); press scale varies 0.90-0.96; lyrics in/out timings (0.30/0.16) differ from `SGRCrossfade` 0.35.

---

## 8. Iconography (SF Symbols)

Default glyph weight in redesign: `UIImageSymbolWeightRegular` at explicit point size (Kit/SGRGlyph.m:14,51; PlayerControls.x:57). No `UIImageSymbolScale` used; sizes are always `configurationWithPointSize:weight:`.

| Token | Symbol(s) | Size / weight | Where | Evidence |
|---|---|---|---|---|
| `icon.transport.play` | `play.fill` / `pause.fill` | 44 Regular | player play button | Player/PlayerControls.x:23,105,164 |
| `icon.transport.skip` | `backward.fill` / `forward.fill` | 32 Regular | player skip | PlayerControls.x:23,183-184 |
| `icon.lyrics` | `quote.bubble` / `quote.bubble.fill` (open) | 20 Regular | player footer lyrics toggle | PlayerFooter.x:26-28 |
| `icon.shuffle` | `shuffle` | mirror glyph 24 | hero action row | SGRHeaderInfo.m:54; SGRActionRow.m:19 |
| `icon.more` | `ellipsis` | – | action row corner button | SGRActionRow.m:449 |
| `icon.download` | `arrow.down`, `arrow.down.circle.fill`, `exclamationmark.circle` (+ custom ring/stop shapes 24 canvas, ring r9.75 w2, stop 7 r1.5) | 17 Semibold | album/playlist download | Kit/SGRDownload.m:127,138-141,210 |
| `icon.follow` | `person.badge.plus` / `person.fill.checkmark` | – | artist follow | Artist/ArtistHeader.x:266-267 |
| `icon.sortFilter` | `arrow.up.arrow.down`, `slider.horizontal.3` | 24 box | playlist menu | Playlist/PlaylistMenu.x:242-243 |
| `icon.lyrics.extras` | `translate`, `character.phonetic`, `character.bubble` | 17 Semibold | lyrics menu | SGRKaraokeView.m:1407-1438 |
| `icon.lyrics.bubble` | `quote.opening` | 11 Bold | meaning bubble | SGRKaraokeView.m:809-810 |
| `icon.speed` | `slider.horizontal.3`, `chevron.down`, `hare.fill`/`tortoise.fill`, `arrow.up`/`arrow.down` | 20 Regular, 13 Semibold, Medium | speed/pitch menu | SpeedPitchMenu.x:136,194,200,216-218 |
| `icon.tab.pinned` | `star.fill` | 19 Semibold | extra tab | Navbar/Navbar.x:62 |
| `icon.settings.*` | `chevron.right` 13 Semibold; `checkmark` 13 Semibold (16 box); tile glyph 14 Medium in 28pt r7 white-12% tile; plus ~40 settings symbols | settings | Settings/SGPageStyle.m:10-11,95-100; SGModPage.m:243 |
| `icon.liveActivity` | `music.note`, `pause.fill`, `waveform`, `play.fill` | SwiftUI | LiveActivityWidget.swift:68-81,350 |

Custom images: none from asset catalogs; custom drawing only (download ring/stop, settings tile backgrounds, glow rims).

---

## 9. Interaction patterns

| Pattern | Detail | Evidence |
|---|---|---|
| Bar -> player morph | Now-playing card grows into full-screen sheet (radius card->display corner), cover flies from bar artwork to player cover; rides Spotify's transition progress so taps/drags/cancels follow; off for iPad/Reduce Motion | Player/PlayerMorph.x:1-22 |
| Glass inside controls | glass circle/capsule inserted at subview index 0 of Spotify's own buttons, kept centered by autoresizing | Kit/SGRGlass.h:12-25; Kit/SGRGlass.m:70-105 |
| Press feedback | scale+alpha spring on highlight (motion.press) | SGRGlyph.m:104-111; SearchCards.x:213-221 |
| Context menus | `showsMenuAsPrimaryAction` UIMenu on lyrics extras (fixed order) and EQ presets; Spotify's context menu in nav bar forced via flag; player header "Context menu" button wrapped in glass | SGRKaraokeView.m:1423-1441; SGDSPCurveView.m:179,418; SGRGlassDesign.x:16; PlayerHeader.x:42 |
| Custom sort/filter menu | replaces Spotify's playlist sort sheet with 56pt glyph rows | Playlist/PlaylistMenu.x:44,250-281 |
| Sheets | Meaning sheet: medium + large detents, grabber visible; Spotify sheet-style player, bottom-sheet queue & Connect, sleep timer options sheet forced on | Lyrics/MeaningSheet.m:40-42; Kit/SGRGlassDesign.x:17-23 |
| Long press | tab bar long-press (home hold), karaoke line hold | Navbar/TabBar.x:228,348; SGRKaraokeView.m:1115,1151 |
| Tap to seek lyrics | tap a line seeks; browse-hold 3s before auto-follow resumes | SGRKaraokeView.m:36,1114,1132 |
| Double-tap zones | over player artwork: 2 cols / 3 cols / 3x3 grid, actions seek ±5/10/15/30s, play/pause, next/prev, shuffle, repeat (swipe = next track and vertical drag kept by Spotify) | Shared/Gestures/Gestures.h:1-20; GestureZones.m:6-15; Redesigned/Player/PlayerGestures.x |
| Lyrics in player | cover shrinks to 72pt thumbnail at top-left, title row moves beside it, lines fade in | Player/PlayerLyrics.x:33-47,340-351 |
| Paused cover | cover shrinks to 0.84 when paused | PlayerArtwork.x:17 |
| Page transitions | nav bar hidden at transition start (avoid 54pt jump under Liquid Glass) | Shared/Navigation/PageTransition.x:1-36 |
| Accessibility adaptation | Reduce Motion -> instant (fades kept, morph off); Reduce Transparency -> solid fills; Increase Contrast -> higher text/hairline alpha, darker field | SGRTokens.m:74-104; SGRGlass.m:11-15 |
