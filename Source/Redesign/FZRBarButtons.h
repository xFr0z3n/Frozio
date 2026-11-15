// The redesign's bar buttons on NaviMus's own screens (REDESIGN_PLAN.md R1, chroma.pw's look): back as a bare
// chevron, every bar button (back, ⋯, NaviMus's sort and filter buttons) white on a 44 pt glass circle. Each part
// can be turned off (Frozio settings → Appearance → Redesigned pages → Bars).
#pragma once
#import <UIKit/UIKit.h>

extern NSString *const FZRKeyBarCircles;    // "fz.redesign.bar.circles": glass circles behind bar buttons (on)
extern NSString *const FZRKeyBarWhite;      // "fz.redesign.bar.white": white bar buttons (on)
extern NSString *const FZRKeyBarBareBack;   // "fz.redesign.bar.bareBack": back without the previous page's title (on)

/// Styles `bar`'s buttons; called on every layout of NaviMus's navigation bars while the redesign is on.
void FZRStyleBarButtons(UINavigationBar *bar);
