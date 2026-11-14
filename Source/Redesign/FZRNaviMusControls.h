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

/// Activates the first accessibility element of NaviMus's page `page` (its content, then its navigation bar,
/// where its toolbar items are) whose label is one of `labels` (case-insensitive). NO when none is found.
BOOL FZRActivateNaviMusControl(UIViewController *page, NSArray<NSString *> *labels);

/// Installs page interception when the redesign is on. Call before NaviMus's main().
void FZRInstallPages(void);
