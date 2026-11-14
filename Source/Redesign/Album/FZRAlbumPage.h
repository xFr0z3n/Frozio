// The redesign's album page (docs/REDESIGN_PLAN.md, R4), laid over NaviMus's own album page.
//
// Layout and values adapted from taurus/tweak/Sources/Redesigned/Album/AlbumHeader.x, AlbumRows.x and
// Kit/SGRHeaderInfo.m, SGRActionRow.m @ fe3211c (GPL-3.0): full-bleed artwork dissolving into the page's
// colour over its bottom 46 %, a 140 pt top scrim at 28 % black, the title (Title 2 bold), artist (Body)
// and "genre · type · year" (Footnote) centred 20 pt from the sides, then the 48 pt action row: shuffle,
// a 148 pt Play capsule, and download (the user's choice in place of chroma.pw's "+"). Glass back and ⋯
// circles (44 pt) are pinned 16 pt in from the top corners.
//
// Data: getAlbum from the user's server through NaviMus's login (FZServer). Actions: NaviMus's own
// PlayAlbumIntent / PlaySongIntent / OpenArtistIntent (FZNaviMus), and NaviMus's own download and ⋯
// controls on the page underneath, reached through accessibility.
#pragma once
#import <UIKit/UIKit.h>

@interface FZRAlbumPage : UIViewController
- (instancetype)initWithAlbumID:(NSString *)albumID naviMusPage:(UIViewController *)naviMusPage;
@end
