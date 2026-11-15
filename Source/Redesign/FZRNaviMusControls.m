#import <objc/message.h>
#import <objc/runtime.h>
#import "Redesign/FZRNaviMusControls.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Album/FZRAlbumPage.h"
#import "Redesign/FZRTap.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

#pragma mark - intents (FZNaviMus.swift)

static void callIntent(NSString *selector, NSString *kind, NSString *identifier, void (^completion)(BOOL, NSString *)) {
    Class bridge = NSClassFromString(@"FZNaviMus");
    SEL sel = NSSelectorFromString(selector);
    if (!identifier.length || ![bridge respondsToSelector:sel]) {
        completion(NO, identifier.length ? @"Frozio's Swift bridge is missing" : @"No ID");
        return;
    }
    FZLog("redesign: %@ %@", selector, kind);
    ((void (*)(id, SEL, NSString *, NSString *, id))objc_msgSend)(bridge, sel, kind, identifier, completion);
}

void FZRNaviMusPlay(NSString *kind, NSString *identifier, void (^completion)(BOOL, NSString *)) {
    callIntent(@"play:id:completion:", kind, identifier, completion);
}

void FZRNaviMusOpen(NSString *kind, NSString *identifier, void (^completion)(BOOL, NSString *)) {
    callIntent(@"open:id:completion:", kind, identifier, completion);
}

static NSString *pageType(UIViewController *vc) {
    Class bridge = NSClassFromString(@"FZNaviMus");
    SEL sel = NSSelectorFromString(@"pageType:");
    return [bridge respondsToSelector:sel] ? ((NSString *(*)(id, SEL, id))objc_msgSend)(bridge, sel, vc) : nil;
}

static NSString *pageString(UIViewController *vc, NSString *path) {
    Class bridge = NSClassFromString(@"FZNaviMus");
    SEL sel = NSSelectorFromString(@"pageString:path:");
    return [bridge respondsToSelector:sel] ? ((NSString *(*)(id, SEL, id, id))objc_msgSend)(bridge, sel, vc, path) : nil;
}

#pragma mark - NaviMus's controls through accessibility

static char kOverlayKey;
static char kBarHiddenKey;

static BOOL viewIsShown(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01 || objc_getAssociatedObject(v, &kOverlayKey)) return NO;
    }
    return YES;
}

// An element's children: its accessibility children, and for a view its subviews too (NaviMus's list cells
// sit in UIKit views SwiftUI doesn't always list), hidden views and the rebuilt page left out.
static NSArray *childrenOf(id element) {
    NSMutableArray *list = [NSMutableArray array];
    NSArray *children = [element respondsToSelector:@selector(accessibilityElements)] ? [element accessibilityElements] : nil;
    if (children.count) [list addObjectsFromArray:children];
    else {
        NSInteger count = [element respondsToSelector:@selector(accessibilityElementCount)] ? [element accessibilityElementCount] : 0;
        for (NSInteger i = 0; i < count && i < 500; i++) {
            id child = [element accessibilityElementAtIndex:i];
            if (child) [list addObject:child];
        }
    }
    if ([element isKindOfClass:UIView.class]) {
        for (UIView *sub in ((UIView *)element).subviews) if (![list containsObject:sub]) [list addObject:sub];
    }
    return list;
}

static void collect(id element, NSUInteger depth, NSMutableArray *found, NSHashTable *seen) {
    if (!element || depth > 40 || found.count > 600 || [seen containsObject:element]) return;
    [seen addObject:element];
    if ([element isKindOfClass:UIView.class] && !viewIsShown(element)) return;
    if ([element isAccessibilityElement] && [element accessibilityLabel].length) [found addObject:element];
    for (id child in childrenOf(element)) collect(child, depth + 1, found, seen);
}

// NaviMus's page as it really is for an instant: the rebuilt page over it out of the way and its navigation
// bar unmasked and touchable. SwiftUI and UIKit only list and activate controls that are reachable; no frame
// is drawn in between, so it never shows.
static void withNaviMusShown(UIViewController *page, UIView *cover, void (^work)(void)) {
    UINavigationBar *bar = page.navigationController.navigationBar;
    BOOL coverWasHidden = cover.hidden;
    CALayer *mask = bar.layer.mask;
    BOOL touchable = bar.userInteractionEnabled;
    id flag = objc_getAssociatedObject(bar, &kBarHiddenKey);
    objc_setAssociatedObject(bar, &kBarHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    cover.hidden = YES;
    bar.layer.mask = nil;
    bar.userInteractionEnabled = YES;
    @try {
        work();
    } @finally {
        cover.hidden = coverWasHidden;
        bar.layer.mask = mask;
        bar.userInteractionEnabled = touchable;
        objc_setAssociatedObject(bar, &kBarHiddenKey, flag, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

__attribute__((unused)) static NSString *describe(id element) {
    return [NSString stringWithFormat:@"\"%@\"%@ <%@>", [element accessibilityLabel],
            ([element accessibilityTraits] & UIAccessibilityTraitButton) ? @" button" : @"", NSStringFromClass([element class])];
}

// The buttons to press: with an anchor, the first match after the element labelled `after` (NaviMus labels a row
// "<title>", its download ring, then "More"), else every match. Buttons only: activating NaviMus's plain "More"
// element (a row's context menu) put its list into select mode on device (build 36).
static NSArray *candidates(NSArray *elements, NSString *after, NSArray<NSString *> *labels) {
    NSUInteger start = 0;
    if (after.length) {
        start = NSNotFound;
        for (NSUInteger i = 0; i < elements.count; i++) {
            NSString *label = [elements[i] accessibilityLabel];
            if ([label caseInsensitiveCompare:after] == NSOrderedSame || [label hasPrefix:[after stringByAppendingString:@","]]) { start = i + 1; break; }
        }
        if (start == NSNotFound) return @[];
    }
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *wanted in labels) {
        for (NSUInteger i = start; i < elements.count; i++) {
            id element = elements[i];
            if (!([element accessibilityTraits] & UIAccessibilityTraitButton)) continue;
            if ([[element accessibilityLabel] caseInsensitiveCompare:wanted] != NSOrderedSame) continue;
            [found addObject:element];
            if (after.length) break;   // a row's own control or none: never the next row's
        }
    }
    return found;
}

// NaviMus's list under the rebuilt page: the scroll view a control sits in.
static UIScrollView *scrollViewOf(UIView *root, CGPoint pointInRoot) {
    UIScrollView *best = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (objc_getAssociatedObject(view, &kOverlayKey)) continue;
        if ([view isKindOfClass:UIScrollView.class] && CGRectContainsPoint([view convertRect:view.bounds toView:root], pointInRoot)) {
            best = (UIScrollView *)view;   // the innermost wins, as later in the walk
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return best;
}

static CGPoint activationPointIn(UIWindow *window, id element) {
    CGPoint screen = [element accessibilityActivationPoint];
    return [window convertPoint:screen fromCoordinateSpace:window.screen.coordinateSpace];
}

static NSArray *collectAll(UIViewController *page) {
    NSMutableArray *elements = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    collect(page.view, 0, elements, seen);
    UINavigationBar *bar = page.navigationController.navigationBar;
    if (bar) collect(bar, 0, elements, seen);
    return elements;
}

BOOL FZRPressNaviMusControl(UIViewController *page, NSString *after, NSArray<NSString *> *labels, CGPoint alignTo) {
    UIView *root = page.view;
    UIWindow *window = root.window;
    if (!root || !window) return NO;
    UIView *cover = nil;
    for (UIView *sub in root.subviews) if (objc_getAssociatedObject(sub, &kOverlayKey)) cover = sub;
    __block BOOL done = NO;
    __block NSArray *elements = @[];
    // Found and pressed in one go: shown and hidden again in between, SwiftUI rebuilds its accessibility nodes
    // and the ones found first no longer activate (device log, build 35).
    withNaviMusShown(page, cover, ^{
        elements = collectAll(page);
        NSArray *found = candidates(elements, after, labels);
        BOOL forceTap = NO;
#ifdef FROZIO_HARNESS
        forceTap = [NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessForceTap"];   // iOS 17's path on iOS 26
#endif
        for (id element in forceTap ? @[] : found) {
            done = [element accessibilityActivate];
            FZLog("redesign: NaviMus control %@ activated=%d", describe(element), done);
            if (done) return;
        }
        // iOS 17 opens a SwiftUI menu only on a touch: tap it, as VoiceOver does when activation is refused.
        id element = found.firstObject;
        if (!element) return;
        CGPoint point = activationPointIn(window, element);
        if (!CGPointEqualToPoint(alignTo, CGPointZero) && fabs(point.y - alignTo.y) > 1) {
            // Under the finger: NaviMus's list scrolls so its control is where the rebuilt page's was tapped, so
            // the menu NaviMus opens is anchored there.
            UIScrollView *list = scrollViewOf(root, [root convertPoint:point fromView:window]);
            if (list) {
                // Past its own range if need be (a short album can't scroll): the list is hidden under the
                // rebuilt page, and it springs back the next time it's touched.
                CGFloat y = list.contentOffset.y + (point.y - alignTo.y);
                [list setContentOffset:CGPointMake(list.contentOffset.x, y) animated:NO];
                [list layoutIfNeeded];
                NSArray *again = candidates(collectAll(page), after, labels);
                if (again.firstObject) element = again.firstObject;
                point = activationPointIn(window, element);
            }
        }
        if (!CGRectContainsPoint(window.bounds, point)) {
            FZLogError("redesign: NaviMus control %@ is off screen at %@", describe(element), NSStringFromCGPoint(point));
            return;
        }
        done = FZRTap(window, point);
        FZLog("redesign: NaviMus control %@ tapped=%d at %@", describe(element), done, NSStringFromCGPoint(point));
    });
    if (done) return YES;
#ifdef FROZIO_DEBUG
    NSMutableArray *names = [NSMutableArray array];
    for (id element in elements) [names addObject:describe(element)];
    UINavigationBar *bar = page.navigationController.navigationBar;
    FZLog("redesign: none of %@%@ among NaviMus's %lu elements (bar alpha %.2f hidden %d items %lu+%lu): %@",
          [labels componentsJoinedByString:@"/"], after.length ? @" after the anchor" : @"", (unsigned long)elements.count,
          bar.alpha, bar.hidden, (unsigned long)bar.topItem.leftBarButtonItems.count, (unsigned long)bar.topItem.rightBarButtonItems.count,
          [names componentsJoinedByString:@", "]);
#endif
    return NO;
}

BOOL FZRActivateMenuItem(NSArray<NSString *> *labels) {
    NSMutableArray *elements = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) collect(window, 0, elements, seen);
    }
    for (NSString *wanted in labels) {
        for (id element in elements) {
            NSString *label = [element accessibilityLabel];
            if (![label isEqualToString:wanted] && ![label hasPrefix:[wanted stringByAppendingString:@" "]]) continue;
            BOOL done = [element accessibilityActivate];
            FZLog("redesign: menu item %@ activated=%d", describe(element), done);
            if (done) return YES;
        }
    }
#ifdef FROZIO_DEBUG
    NSMutableArray *names = [NSMutableArray array];
    for (id element in elements) [names addObject:describe(element)];
    FZLog("redesign: no menu item %@ among %@", [labels componentsJoinedByString:@"/"], [names componentsJoinedByString:@", "]);
#endif
    return NO;
}

BOOL FZRActivateNaviMusControl(UIViewController *page, NSString *after, NSArray<NSString *> *labels) {
    return FZRPressNaviMusControl(page, after, labels, CGPointZero);
}

#pragma mark - NaviMus's navigation bar under a rebuilt page

static IMP fz_origBarLayout;

// An empty mask: the bar draws nothing but stays a visible view. It keeps taking touches: NaviMus's own back
// and ⋯ sit where the rebuilt page draws its glass back and ⋯, so a tap there is a real tap on NaviMus's own
// (how the user's ⋯ worked on device, build 36).
static CALayer *emptyMask(void) {
    CALayer *mask = [CALayer layer];
    mask.frame = CGRectZero;
    return mask;
}

static void applyHidden(UINavigationBar *bar, BOOL hidden) {
    objc_setAssociatedObject(bar, &kBarHiddenKey, hidden ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    bar.layer.mask = hidden ? emptyMask() : nil;
}

// UIKit's and SwiftUI's own updates can't bring the bar back while a rebuilt page is on top.
static void fz_barLayout(UINavigationBar *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origBarLayout)(self, _cmd);
    if (objc_getAssociatedObject(self, &kBarHiddenKey) && !self.layer.mask) applyHidden(self, YES);
}

void FZRSetNaviMusBarHidden(UIViewController *page, BOOL hidden, id<UIViewControllerTransitionCoordinator> transition) {
    UINavigationBar *bar = page.navigationController.navigationBar;
    if (!bar) return;
    if (hidden) {
        applyHidden(bar, YES);   // gone from the start of the push, never drawn over the cover
        [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            if (context.isCancelled) applyHidden(bar, NO);
        }];
        return;
    }
    if (!transition) { applyHidden(bar, NO); return; }
    // Leaving: the bar fades in with the pop rather than appearing over the page as it slides away.
    applyHidden(bar, NO);
    bar.alpha = 0;
    [transition animateAlongsideTransition:^(id context) { bar.alpha = 1; }
                                completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        bar.alpha = 1;
        if (context.isCancelled) applyHidden(bar, YES);   // a cancelled swipe back leaves the rebuilt page on top
    }];
}

#pragma mark - pages

static IMP fz_origPush, fz_origSetControllers, fz_origLayout;

// A rebuilt page for the NaviMus page `vc` shows, or nil when the redesign doesn't rebuild it (yet).
static UIViewController *rebuiltPageFor(UIViewController *vc) {
    NSString *type = pageType(vc);
    if ([type hasSuffix:@".AlbumViewWrapper"]) {
        NSString *albumID = pageString(vc, @"albumID") ?: pageString(vc, @"album.id");
        if (!albumID.length) {
            FZLogError("redesign: album page without an album ID; NaviMus's page stays");
            return nil;
        }
        return [[FZRAlbumPage alloc] initWithAlbumID:albumID naviMusPage:vc];
    }
    return nil;
}

static void cover(UIViewController *vc) {
    if (objc_getAssociatedObject(vc, &kOverlayKey)) return;
    UIViewController *page = rebuiltPageFor(vc);
    if (!page) return;
    objc_setAssociatedObject(vc, &kOverlayKey, page, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [vc addChildViewController:page];
    page.view.frame = vc.view.bounds;
    page.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    objc_setAssociatedObject(page.view, &kOverlayKey, page, OBJC_ASSOCIATION_ASSIGN);
    [vc.view addSubview:page.view];
    [page didMoveToParentViewController:vc];
    FZLog("redesign: %@ laid over NaviMus's page", NSStringFromClass(page.class));
#ifdef FROZIO_DEBUG
    // The labels of NaviMus's own controls on the page, to wire the rebuilt page's buttons to them.
    __weak UIViewController *weakVC = vc;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakVC) FZRActivateNaviMusControl(weakVC, nil, @[@"\u2063frozio-probe-no-such-control"]);
    });
#endif
}

static void fz_pushViewController(UINavigationController *self, SEL _cmd, UIViewController *vc, BOOL animated) {
    @try {
        cover(vc);
    } @catch (NSException *e) {
        FZLogError("redesign: covering a page threw %@; NaviMus's page stays", e.name);
    }
    ((void (*)(id, SEL, id, BOOL))fz_origPush)(self, _cmd, vc, animated);
}

// SwiftUI's NavigationStack doesn't push: it sets the whole stack whenever its path changes.
static void fz_setViewControllers(UINavigationController *self, SEL _cmd, NSArray<UIViewController *> *controllers, BOOL animated) {
    @try {
        for (UIViewController *vc in controllers) cover(vc);
    } @catch (NSException *e) {
        FZLogError("redesign: covering a page threw %@; NaviMus's page stays", e.name);
    }
    ((void (*)(id, SEL, id, BOOL))fz_origSetControllers)(self, _cmd, controllers, animated);
}

// SwiftUI adds its own views to the hosting view as the page builds; the rebuilt page stays on top.
static void fz_viewDidLayoutSubviews(UIViewController *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origLayout)(self, _cmd);
    UIViewController *page = objc_getAssociatedObject(self, &kOverlayKey);
    if (page && page.view.superview == self.view && self.view.subviews.lastObject != page.view) {
        [self.view bringSubviewToFront:page.view];
    }
}

void FZRInstallPages(void) {
    if (!FZRRedesignActive()) return;
    BOOL push = FZHookInstanceMethod(UINavigationController.class, @selector(pushViewController:animated:), "v@:@B",
                                     (IMP)fz_pushViewController, &fz_origPush, "redesign.push");
    BOOL set = FZHookInstanceMethod(UINavigationController.class, @selector(setViewControllers:animated:), "v@:@B",
                                    (IMP)fz_setViewControllers, &fz_origSetControllers, "redesign.stack");
    BOOL layout = (push || set) && FZHookInstanceMethod(UIViewController.class, @selector(viewDidLayoutSubviews), "v@:",
                                               (IMP)fz_viewDidLayoutSubviews, &fz_origLayout, "redesign.layout");
    BOOL barLayout = FZHookInstanceMethod(UINavigationBar.class, @selector(layoutSubviews), "v@:", (IMP)fz_barLayout, &fz_origBarLayout, "redesign.bar.layout");
    if (!barLayout) FZLogError("redesign: NaviMus's bar may show through (layout hook missing)");
    FZLog("redesign: pages %@ (push=%d stack=%d layout=%d)", (push || set) && layout ? @"installed" : @"NOT installed", push, set, layout);
    (void)layout;
}
