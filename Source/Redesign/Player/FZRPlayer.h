// The redesign's mini player (R2) and player (R3), docs/REDESIGN_PLAN.md, 1:1 with chroma.pw's, every button
// optional. Adapted from taurus/tweak/Sources/Redesigned/NowPlayingBar/ and Player/ @ fe3211c (GPL-3.0).
//
// NaviMus draws its mini player and player in one SwiftUI overlay of each tab (iOS 17: a `_UIInheritedView` band
// over the tab bar, device probe build 33). Frozio hides that band (an empty layer mask, no touches) and lays its
// own glass bar over the tab bar controller; the bar opens Frozio's player. Everything plays through NaviMus: its
// command handlers (FZRemote) and its Now Playing info. What Frozio can't rebuild yet (the queue, a song's
// download) goes through NaviMus's own player, opened out of sight or, from the ⋯ menu, shown as it is.
#pragma once
#import <UIKit/UIKit.h>

// Switches (FZEnabled: on until switched off; FZHidden: off until switched on).
extern NSString *const FZRKeyPlayerRebuilt;      // "fz.redesign.player": the rebuilt mini player and player (on)
extern NSString *const FZRKeyMiniPlayPause;      // mini player: play/pause (on)
extern NSString *const FZRKeyMiniPrevious;       // previous (off)
extern NSString *const FZRKeyMiniNext;           // next (on)
extern NSString *const FZRKeyMiniAirPlay;        // AirPlay (off)
extern NSString *const FZRKeyMiniDownload;       // download (on), in place of chroma.pw's +
extern NSString *const FZRKeyMiniProgress;       // the progress line (on)
extern NSString *const FZRKeyMiniRoundArtwork;   // a round cover (on, as chroma.pw's)
extern NSString *const FZRKeyMiniSwipe;          // swipe the bar to change song (on)
extern NSString *const FZRKeyPlayerContext;      // player: the album name at the top (on)
extern NSString *const FZRKeyPlayerBackground;   // 0 fluid artwork (chroma.pw's, Kawarp), 1 blurred cover, 2 colours, 3 the cover
extern NSString *const FZRKeyPlayerRightSlot;    // right of next: 0 sleep timer (chroma.pw), 1 repeat
extern NSString *const FZRKeyPlayerDownload;     // download beside the title (on)
extern NSString *const FZRKeyPlayerShuffle;      // shuffle (on)
extern NSString *const FZRKeyPlayerRepeat;       // repeat (on)
extern NSString *const FZRKeyPlayerAirPlay;      // AirPlay (on)
extern NSString *const FZRKeyPlayerSleep;        // sleep timer (on)
extern NSString *const FZRKeyPlayerLyrics;       // lyrics (on)
extern NSString *const FZRKeyPlayerQueue;        // queue (on)
extern NSString *const FZRKeyPlayerMore;         // ⋯ (on)
extern NSString *const FZRKeyPlayerShrink;       // the cover shrinks while paused (on)
extern NSString *const FZRKeyPlayerTimes;        // elapsed and remaining under the scrubber (on)

/// Installs the mini player when the redesign is on. Call before NaviMus's main().
void FZRInstallPlayer(void);

/// Whether the rebuilt player is in use now (the redesign on at launch and the switch on).
BOOL FZRPlayerActive(void);

/// The tab bar controller Frozio's mini player sits on, and that bar (nil before the first song).
UITabBarController *FZRPlayerTabs(void);
UIView *FZRPlayerMiniBar(void);
/// The player's open/close animation (FZRPlayerTransition.m).
id<UIViewControllerTransitioningDelegate> FZRPlayerTransitioning(void);

/// Opens Frozio's player over the app.
void FZRPresentPlayer(void);

/// Rows for the options page (Frozio settings → Appearance → Redesigned pages).
NSArray *FZRPlayerOptionSections(void);

#pragma mark - NaviMus's own player (FZRNaviMusPlayer.m)

/// NaviMus's mini player band in the tab bar controller's selected tab, nil when it has none.
UIView *FZRNaviMusMiniBand(UITabBarController *tabs);
/// Hides or shows NaviMus's band (and keeps it hidden through SwiftUI's updates while `hidden`).
void FZRSetNaviMusMiniHidden(UITabBarController *tabs, BOOL hidden);
/// Hides NaviMus's mini player again now and once a page change has settled (it can draw a new one then).
void FZRRecheckNaviMusMini(void);
extern NSString *const FZRKeyTabsFirstPage;   // "fz.redesign.tabsFirstPage": a tab tap opens its first page
/// Chip labels readable on a light accent (FZRLightAccentText.m).
void FZRInstallLightAccentText(void);
/// Hooks tab taps (FZRTabReset.m).
void FZRInstallTabReset(void);
/// Closes NaviMus's own player if it's open without Frozio having shown it. YES if closed.
BOOL FZRCloseStrayNaviMusPlayer(UITabBarController *tabs);
/// The same over the next few seconds (a sheet or an app switch may hold it open a moment).
void FZRCloseStrayNaviMusPlayerSoon(UITabBarController *tabs);
/// Whether NaviMus's own player is open on screen because Frozio showed it.
BOOL FZRNaviMusPlayerShown(void);
/// Shows NaviMus's own player as it is (the queue, ratings, what Frozio hasn't rebuilt). Frozio's bar steps aside
/// until it closes.
void FZRShowNaviMusPlayer(UITabBarController *tabs, UIView *frozioBar);
/// Presses the control labelled one of `labels` in NaviMus's player (or the item of its ⋯ menu), with the player
/// opened out of sight and closed again. Completion on the main thread.
void FZRNaviMusPlayerAction(UITabBarController *tabs, UIView *frozioBar, NSArray<NSString *> *labels, void (^completion)(BOOL ok, NSString *why));
