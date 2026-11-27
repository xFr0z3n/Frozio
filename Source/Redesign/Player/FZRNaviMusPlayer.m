// NaviMus's own mini player and player under Frozio's (see FZRPlayer.h).
//
// iOS 17: each tab's hosting view carries a `SwiftUI._UIInheritedView` band from 692 to the bottom of an 844 pt
// screen, under the 83 pt tab bar (device probe, build 33): NaviMus's backdrop. Its visible card is drawn in the
// root hosting view over the tabs (build 40). Both are hidden the way NaviMus's navigation bar is under a rebuilt
// page: a layer mask (still laid out and in accessibility, so their controls can be pressed) and no touches.
#import <objc/runtime.h>
#import "Redesign/Player/FZRPlayer.h"
#import "Redesign/FZRNaviMusControls.h"
#import "Redesign/FZRTap.h"
#import "Core/FZLog.h"
#import "Core/FZRemote.h"

static char kBandHiddenKey;
static NSHashTable<UIView *> *sHiddenBands;
static BOOL sShown, sBusy;

// Taller than this, the band is NaviMus's open player rather than its mini player.
static const CGFloat kOpenHeight = 320;

static BOOL isBandClass(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name rangeOfString:@"InheritedView"].location != NSNotFound
        || [name rangeOfString:@"BottomAccessory"].location != NSNotFound
        || [name rangeOfString:@"TabAccessory"].location != NSNotFound;
}

static BOOL isSwiftUIClass(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name rangeOfString:@"SwiftUI"].location != NSNotFound || isBandClass(view);
}

// The view the tab bar controller sits in: NaviMus's root hosting view (its RootModifier), where NaviMus draws its
// visible mini player card over the tabs (device, build 40: the card covered Frozio's bar in the tabs' view).
static UIView *hostOf(UITabBarController *tabs) {
    UIView *host = tabs.parentViewController.view;
    return host && [tabs.view isDescendantOfView:host] ? host : tabs.view;
}

static CGFloat tabTopIn(UITabBarController *tabs, UIView *view) {
    UITabBar *bar = tabs.tabBar;
    if (!bar.window || bar.hidden || bar.alpha < 0.01) return view.bounds.size.height;
    return CGRectGetMinY([bar convertRect:bar.bounds toView:view]);
}

// NaviMus's backdrop band in the selected tab (iOS 17: `_UIInheritedView`, 692 to the bottom, under the tab bar).
static UIView *contentBand(UITabBarController *tabs) {
    UIView *root = tabs.view;
    UIView *content = tabs.selectedViewController.view;
    if (!root || !content) return nil;
    CGFloat height = root.bounds.size.height;
    CGFloat reach = MIN(height - 1, tabTopIn(tabs, root) - 1);
    // Breadth first, so the outermost band wins (NaviMus nests two of the same frame).
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:content];
    NSMutableArray<NSNumber *> *depths = [NSMutableArray arrayWithObject:@0];
    while (queue.count) {
        UIView *view = queue.firstObject;
        NSInteger depth = depths.firstObject.integerValue;
        [queue removeObjectAtIndex:0];
        [depths removeObjectAtIndex:0];
        if (view != content && isBandClass(view)) {
            CGRect frame = [view convertRect:view.bounds toView:root];
            BOOL bottom = CGRectGetMaxY(frame) >= reach && CGRectGetMinY(frame) > 0;
            BOOL mini = frame.size.height >= 40 && frame.size.height <= kOpenHeight && CGRectGetMinY(frame) > height / 2;
            BOOL open = frame.size.height > kOpenHeight;   // NaviMus's player while it's open
            if (bottom && (mini || open)) return view;
        }
        if (depth >= 4) continue;
        for (UIView *sub in view.subviews) {
            [queue addObject:sub];
            [depths addObject:@(depth + 1)];
        }
    }
    return nil;
}

static void logRootTree(UITabBarController *tabs, UIView *host) {
#ifdef FROZIO_DEBUG
    static NSInteger logged;
    static CFTimeInterval last;
    if (!FZNowPlayingInfo() || logged >= 4 || CACurrentMediaTime() - last < 2) return;
    logged++;
    last = CACurrentMediaTime();
    CGFloat height = host.bounds.size.height;
    NSMutableArray *lines = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:host];
    NSMutableArray<NSNumber *> *depths = [NSMutableArray arrayWithObject:@0];
    while (queue.count && lines.count < 80) {
        UIView *view = queue.firstObject;
        NSInteger depth = depths.firstObject.integerValue;
        [queue removeObjectAtIndex:0];
        [depths removeObjectAtIndex:0];
        CGRect frame = [view convertRect:view.bounds toView:host];
        if (CGRectGetMaxY(frame) > height - 260 || view == host) {
            NSString *name = NSStringFromClass(view.class);
            [lines addObject:[NSString stringWithFormat:@"%ld %@ %@%@%@%@", (long)depth, [name substringToIndex:MIN(70, name.length)],
                              NSStringFromCGRect(frame), view.hidden ? @" hidden" : @"", view.alpha < 1 ? [NSString stringWithFormat:@" a%.2f", view.alpha] : @"",
                              view == tabs.view ? @" (tabs)" : @""]];
        }
        if (view == tabs.view || [view isKindOfClass:UIScrollView.class] || depth >= 7 || [view.accessibilityIdentifier isEqualToString:@"FZRMiniPlayer"]) continue;
        for (UIView *sub in view.subviews) { [queue addObject:sub]; [depths addObject:@(depth + 1)]; }
    }
    FZLog("player: root %@ bottom: %@", NSStringFromClass(host.class), [lines componentsJoinedByString:@" | "]);
#endif
}

// NaviMus's visible mini player card (and its player when open): drawn in the root hosting view over the tabs.
static UIView *rootCard(UITabBarController *tabs) {
    UIView *host = hostOf(tabs);
    if (host == tabs.view) return nil;
    logRootTree(tabs, host);
    CGFloat width = host.bounds.size.width, height = host.bounds.size.height, tabTop = tabTopIn(tabs, host);
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:host.subviews];
    NSMutableArray<NSNumber *> *depths = [NSMutableArray array];
    for (NSUInteger i = 0; i < queue.count; i++) [depths addObject:@1];
    while (queue.count) {
        UIView *view = queue.firstObject;
        NSInteger depth = depths.firstObject.integerValue;
        [queue removeObjectAtIndex:0];
        [depths removeObjectAtIndex:0];
        if (view == tabs.view || [view.accessibilityIdentifier isEqualToString:@"FZRMiniPlayer"] || [view isKindOfClass:UIScrollView.class]) continue;
        BOOL ancestor = [tabs.view isDescendantOfView:view];
        if (!ancestor && isSwiftUIClass(view) && !view.hidden) {
            CGRect frame = [view convertRect:view.bounds toView:host];
            BOOL wide = frame.size.width >= width * 0.8;
            BOOL mini = frame.size.height >= 40 && frame.size.height <= kOpenHeight && CGRectGetMinY(frame) > height / 2
                && CGRectGetMinY(frame) < tabTop && CGRectGetMaxY(frame) >= tabTop - 24;
            BOOL open = isBandClass(view) && frame.size.height > kOpenHeight;
            if (wide && (mini || open)) return view;
        }
        if (depth >= 6) continue;
        for (UIView *sub in view.subviews) { [queue addObject:sub]; [depths addObject:@(depth + 1)]; }
    }
    return nil;
}

// SwiftUI may draw the card's contents as loose siblings of its background (harness): every other NaviMus view in
// the root view that lies within the card goes with it, so nothing shows through Frozio's translucent bar.
static NSArray<UIView *> *cardCompanions(UITabBarController *tabs, UIView *card) {
    UIView *host = hostOf(tabs);
    if (!card || host == tabs.view) return @[];
    CGRect area = CGRectInset([card convertRect:card.bounds toView:host], -4, -4);
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:host.subviews];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view == card || view == tabs.view || [view.accessibilityIdentifier isEqualToString:@"FZRMiniPlayer"]) continue;
        if ([view isDescendantOfView:card] || [view isKindOfClass:UIScrollView.class]) continue;
        BOOL ancestor = [tabs.view isDescendantOfView:view] || [card isDescendantOfView:view];
        if (!ancestor && isSwiftUIClass(view) && CGRectContainsRect(area, [view convertRect:view.bounds toView:host])) {
            [found addObject:view];
            continue;
        }
        if (ancestor) [queue addObjectsFromArray:view.subviews];
    }
    return found;
}

UIView *FZRNaviMusMiniBand(UITabBarController *tabs) {
    return rootCard(tabs) ?: contentBand(tabs);
}

// `from`: the band is hidden above this y (its own coordinates) and left as it is below, where NaviMus's backdrop
// behind the tab bar lies (hiding all of it left the tab bar see-through on device, build 40). 0 hides all of it.
static void hideBand(UIView *band, BOOL hidden, CGFloat from) {
    if (!band) return;
    if (hidden) {
        CGRect keep = from > 0 && from < band.bounds.size.height
            ? CGRectMake(0, from, band.bounds.size.width, band.bounds.size.height - from) : CGRectZero;
        CALayer *mask = band.layer.mask;
        if (!mask || !objc_getAssociatedObject(band, &kBandHiddenKey)) {
            mask = [CALayer layer];
            mask.backgroundColor = UIColor.blackColor.CGColor;
        }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        mask.frame = keep;
        band.layer.mask = mask;
        [CATransaction commit];
        band.userInteractionEnabled = NO;
        objc_setAssociatedObject(band, &kBandHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!sHiddenBands) sHiddenBands = [NSHashTable weakObjectsHashTable];
        [sHiddenBands addObject:band];
    } else {
        band.layer.mask = nil;
        band.userInteractionEnabled = YES;
        objc_setAssociatedObject(band, &kBandHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sHiddenBands removeObject:band];
    }
}

// What was found last time, to check cheaply on each layout (the search walked NaviMus's whole root view on every
// layout pass, which slowed the app down while pages moved; device, build 51).
static __weak UIView *sCard, *sBand;
static CFTimeInterval sLastSearch;

static BOOL stillHidden(UIView *view, UITabBarController *tabs) {
    return view && view.window == tabs.view.window && objc_getAssociatedObject(view, &kBandHiddenKey) && view.layer.mask;
}

void FZRSetNaviMusMiniHidden(UITabBarController *tabs, BOOL hidden) {
    if (sShown || sBusy) return;   // NaviMus's player is in use; it's hidden again when that ends
    if (!hidden) {
        for (UIView *view in sHiddenBands.allObjects) hideBand(view, NO, 0);
        sCard = sBand = nil;
        return;
    }
    // Both still in place and masked: nothing to do, unless it's been a while (NaviMus may have built a new one).
    CFTimeInterval now = CACurrentMediaTime();
    UIView *knownCard = sCard, *knownBand = sBand;
    if ((knownCard || knownBand) && (!knownCard || stillHidden(knownCard, tabs)) && (!knownBand || stillHidden(knownBand, tabs))
        && now - sLastSearch < 1.0) return;
    sLastSearch = now;
    UIView *card = rootCard(tabs), *band = contentBand(tabs);
    sCard = card;
    sBand = band;
    NSMutableArray *views = [NSMutableArray array];
    if (card) [views addObject:card];
    if (band) [views addObject:band];
    for (UIView *companion in cardCompanions(tabs, card)) {
        if (!objc_getAssociatedObject(companion, &kBandHiddenKey)) hideBand(companion, YES, 0);
    }
    for (UIView *view in views) {
        if (!objc_getAssociatedObject(view, &kBandHiddenKey)) {
            FZLog("player: NaviMus's %@ hidden (%@ %@)", view == card ? @"mini player card" : @"mini player band", NSStringFromClass(view.class),
                  NSStringFromCGRect([view convertRect:view.bounds toView:hostOf(tabs)]));
        }
        // The card all of it; the band down to the tab bar, which keeps NaviMus's backdrop.
        CGFloat from = view == band ? tabTopIn(tabs, view) : 0;
        hideBand(view, YES, from);
    }
}

BOOL FZRNaviMusPlayerShown(void) { return sShown; }

static BOOL isOpen(UITabBarController *tabs, UIView *band) {
    if (band.bounds.size.height > kOpenHeight) return YES;
    UIViewController *presented = tabs.view.window.rootViewController.presentedViewController;
    return presented && ![NSStringFromClass(presented.class) hasPrefix:@"FZ"]
        && [NSStringFromClass(presented.class) rangeOfString:@"ContextMenu"].location == NSNotFound;
}

// Where NaviMus's mini player takes a tap that opens its player: left of its buttons, over its title.
static CGPoint miniPoint(UITabBarController *tabs, UIView *band) {
    UIWindow *window = tabs.view.window;
    CGRect frame = [band convertRect:band.bounds toView:window];
    // The mini player is the band's top: down to the tab bar on device (69 pt), at most 80 pt.
    CGFloat mini = tabTopIn(tabs, window) - CGRectGetMinY(frame);
    if (mini < 30) mini = 64;
    mini = MIN(MIN(mini, 80), frame.size.height);
    return CGPointMake(CGRectGetMinX(frame) + frame.size.width * 0.35, CGRectGetMinY(frame) + mini / 2);
}

static void logElements(NSString *when, NSArray *elements) {
#ifdef FROZIO_DEBUG
    NSMutableArray *names = [NSMutableArray array];
    for (id element in elements) [names addObject:FZRDescribeElement(element)];
    FZLog("player: NaviMus's player %@: %lu elements: %@", when, (unsigned long)elements.count, [names componentsJoinedByString:@", "]);
#endif
}

// SwiftUI lists the band's controls on the tab's hosting view rather than on the band (harness): the tab's elements
// whose frame lies in the band, and the band's own.
static NSArray *bandElements(UITabBarController *tabs, UIView *band) {
    UIWindow *window = tabs.view.window;
    CGRect frame = [band convertRect:band.bounds toView:window];
    NSMutableArray *elements = [NSMutableArray array];
    for (id element in FZRAccessibilityElementsIn(hostOf(tabs))) {
        CGRect screen = [element accessibilityFrame];
        CGRect inWindow = [window convertRect:screen fromCoordinateSpace:window.screen.coordinateSpace];
        CGPoint center = CGPointMake(CGRectGetMidX(inWindow), CGRectGetMidY(inWindow));
        if (CGRectContainsPoint(frame, center) && ![elements containsObject:element]) [elements addObject:element];
    }
    for (id element in FZRAccessibilityElementsIn(band)) if (![elements containsObject:element]) [elements addObject:element];
    return elements;
}

static NSArray *playerElements(UITabBarController *tabs, UIView *band) {
    NSMutableArray *elements = [NSMutableArray arrayWithArray:bandElements(tabs, band)];
    UIViewController *presented = tabs.view.window.rootViewController.presentedViewController;
    if (presented && ![NSStringFromClass(presented.class) hasPrefix:@"FZ"]) [elements addObjectsFromArray:FZRAccessibilityElementsIn(presented.view)];
    return elements;
}

static id buttonLabelled(NSArray *elements, NSArray<NSString *> *labels) {
    for (NSString *wanted in labels) {
        for (id element in elements) {
            if (!([element accessibilityTraits] & UIAccessibilityTraitButton)) continue;
            NSString *label = [element accessibilityLabel];
            if ([label caseInsensitiveCompare:wanted] == NSOrderedSame || [label.lowercaseString hasPrefix:[wanted.lowercaseString stringByAppendingString:@" "]]) return element;
        }
    }
    return nil;
}

static BOOL press(UIWindow *window, id element) {
    if ([element accessibilityActivate]) return YES;
    return FZRTap(window, FZRElementPoint(window, element));
}

void FZRShowNaviMusPlayer(UITabBarController *tabs, UIView *frozioBar) {
    UIView *band = FZRNaviMusMiniBand(tabs);
    UIWindow *window = tabs.view.window;
    if (!band || !window || sShown || sBusy) {
        FZLogError("player: NaviMus's player can't be shown (band %d window %d busy %d)", band != nil, window != nil, sShown || sBusy);
        return;
    }
    for (UIView *view in sHiddenBands.allObjects) hideBand(view, NO, 0);
    sShown = YES;
    frozioBar.hidden = YES;
    BOOL tapped = FZRTapIn(tabs.view, miniPoint(tabs, band));
    FZLog("player: showing NaviMus's player (tap %d)", tapped);
    __weak UITabBarController *weakTabs = tabs;
    __weak UIView *weakBar = frozioBar;
    __block BOOL opened = NO;
    __block NSUInteger ticks = 0;
    __block void (^watch)(void);
    watch = ^{
        UITabBarController *tabs = weakTabs;
        UIView *band = FZRNaviMusMiniBand(tabs);
        BOOL open = tabs && isOpen(tabs, band);
        ticks++;
        if (open && !opened) { opened = YES; logElements(@"shown", playerElements(tabs, band)); }
        // Closed again, or never opened within 3 s: Frozio's bar comes back.
        if ((opened && !open) || (!opened && ticks > 10) || !tabs) {
            sShown = NO;
            weakBar.hidden = NO;
            if (tabs && FZRPlayerActive()) FZRSetNaviMusMiniHidden(tabs, YES);
            FZLog("player: NaviMus's player %@", opened ? @"closed" : @"didn't open");
            watch = nil;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (watch) watch(); });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (watch) watch(); });
}

#pragma mark - a control of NaviMus's player, out of sight

static NSArray<NSString *> *closeLabels(void) {
    return @[@"Go Down", @"Close", @"Dismiss", @"Minimize", @"Minimise", @"Collapse", @"Hide Player", @"Close Player", @"chevron.down", @"Down", @"Done"];
}

// Frozio's own pages presented over the app (its player) let touches through while NaviMus's player is used
// under them, so window hit tests reach NaviMus.
static NSHashTable<UIView *> *sPassedThrough;

static void passThroughFrozio(UITabBarController *tabs, BOOL through) {
    if (!through) {
        for (UIView *view in sPassedThrough.allObjects) view.userInteractionEnabled = YES;
        [sPassedThrough removeAllObjects];
        return;
    }
    if (!sPassedThrough) sPassedThrough = [NSHashTable weakObjectsHashTable];
    for (UIViewController *vc = tabs.view.window.rootViewController.presentedViewController; vc; vc = vc.presentedViewController) {
        if (![NSStringFromClass(vc.class) hasPrefix:@"FZ"]) continue;
        UIView *container = vc.presentationController.containerView ?: vc.view.superview;
        if (!container || container == tabs.view.window || !container.userInteractionEnabled) continue;
        container.userInteractionEnabled = NO;
        [sPassedThrough addObject:container];
    }
}

// NaviMus's own player open when Frozio didn't show it (left behind after a menu action whose sheet came up first,
// or restored when the app comes back): invisible under Frozio's mask, its AirPlay, share and other buttons sat over
// the tab bar and took its taps (device, build 57: Home opened AirDrop). Closed with its own "Go Down".
BOOL FZRCloseStrayNaviMusPlayer(UITabBarController *tabs) {
    if (!tabs || sShown || sBusy) return NO;
    UIView *band = FZRNaviMusMiniBand(tabs);
    if (!band) return NO;
    // Open is when its own "Go Down" is there (the band's height doesn't tell: 844 pt either way on device).
    id close = buttonLabelled(bandElements(tabs, band), @[@"Go Down"]);
    if (!close) return NO;
    BOOL closed = press(tabs.view.window, close);
    FZLog("player: stray NaviMus player closed=%d", closed);
    return closed;
}

static void closeStrayLater(UITabBarController *tabs, NSUInteger tries) {
    __weak UITabBarController *weakTabs = tabs;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UITabBarController *t = weakTabs;
        if (!t || sShown || sBusy) return;
        if (FZRCloseStrayNaviMusPlayer(t) || tries < 6) {
            if (tries < 12) closeStrayLater(t, tries + 1);   // a few looks: a sheet or app switch may bring it up late
        } else if (FZRPlayerActive()) {
            FZRSetNaviMusMiniHidden(t, YES);
        }
    });
}

void FZRCloseStrayNaviMusPlayerSoon(UITabBarController *tabs) { closeStrayLater(tabs, 0); }

// A still of the screen laid over the app while NaviMus's player opens and closes under it: SwiftUI makes a new view
// for the open player, which Frozio's mask doesn't cover, so it showed for a moment (device, build 59: "Quick Settings
// still showed the old player for a second"). Sheets NaviMus presents come above the still; it fades once the player
// has closed.
static UIView *sShield;

static void raiseShield(UIWindow *window) {
    [sShield removeFromSuperview];
    sShield = [window snapshotViewAfterScreenUpdates:NO];
    if (!sShield) return;
    sShield.frame = window.bounds;
    sShield.userInteractionEnabled = NO;    // Frozio finds NaviMus's controls under it by hit-testing
    [window addSubview:sShield];
}

static void lowerShield(UITabBarController *tabs, NSUInteger tries) {
    if (!sShield) return;
    UIView *band = FZRNaviMusMiniBand(tabs);
    BOOL stillOpen = band && buttonLabelled(bandElements(tabs, band), @[@"Go Down"]);
    if (stillOpen && tries < 20) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ lowerShield(tabs, tries + 1); });
        return;
    }
    // Its closing animation first, then away.
    UIView *shield = sShield;
    sShield = nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.15 animations:^{ shield.alpha = 0; } completion:^(BOOL done) { [shield removeFromSuperview]; }];
    });
}

static void finishAction(UITabBarController *tabs, UIView *frozioBar, BOOL ok, NSString *why, void (^completion)(BOOL, NSString *)) {
    UIView *band = FZRNaviMusMiniBand(tabs);
    UIWindow *window = tabs.view.window;
    // NaviMus's player closed again; if it has no close control the band stays out of sight and untouchable.
    if (band && isOpen(tabs, band)) {
        NSArray *elements = playerElements(tabs, band);
        id close = buttonLabelled(elements, closeLabels());
        BOOL closed = close && press(window, close);
        FZLog("player: NaviMus's player closed=%d with %@", closed, close ? FZRDescribeElement(close) : @"nothing");
        if (!closed) logElements(@"left open", elements);
    }
    sBusy = NO;
    frozioBar.userInteractionEnabled = YES;
    passThroughFrozio(tabs, NO);
    if (band && FZRPlayerActive()) FZRSetNaviMusMiniHidden(tabs, YES);
    // A sheet NaviMus presents from the item (Quick Settings, playlists…) can keep its player from closing at once.
    closeStrayLater(tabs, 0);
    lowerShield(tabs, 0);
    // The unseen player and menu leave UIKit's status bar hidden until something asks again (harness).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIViewController *vc = window.rootViewController; vc; vc = vc.presentedViewController) [vc setNeedsStatusBarAppearanceUpdate];
    });
    completion(ok, why);
}

static void runPlayerAction(UITabBarController *tabs, UIView *frozioBar, NSArray<NSString *> *labels, void (^completion)(BOOL, NSString *));

// Started on the next turn of the run loop: a button calls this from inside UIKit's delivery of the user's own touch,
// and Frozio's taps share UIKit's touch event, which left the next real touch going to NaviMus (harness).
void FZRNaviMusPlayerAction(UITabBarController *tabs, UIView *frozioBar, NSArray<NSString *> *labels, void (^completion)(BOOL, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{ runPlayerAction(tabs, frozioBar, labels, completion); });
}

static void runPlayerAction(UITabBarController *tabs, UIView *frozioBar, NSArray<NSString *> *labels, void (^completion)(BOOL, NSString *)) {
    UIView *band = FZRNaviMusMiniBand(tabs);
    UIWindow *window = tabs.view.window;
    if (!band || !window) { completion(NO, @"NaviMus's mini player wasn't found."); return; }
    if (sShown || sBusy) { completion(NO, @"NaviMus's player is busy."); return; }
    sBusy = YES;
    raiseShield(window);
    frozioBar.userInteractionEnabled = NO;
    passThroughFrozio(tabs, YES);
    band.userInteractionEnabled = YES;   // still masked: NaviMus's player opens out of sight
    logElements(@"before", bandElements(tabs, band));
    if (!FZRTapIn(tabs.view, miniPoint(tabs, band))) {
        finishAction(tabs, frozioBar, NO, @"NaviMus's player couldn't be opened.", completion);
        return;
    }
    __weak UITabBarController *weakTabs = tabs;
    __weak UIView *weakBar = frozioBar;
    __block NSUInteger tries = 0, openTicks = 0;
    __block void (^step)(void);
    step = ^{
        // Held here: `step = nil` below releases this block and what it captured.
        void (^done)(BOOL, NSString *) = completion;
        NSArray<NSString *> *wanted = labels;
        UIView *bar = weakBar;
        UITabBarController *tabs = weakTabs;
        UIView *band = FZRNaviMusMiniBand(tabs);
        if (!tabs || !band) { sBusy = NO; [sShield removeFromSuperview]; sShield = nil; bar.userInteractionEnabled = YES; passThroughFrozio(nil, NO); done(NO, @"NaviMus's player went away."); step = nil; return; }
        tries++;
        BOOL open = isOpen(tabs, band);
        if (open) openTicks++;
        // Let it settle for a moment once open: SwiftUI lists its controls a frame or two after showing them.
        if (open && openTicks >= 3) {
            NSArray *elements = playerElements(tabs, band);
            logElements(@"open", elements);
            id direct = buttonLabelled(elements, wanted);
            if (direct) {
                BOOL pressed = press(tabs.view.window, direct);
                FZLog("player: NaviMus's %@ pressed=%d", FZRDescribeElement(direct), pressed);
                step = nil;
                finishAction(tabs, bar, pressed, pressed ? nil : @"NaviMus's control refused the press.", done);
                return;
            }
            id more = buttonLabelled(elements, @[@"More", @"More Options", @"Options", @"ellipsis", @"Menu", @"Song Menu"]);
            if (more) {
                CGPoint point = FZRElementPoint(tabs.view.window, more);
                FZLog("player: NaviMus's player menu at %@", NSStringFromCGPoint(point));
                step = nil;
                FZRPerformMenuActionUnseen(tabs.view.window, point, wanted, ^(BOOL ok) {
                    finishAction(tabs, bar, ok, ok ? nil : [NSString stringWithFormat:@"NaviMus's player menu has no %@ item.", wanted.firstObject], done);
                });
                return;
            }
            step = nil;
            finishAction(tabs, bar, NO, [NSString stringWithFormat:@"NaviMus's player has no %@ control or menu.", wanted.firstObject], done);
            return;
        }
        if (tries > 30) {
            step = nil;
            FZLogError("player: NaviMus's player didn't open (band %@)", NSStringFromCGRect(band.frame));
            finishAction(tabs, bar, NO, @"NaviMus's player didn't open.", done);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (step) step(); });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (step) step(); });
}
