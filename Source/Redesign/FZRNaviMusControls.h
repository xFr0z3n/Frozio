// The redesign's bridge to NaviMus (docs/REDESIGN_PLAN.md):
// - its own App Intents for playing and opening (FZNaviMus.swift),
// - its own controls on the page a rebuilt page covers, reached through accessibility, so NaviMus keeps
//   doing the downloading, shuffling and menus itself,
// - page interception: when NaviMus pushes a page the redesign rebuilds, the rebuilt page is laid over it.
#pragma once
#import <UIKit/UIKit.h>

/// kind: "Album", "Artist", "Playlist", "Song". Completion on the main thread; `why` says what failed.
void FZRNaviMusPlay(NSString *kind, NSString *identifier, void (^completion)(BOOL ok, NSString *why));
void FZRNaviMusOpen(NSString *kind, NSString *identifier, void (^completion)(BOOL ok, NSString *why));
/// Runs one of NaviMus's parameterless App Intents by name ("LikeSongIntent").
void FZRNaviMusPerform(NSString *intent, void (^completion)(BOOL ok, NSString *why));

/// Activates the first accessibility element of NaviMus's page `page` (its content, then its navigation bar,
/// where its toolbar items are) whose label is one of `labels` (case-insensitive). With `after`, only elements
/// after the one labelled `after` (a song's row: its own ⋯). NO when none is found.
BOOL FZRActivateNaviMusControl(UIViewController *page, NSString *after, NSArray<NSString *> *labels);

/// The same, falling back to a real tap (FZRTap) where activation is refused (SwiftUI menus on iOS 17). With
/// `alignTo` (window coordinates, not CGPointZero), NaviMus's list first scrolls the control to that point, so
/// what it opens is anchored where the user tapped.
BOOL FZRPressNaviMusControl(UIViewController *page, NSString *after, NSArray<NSString *> *labels, CGPoint alignTo);

/// Taps the row of NaviMus's page whose title is `title` (a plain element, so it's tapped, not activated), its list
/// first scrolled so the row is under `alignTo`. NaviMus then does what its own row does (an album's song plays with the
/// rest of the album after it).
BOOL FZRTapNaviMusRow(UIViewController *page, NSString *title, CGPoint alignTo);

/// Runs the action titled one of `labels` from the menu of the control under `point` (window coordinates) without
/// showing the menu: a UIButton's menu, or a context-menu interaction's. NO when there's none.
BOOL FZRPerformMenuAction(UIWindow *window, CGPoint point, NSArray<NSString *> *labels);

/// FZRPerformMenuAction, and where the menu has no items yet (a SwiftUI menu fills them when it first shows), its
/// control at `point` is tapped, the menu it opens is kept out of sight, the action is performed and the menu
/// closed. If the menu has no such action it's shown for the user to pick. Completion on the main thread.
void FZRPerformMenuActionUnseen(UIWindow *window, CGPoint point, NSArray<NSString *> *labels, void (^completion)(BOOL ok));

/// Activates an item of the menu on screen whose label is one of `labels` (or starts with one and a space).
BOOL FZRActivateMenuItem(NSArray<NSString *> *labels);

/// Every labelled accessibility element under `root` (its accessibility tree and its subviews), hidden views left out.
NSArray *FZRAccessibilityElementsIn(UIView *root);
/// An element for the log: "label" button <class>.
NSString *FZRDescribeElement(id element);
/// Where an element is pressed, in `window`'s coordinates.
CGPoint FZRElementPoint(UIWindow *window, id element);

/// Hides NaviMus's navigation bar's drawing under a rebuilt page (and keeps it hidden through UIKit's and
/// SwiftUI's own updates), or shows it again; alongside `transition` when there is one.
void FZRSetNaviMusBarHidden(UIViewController *page, BOOL hidden, id<UIViewControllerTransitionCoordinator> transition);

/// Installs page interception when the redesign is on. Call before NaviMus's main().
void FZRInstallPages(void);

/// NaviMus's own icon for a menu item, once Frozio has read one of its menus holding it; nil before.
UIImage *FZRNaviMusMenuIcon(NSString *title);

/// A cover NaviMus has cached on disk (its 800, 400 or 200 px copy), nil when it has none. Main thread or not.
UIImage *FZRNaviMusCachedCover(NSString *coverArtID);
/// The album's coverArt ID as NaviMus's page holds it (a Library route carries the whole album), nil when unknown.
NSString *FZRNaviMusPageCoverArt(UIViewController *page);
