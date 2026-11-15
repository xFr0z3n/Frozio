// The redesign's bar buttons on NaviMus's own screens (REDESIGN_PLAN.md R1, chroma.pw's look): back as a bare
// chevron, every bar button (back, ⋯, NaviMus's sort and filter buttons) white on a 44 pt glass circle. Each part
// can be turned off (Frozio settings → Appearance → Redesigned pages → Bars).
#pragma once
#import <UIKit/UIKit.h>

extern NSString *const FZRKeyCircleOthers;  // "fz.redesign.circle.others": circles behind bar buttons other than back and ⋯ (on)
// Back and ⋯ use FZRKeyCircleBack and FZRKeyCircleMore (FZRAlbumPage.h), here, on the album page and in the player.
extern NSString *const FZRKeyBarWhite;      // "fz.redesign.bar.white": white bar buttons (on)
extern NSString *const FZRKeyBarBareBack;   // "fz.redesign.bar.bareBack": back without the previous page's title (on)

/// Styles `bar`'s buttons; called on every layout of NaviMus's navigation bars while the redesign is on.
void FZRStyleBarButtons(UINavigationBar *bar);

/// NaviMus's library section chips in the same glass (FZRLibraryChips.m; FZRKeyCircleOthers turns them off too).
void FZRInstallLibraryChips(void);
