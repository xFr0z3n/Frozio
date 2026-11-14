// The redesign accent colour (spoti.pw: "Accent colour" of Appearance; default #37F200, the
// redesign's own green — docs/DESIGN_TOKENS.md color.accent). Stored as 0xRRGGBB under
// FZAccentKey ("fz.redesign.accent", Settings/Kit/FZPageStyle.h), shared with the settings pages.
// Unlike spoti.pw, Frozio does not swap colours at draw time (there is no Spotify green to swap);
// Frozio's own surfaces read FZRAccent() directly.
#pragma once
#import <UIKit/UIKit.h>

extern NSNotificationName const FZRAccentDidChangeNotification;

UIColor *FZRAccentColor(void);   // never nil
NSString *FZRAccentLabel(void);  // "#RRGGBB" (or "Redesign green" for the default)
void FZRPickAccent(void);        // the system colour picker over the top of the app, stored on the way out
void FZRResetAccent(void);       // back to #37F200
