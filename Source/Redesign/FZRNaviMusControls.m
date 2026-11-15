#import <objc/message.h>
#import <objc/runtime.h>
#import "Redesign/FZRNaviMusControls.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Album/FZRAlbumPage.h"
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

// The element to activate: with an anchor, the first match after the element labelled `after` (NaviMus labels a
// row "<title>", its download ring, then "More"), else the first match; buttons before plain elements.
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
    NSMutableArray *buttons = [NSMutableArray array], *others = [NSMutableArray array];
    for (NSString *wanted in labels) {
        for (NSUInteger i = start; i < elements.count; i++) {
            id element = elements[i];
            if ([[element accessibilityLabel] caseInsensitiveCompare:wanted] != NSOrderedSame) continue;
            [([element accessibilityTraits] & UIAccessibilityTraitButton ? buttons : others) addObject:element];
            if (after.length) break;   // a row's own control or none: never the next row's
        }
    }
    return [buttons arrayByAddingObjectsFromArray:others];
}

BOOL FZRActivateNaviMusControl(UIViewController *page, NSString *after, NSArray<NSString *> *labels) {
    UIView *root = page.view;
    if (!root) return NO;
    UIView *cover = nil;
    for (UIView *sub in root.subviews) if (objc_getAssociatedObject(sub, &kOverlayKey)) cover = sub;
    __block BOOL done = NO;
    NSMutableArray *elements = [NSMutableArray array];
    // Found and activated in one go: shown and hidden again in between, SwiftUI rebuilds its accessibility
    // nodes and the ones found first no longer activate (device log, build 35).
    withNaviMusShown(page, cover, ^{
        NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        collect(root, 0, elements, seen);
        UINavigationBar *bar = page.navigationController.navigationBar;
        if (bar) collect(bar, 0, elements, seen);
        for (id element in candidates(elements, after, labels)) {
            done = [element accessibilityActivate];
            FZLog("redesign: NaviMus control %@ activated=%d", describe(element), done);
            if (done) break;
        }
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

#pragma mark - NaviMus's navigation bar under a rebuilt page

static IMP fz_origBarLayout;

// An empty mask: the bar draws nothing but stays a visible view, so iOS 17 still lists and activates its items
// (an alpha of 0 took them out of accessibility, device log build 35). It takes no touches meanwhile, so the
// rebuilt page's own buttons under it get them.
static CALayer *emptyMask(void) {
    CALayer *mask = [CALayer layer];
    mask.frame = CGRectZero;
    return mask;
}

static void applyHidden(UINavigationBar *bar, BOOL hidden) {
    objc_setAssociatedObject(bar, &kBarHiddenKey, hidden ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    bar.layer.mask = hidden ? emptyMask() : nil;
    bar.userInteractionEnabled = !hidden;
}

// UIKit's and SwiftUI's own updates can't bring the bar back while a rebuilt page is on top.
static void fz_barLayout(UINavigationBar *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origBarLayout)(self, _cmd);
    if (objc_getAssociatedObject(self, &kBarHiddenKey) && (!self.layer.mask || self.userInteractionEnabled)) applyHidden(self, YES);
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
