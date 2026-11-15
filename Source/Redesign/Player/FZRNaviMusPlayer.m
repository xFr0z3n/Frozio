// NaviMus's own mini player and player under Frozio's (see FZRPlayer.h).
//
// iOS 17 (device probe, build 33): each tab's hosting view carries a `SwiftUI._UIInheritedView` band from 692 to
// the bottom of an 844 pt screen, under the 83 pt tab bar: NaviMus's mini player, which grows into its player.
// It's hidden the way NaviMus's navigation bar is under a rebuilt page: an empty layer mask (still laid out and
// still in accessibility, so its controls can be pressed) and no touches.
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

UIView *FZRNaviMusMiniBand(UITabBarController *tabs) {
    UIView *root = tabs.view;
    UIView *content = tabs.selectedViewController.view;
    if (!root || !content) return nil;
    CGFloat height = root.bounds.size.height;
    // It reaches the bottom (NaviMus, under its tab bar) or at least the tab bar's top.
    CGFloat reach = height - 1;
    if (tabs.tabBar.window && !tabs.tabBar.hidden) reach = MIN(reach, CGRectGetMinY([tabs.tabBar convertRect:tabs.tabBar.bounds toView:root]) - 1);
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
#ifdef FROZIO_DEBUG
    // Once per tab: what is there instead, for the next build.
    // Up to three times, a second apart, while a song is on (SwiftUI may draw the band a moment after it starts).
    static NSMapTable *logged;
    static CFTimeInterval last;
    if (!logged) logged = [NSMapTable weakToStrongObjectsMapTable];
    NSInteger count = [[logged objectForKey:content] integerValue];
    if (FZNowPlayingInfo() && count < 3 && CACurrentMediaTime() - last > 1) {
        [logged setObject:@(count + 1) forKey:content];
        last = CACurrentMediaTime();
        NSMutableArray *seen = [NSMutableArray array];
        NSMutableArray<UIView *> *walk = [NSMutableArray arrayWithObject:content];
        while (walk.count && seen.count < 60) {
            UIView *view = walk.firstObject;
            [walk removeObjectAtIndex:0];
            CGRect frame = [view convertRect:view.bounds toView:root];
            if (CGRectGetMaxY(frame) > height - 300 && view != content) {
                [seen addObject:[NSString stringWithFormat:@"%@ %@", [NSStringFromClass(view.class) substringToIndex:MIN(60, NSStringFromClass(view.class).length)], NSStringFromCGRect(frame)]];
            }
            if ([view isKindOfClass:UIScrollView.class]) continue;
            [walk addObjectsFromArray:view.subviews];
        }
        FZLog("player: no mini player band found in %@; bottom views: %@", NSStringFromClass(content.class), [seen componentsJoinedByString:@"; "]);
    }
#endif
    return nil;
}

static void hideBand(UIView *band, BOOL hidden) {
    if (!band) return;
    if (hidden) {
        CALayer *mask = [CALayer layer];
        mask.frame = CGRectZero;
        band.layer.mask = mask;
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

void FZRSetNaviMusMiniHidden(UITabBarController *tabs, BOOL hidden) {
    if (sShown || sBusy) return;   // NaviMus's player is in use; it's hidden again when that ends
    UIView *band = FZRNaviMusMiniBand(tabs);
    if (hidden) {
        if (band && !objc_getAssociatedObject(band, &kBandHiddenKey)) {
            FZLog("player: NaviMus's mini player hidden (%@ %@)", NSStringFromClass(band.class),
                  NSStringFromCGRect([band convertRect:band.bounds toView:tabs.view]));
        }
        hideBand(band, YES);
        return;
    }
    for (UIView *view in sHiddenBands.allObjects) hideBand(view, NO);
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
    CGRect bar = [tabs.tabBar convertRect:tabs.tabBar.bounds toView:window];
    // The mini player is the band's top: down to the tab bar on device (69 pt), at most 80 pt.
    CGFloat mini = CGRectGetMinY(bar) - CGRectGetMinY(frame);
    if (tabs.tabBar.hidden || mini < 30) mini = 64;
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
    for (id element in FZRAccessibilityElementsIn(tabs.selectedViewController.view)) {
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
    sShown = YES;
    hideBand(band, NO);
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
    return @[@"Close", @"Dismiss", @"Minimize", @"Minimise", @"Collapse", @"Hide Player", @"Close Player", @"chevron.down", @"Down", @"Done"];
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
    if (band) hideBand(band, YES);
    completion(ok, why);
}

void FZRNaviMusPlayerAction(UITabBarController *tabs, UIView *frozioBar, NSArray<NSString *> *labels, void (^completion)(BOOL, NSString *)) {
    UIView *band = FZRNaviMusMiniBand(tabs);
    UIWindow *window = tabs.view.window;
    if (!band || !window) { completion(NO, @"NaviMus's mini player wasn't found."); return; }
    if (sShown || sBusy) { completion(NO, @"NaviMus's player is busy."); return; }
    sBusy = YES;
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
        UITabBarController *tabs = weakTabs;
        UIView *band = FZRNaviMusMiniBand(tabs);
        if (!tabs || !band) { sBusy = NO; weakBar.userInteractionEnabled = YES; passThroughFrozio(nil, NO); done(NO, @"NaviMus's player went away."); step = nil; return; }
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
                finishAction(tabs, weakBar, pressed, pressed ? nil : @"NaviMus's control refused the press.", done);
                return;
            }
            id more = buttonLabelled(elements, @[@"More", @"More Options", @"Options", @"ellipsis", @"Menu", @"Song Menu"]);
            if (more) {
                CGPoint point = FZRElementPoint(tabs.view.window, more);
                FZLog("player: NaviMus's player menu at %@", NSStringFromCGPoint(point));
                step = nil;
                FZRPerformMenuActionUnseen(tabs.view.window, point, wanted, ^(BOOL ok) {
                    finishAction(tabs, weakBar, ok, ok ? nil : @"NaviMus's player menu has no Download item.", done);
                });
                return;
            }
            step = nil;
            finishAction(tabs, weakBar, NO, @"NaviMus's player has no Download control or menu.", done);
            return;
        }
        if (tries > 30) {
            step = nil;
            FZLogError("player: NaviMus's player didn't open (band %@)", NSStringFromCGRect(band.frame));
            finishAction(tabs, weakBar, NO, @"NaviMus's player didn't open.", done);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (step) step(); });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (step) step(); });
}
