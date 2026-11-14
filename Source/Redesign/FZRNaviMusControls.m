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

static NSArray *accessibilityChildren(id element) {
    NSArray *children = [element respondsToSelector:@selector(accessibilityElements)] ? [element accessibilityElements] : nil;
    if (children.count) return children;
    NSMutableArray *list = [NSMutableArray array];
    NSInteger count = [element respondsToSelector:@selector(accessibilityElementCount)] ? [element accessibilityElementCount] : 0;
    for (NSInteger i = 0; i < count && i < 500; i++) {
        id child = [element accessibilityElementAtIndex:i];
        if (child) [list addObject:child];
    }
    if (!list.count && [element isKindOfClass:UIView.class]) [list addObjectsFromArray:((UIView *)element).subviews];
    return list;
}

static void collect(id element, NSUInteger depth, NSMutableArray *found) {
    if (!element || depth > 40 || found.count > 400) return;
    if ([element isAccessibilityElement]) [found addObject:element];
    for (id child in accessibilityChildren(element)) collect(child, depth + 1, found);
}

static char kOverlayKey;

// NaviMus's page as it really is for an instant: the rebuilt page over it out of the way and its navigation
// bar (whose drawing the rebuilt page hides) back. SwiftUI and UIKit only search and activate controls that
// are reachable; no frame is drawn in between, so it never shows.
static void withNaviMusShown(UIViewController *page, UIView *cover, void (^work)(void)) {
    UINavigationBar *bar = page.navigationController.navigationBar;
    BOOL coverWasHidden = cover.hidden;
    CGFloat barAlpha = bar.alpha;
    cover.hidden = YES;
    bar.alpha = 1;
    @try {
        work();
    } @finally {
        cover.hidden = coverWasHidden;
        bar.alpha = barAlpha;
    }
}

BOOL FZRActivateNaviMusControl(UIViewController *page, NSArray<NSString *> *labels) {
    UIView *root = page.view;
    if (!root) return NO;
    UIView *cover = nil;
    for (UIView *sub in root.subviews) if (objc_getAssociatedObject(sub, &kOverlayKey)) cover = sub;
    NSMutableArray *elements = [NSMutableArray array];
    withNaviMusShown(page, cover, ^{
        collect(root, 0, elements);
        if (page.navigationController.navigationBar) collect(page.navigationController.navigationBar, 0, elements);
    });
    for (NSString *wanted in labels) {
        for (id element in elements) {
            NSString *label = [element accessibilityLabel];
            if (!label || [label caseInsensitiveCompare:wanted] != NSOrderedSame) continue;
            __block BOOL done = NO;
            withNaviMusShown(page, cover, ^{ done = [element accessibilityActivate]; });
            FZLog("redesign: NaviMus control \"%@\" activated=%d", label, done);
            if (done) return YES;
        }
    }
#ifdef FROZIO_DEBUG
    NSMutableArray *names = [NSMutableArray array];
    for (id element in elements) {
        NSString *label = [element accessibilityLabel];
        if (label.length) [names addObject:[NSString stringWithFormat:@"\"%@\"%@", label,
            ([element accessibilityTraits] & UIAccessibilityTraitButton) ? @" (button)" : @""]];
    }
    FZLog("redesign: none of %@ among NaviMus's %lu elements: %@", [labels componentsJoinedByString:@"/"],
          (unsigned long)elements.count, [names componentsJoinedByString:@", "]);
#endif
    return NO;
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
        if (weakVC) FZRActivateNaviMusControl(weakVC, @[@"\u2063frozio-probe-no-such-control"]);
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
    FZLog("redesign: pages %@ (push=%d stack=%d layout=%d)", (push || set) && layout ? @"installed" : @"NOT installed", push, set, layout);
    (void)layout;
}
