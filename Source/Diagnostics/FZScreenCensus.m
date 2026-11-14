#import "FZScreenCensus.h"
#import "Core/FZLog.h"

#ifdef FROZIO_DEBUG
#import <UIKit/UIKit.h>
#import "Core/FZHook.h"

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
