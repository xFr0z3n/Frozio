#import "FZSettingsEntry.h"
#import "FZSettingsPage.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import <UIKit/UIKit.h>

static NSString *const kHostClass = @"_TtGC7SwiftUI32NavigationStackHostingControllerVS_7AnyView_";
static NSString *const kNavClass  = @"SwiftUI.UIKitNavigationController";
static NSString *const kTabClass  = @"SwiftUI.UIKitTabBarController";
static NSString *const kEntryId   = @"fz.settings.entry";

static IMP fz_origViewDidAppear;

@interface FZEntryTarget : NSObject
+ (instancetype)shared;
@end

@implementation FZEntryTarget
+ (instancetype)shared {
    static FZEntryTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [FZEntryTarget new]; });
    return t;
}
- (void)open:(UIBarButtonItem *)sender {
    UIViewController *top = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) top = w.rootViewController;
    }
    while (top.presentedViewController) top = top.presentedViewController;
    FZLog("settings entry: open from %@", NSStringFromClass(top.class));
    FZPresentSettings(top);
}
@end

// Generic SwiftUI specializations are instantiated lazily, so classes are matched by runtime name
// (exact for the host, superclass chain for the containers) instead of being looked up at load time.
static BOOL FZClassChainHasName(Class c, NSString *name) {
    for (; c; c = class_getSuperclass(c)) if ([NSStringFromClass(c) isEqualToString:name]) return YES;
    return NO;
}

static BOOL FZIsNaviMusSettingsRoot(UIViewController *vc) {
    if (![NSStringFromClass(vc.class) isEqualToString:kHostClass]) return NO;
    UINavigationController *nav = vc.navigationController;
    if (!nav || !FZClassChainHasName(nav.class, kNavClass) || nav.viewControllers.firstObject != vc) return NO;
    BOOL inTabs = NO;
    for (UIViewController *p = nav.parentViewController; p; p = p.parentViewController) {
        if (FZClassChainHasName(p.class, kTabClass)) { inTabs = YES; break; }
    }
    return inTabs && [vc.navigationItem.title isEqualToString:@"Settings"];
}

static UIImage *FZEntryImage(void) {
    UIImage *logo = FZLogoImage();
    if (!logo) return [UIImage systemImageNamed:@"snowflake"];
    CGSize size = CGSizeMake(28, 28);
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 28, 28) cornerRadius:7] addClip];
        [logo drawInRect:CGRectMake(0, 0, 28, 28)];
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static void FZEnsureEntry(UIViewController *vc) {
    NSArray<UIBarButtonItem *> *items = vc.navigationItem.rightBarButtonItems ?: @[];
    for (UIBarButtonItem *i in items) if ([i.accessibilityIdentifier isEqualToString:kEntryId]) return;
    UIBarButtonItem *entry = [[UIBarButtonItem alloc] initWithImage:FZEntryImage()
                                                              style:UIBarButtonItemStylePlain
                                                             target:[FZEntryTarget shared]
                                                             action:@selector(open:)];
    entry.accessibilityIdentifier = kEntryId;
    entry.accessibilityLabel = @"Frozio settings";
    vc.navigationItem.rightBarButtonItems = [items arrayByAddingObject:entry];
    FZLog("settings entry: added to NaviMus Settings (%lu existing items)", (unsigned long)items.count);
}

static void fz_entryViewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))fz_origViewDidAppear)(self, _cmd, animated);
    @try {
        if (FZIsNaviMusSettingsRoot(self)) FZEnsureEntry(self);
    } @catch (NSException *e) {
        FZLogError("settings entry: %@", e); // never take NaviMus down
    }
}

void FZInstallSettingsEntry(void) {
    FZHookInstanceMethod(UIViewController.class, @selector(viewDidAppear:), "v@:B",
                         (IMP)fz_entryViewDidAppear, &fz_origViewDidAppear, "settings-entry.viewDidAppear");
}
