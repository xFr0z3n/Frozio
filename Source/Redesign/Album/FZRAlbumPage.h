// The redesign's album page (docs/REDESIGN_PLAN.md, R4), laid over NaviMus's own album page, 1:1 with
// chroma.pw's. Adapted from taurus/tweak/Sources/Redesigned/Album/AlbumHeader.x, AlbumField.x, AlbumRows.x and
// Kit/SGRHeaderInfo.m, SGRActionRow.m @ fe3211c (GPL-3.0):
// - the page's field (FZRArtworkField: the cover's field colour fading to black), 600 pt bleed;
// - the hero: the cover filling the top of the page down to 56 pt below the title's top (SGRHeaderInfoTitleRise),
//   dissolving into the field over its bottom 46 %, a 140 pt top scrim at 28 % black;
// - the info (SGRHeaderInfo): title Title 2 bold primary (2 lines), artist Body secondary, "genre · type · year"
//   Footnote tertiary, 20 pt sides, gaps 2 / 4, 16 pt above the 48 pt row, 14 pt under it;
// - the row: shuffle (accent while NaviMus shuffles), the 148 pt white Play capsule whose glyph and word take
//   the field's colour and read Pause while this album plays, download (the user's choice over chroma.pw's +);
// - ⋯ pinned in a 44 pt glass circle 16 pt from the top right; back a bare chevron (both configurable);
// - rows: title Body primary, explicit badge plus artists Subheadline secondary, ⋯; the playing row in the
//   accent with moving bars.
//
// Data: getAlbum from the user's server through NaviMus's login (FZServer). Actions: NaviMus's own intents
// (FZNaviMus), its own controls on the page underneath through accessibility, its own command handlers (FZRemote).
#pragma once
#import <UIKit/UIKit.h>

extern NSString *const FZRKeyCircleBack;      // "fz.redesign.circle.back": a glass circle behind back, everywhere (on)
extern NSString *const FZRKeyCircleMore;      // "fz.redesign.circle.more": behind ⋯, everywhere (on)
extern NSString *const FZRKeyCircleActions;   // "fz.redesign.circle.actions": behind shuffle and download (on)
extern NSString *const FZRKeyAlbumShuffle;    // "fz.redesign.album.shuffle": the shuffle button (on)
extern NSString *const FZRKeyAlbumDownload;   // "fz.redesign.album.download": the download button (on)
extern NSString *const FZRKeyAlbumMeta;       // "fz.redesign.album.meta": the genre · type · year line (on)

@interface FZRAlbumPage : UIViewController
- (instancetype)initWithAlbumID:(NSString *)albumID naviMusPage:(UIViewController *)naviMusPage;
@end

/// The redesigned pages' options page (Frozio settings → Appearance → Redesigned pages).
UIViewController *FZRRedesignOptionsPage(void);
