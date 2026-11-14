#import "FZScreenCensus.h"
#import "Core/FZLog.h"

#ifdef FROZIO_DEBUG
#import <UIKit/UIKit.h>
#import "Core/FZHook.h"
#import <objc/message.h>

static IMP fz_origViewDidAppear;

static NSString *FZShort(id obj) {
    if (!obj) return @"-";
    NSString *s = NSStringFromClass([obj class]);
    return s.length > 160 ? [[s substringToIndex:160] stringByAppendingString:@"…"] : s;
}

static NSString *FZSuperChain(Class c) {
    NSMutableArray *a = [NSMutableArray array];
    for (Class k = class_getSuperclass(c); k && k != UIViewController.class && a.count < 6; k = class_getSuperclass(k)) {
        [a addObject:NSStringFromClass(k)];
    }
    return [a componentsJoinedByString:@" > "];
}

static void FZDumpTree(UIViewController *vc, NSUInteger depth, NSMutableString *out) {
    if (!vc || depth > 12) return;
    [out appendFormat:@"\n%@%@ title=%@", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
                      FZShort(vc), vc.title ?: vc.navigationItem.title ?: @"-"];
    for (UIViewController *child in vc.childViewControllers) FZDumpTree(child, depth + 1, out);
    if (vc.presentedViewController && vc.presentedViewController.presentingViewController == vc) {
        [out appendFormat:@"\n%@(presents)", [@"" stringByPaddingToLength:(depth + 1) * 2 withString:@" " startingAtIndex:0]];
        FZDumpTree(vc.presentedViewController, depth + 2, out);
    }
}

static void FZLogTabBar(UIViewController *root) {
    UITabBarController *tbc = nil;
    for (UIViewController *v = root; v; v = v.childViewControllers.firstObject) {
        if ([v isKindOfClass:UITabBarController.class]) { tbc = (UITabBarController *)v; break; }
    }
    if (!tbc) { FZLog("census: no UITabBarController under %@", FZShort(root)); return; }
    NSMutableArray *items = [NSMutableArray array];
    [tbc.viewControllers enumerateObjectsUsingBlock:^(UIViewController *c, NSUInteger i, BOOL *stop) {
        [items addObject:[NSString stringWithFormat:@"%lu:%@ <%@>", (unsigned long)i, c.tabBarItem.title ?: @"-", FZShort(c)]];
    }];
    FZLog("census: tab bar %@ tabs=[%@] selected=%lu", FZShort(tbc), [items componentsJoinedByString:@", "],
          (unsigned long)tbc.selectedIndex);
}

// FZProbe.swift, called by name so this file needs no generated Swift header.
static NSString *FZProbeCall(NSString *selector, UIViewController *vc) {
    Class probe = NSClassFromString(@"FZProbe");
    SEL sel = NSSelectorFromString(selector);
    if (![probe respondsToSelector:sel]) return nil;
    return ((NSString *(*)(id, SEL, id))objc_msgSend)(probe, sel, vc);
}

// Views overlapping the bottom of the tab bar controller (tab bar, mini player) and the views of a
// navigation bar (bar buttons): class, frame and depth, for placing the redesign's own bar and buttons.
static void FZDumpViews(UIView *view, UIView *root, NSUInteger depth, CGFloat minY, NSMutableString *out, NSUInteger *lines) {
    if (!view || depth > 9 || *lines > 120) return;
    CGRect frame = [view convertRect:view.bounds toView:root];
    if (CGRectGetMaxY(frame) >= minY && !view.hidden && view.alpha > 0.01) {
        [out appendFormat:@"\n%@%@ %@%@", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], FZShort(view),
                          NSStringFromCGRect(frame), view.userInteractionEnabled ? @"" : @" (no touch)"];
        (*lines)++;
    }
    for (UIView *sub in view.subviews) FZDumpViews(sub, root, depth + 1, minY, out, lines);
}

static void FZLogLayout(UITabBarController *tbc) {
    UIView *root = tbc.view;
    NSMutableString *bottom = [NSMutableString string];
    NSUInteger lines = 0;
    FZDumpViews(root, root, 0, CGRectGetHeight(root.bounds) - 220, bottom, &lines);
    FZLog("probe: bottom 220 pt of the tab bar controller:%@", bottom);
    UINavigationController *nav = [tbc.selectedViewController isKindOfClass:UINavigationController.class]
        ? (UINavigationController *)tbc.selectedViewController
        : tbc.selectedViewController.childViewControllers.firstObject.navigationController;
    if (nav) {
        NSMutableString *bar = [NSMutableString string];
        lines = 0;
        FZDumpViews(nav.navigationBar, nav.navigationBar, 0, -1000, bar, &lines);
        FZLog("probe: navigation bar of %@:%@", FZShort(nav), bar);
    }
}

static void fz_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))fz_origViewDidAppear)(self, _cmd, animated);
    @try {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            UIWindow *w = self.view.window;
            NSMutableString *tree = [NSMutableString string];
            FZDumpTree(w.rootViewController, 0, tree);
            FZLog("census: window %@ root tree:%@", FZShort(w), tree);
            FZLogTabBar(w.rootViewController);
        });
        if ([self isKindOfClass:UITabBarController.class]) {
            static dispatch_once_t tabOnce;
            dispatch_once(&tabOnce, ^{ FZLogTabBar(self); });
            // Once the mini player has had time to appear.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                FZLogLayout((UITabBarController *)self);
            });
            static dispatch_once_t intentsOnce;
            dispatch_once(&intentsOnce, ^{
                Class probe = NSClassFromString(@"FZProbe");
                if ([probe respondsToSelector:NSSelectorFromString(@"intentSummary")]) {
                    FZLog("probe: intents\n%@", ((NSString *(*)(id, SEL))objc_msgSend)(probe, NSSelectorFromString(@"intentSummary")));
                }
            });
        }
        NSString *rootType = FZProbeCall(@"rootViewType:", self);
        if (rootType) {
            FZLog("probe: page %@ title=%@ depth=%lu root=%@ fields [%@]", FZShort(self), self.navigationItem.title ?: @"-",
                  (unsigned long)self.navigationController.viewControllers.count, rootType, FZProbeCall(@"rootViewFields:", self) ?: @"");
        }
        UINavigationController *nav = self.navigationController;
        FZLog("census: appear %@ | super %@ | title=%@ nav=%@ depth=%lu parent=%@ presenting=%@",
              FZShort(self), FZSuperChain(self.class),
              self.title ?: self.navigationItem.title ?: @"-",
              FZShort(nav), (unsigned long)nav.viewControllers.count,
              FZShort(self.parentViewController), FZShort(self.presentingViewController));
    } @catch (NSException *e) {
        FZLogError("census: exception %@", e);
    }
}

void FZInstallScreenCensus(void) {
    FZHookInstanceMethod(UIViewController.class, @selector(viewDidAppear:), "v@:B",
                         (IMP)fz_viewDidAppear, &fz_origViewDidAppear, "census.viewDidAppear");
}
#else
void FZInstallScreenCensus(void) {}
#endif
