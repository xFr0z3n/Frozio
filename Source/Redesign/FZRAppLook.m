#import <UIKit/UIKit.h>
#import "Redesign/FZRAppLook.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import "Prefs/FZSettings.h"

static BOOL sActive;
static IMP fz_origSetStyle;
static IMP fz_origSetControllerStyle;
static IMP fz_origBecomeKey;
static IMP fz_origSetBarTint;

BOOL FZRRedesignActive(void) {
    return sActive;
}

static BOOL glassBars(void) {
#ifdef FROZIO_HARNESS
    // The harness's only Simulator is iOS 26; this previews the pre-26 bars on it.
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessMaterialBars"]) return NO;
#endif
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

#pragma mark - dark

static void fz_setOverrideUserInterfaceStyle(UIWindow *self, SEL _cmd, UIUserInterfaceStyle style) {
    // The redesign is dark only (tokens: black field, white text); a request for light or for the
    // system's own style becomes dark.
    ((void (*)(id, SEL, UIUserInterfaceStyle))fz_origSetStyle)(self, _cmd, UIUserInterfaceStyleDark);
}

// SwiftUI applies preferredColorScheme (NaviMus's appearance setting) to the root UIHostingController,
// not to the window (seen in the harness: window dark, hosting controller override = light).
static void fz_setControllerStyle(UIViewController *self, SEL _cmd, UIUserInterfaceStyle style) {
    ((void (*)(id, SEL, UIUserInterfaceStyle))fz_origSetControllerStyle)(self, _cmd, UIUserInterfaceStyleDark);
}

static void fz_becomeKeyWindow(UIWindow *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origBecomeKey)(self, _cmd);
    if (self.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}

#pragma mark - bars

// The redesign's bars carry its accent. SwiftUI's .tint (NaviMus's tint) sets the tab bar's own tintColor,
// which beats the appearance proxy, so whatever is set becomes the accent.
static void fz_setTabBarTint(UITabBar *self, SEL _cmd, UIColor *tint) {
    ((void (*)(id, SEL, UIColor *))fz_origSetBarTint)(self, _cmd, FZRAccent());
}

static UITabBarAppearance *sTabLook;

UITabBarAppearance *FZRTabBarLook(void) { return sTabLook; }

static void styleTabBar(void) {
    UITabBar *proxy = [UITabBar appearance];
    proxy.tintColor = FZRAccent();
    proxy.unselectedItemTintColor = FZRSecondary();
    if (glassBars()) return; // the system's glass tab bar stays as it is

    UITabBarAppearance *look = [UITabBarAppearance new];
    [look configureWithDefaultBackground];
    look.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    look.backgroundColor = UIColor.clearColor;
    look.shadowColor = FZRHairline();
    for (UITabBarItemAppearance *item in @[look.stackedLayoutAppearance, look.inlineLayoutAppearance, look.compactInlineLayoutAppearance]) {
        item.normal.iconColor = FZRSecondary();
        item.normal.titleTextAttributes = @{NSForegroundColorAttributeName: FZRSecondary()};
        item.selected.iconColor = FZRAccent();
        item.selected.titleTextAttributes = @{NSForegroundColorAttributeName: FZRAccent()};
    }
    proxy.standardAppearance = look;
    proxy.scrollEdgeAppearance = look;
    sTabLook = look;
}

static void styleNavigationBar(void) {
    UINavigationBar *proxy = [UINavigationBar appearance];
    proxy.tintColor = FZRAccent();
    if (glassBars()) return; // the system's glass navigation bar stays as it is

    NSDictionary *title = @{NSForegroundColorAttributeName: FZRPrimary(),
                            NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]};
    NSDictionary *largeTitle = @{NSForegroundColorAttributeName: FZRPrimary(),
                                 NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]};
    // Scrolled: the glass fallback behind the bar. At the top: nothing, the large title on black.
    UINavigationBarAppearance *scrolled = [UINavigationBarAppearance new];
    [scrolled configureWithDefaultBackground];
    scrolled.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    scrolled.backgroundColor = UIColor.clearColor;
    scrolled.shadowColor = FZRHairline();
    scrolled.titleTextAttributes = title;
    scrolled.largeTitleTextAttributes = largeTitle;
    UINavigationBarAppearance *top = [UINavigationBarAppearance new];
    [top configureWithTransparentBackground];
    top.titleTextAttributes = title;
    top.largeTitleTextAttributes = largeTitle;
    proxy.standardAppearance = scrolled;
    proxy.compactAppearance = scrolled;
    proxy.scrollEdgeAppearance = top;
    proxy.compactScrollEdgeAppearance = top;
}

void FZRInstallAppLook(void) {
    if (![[FZSettings defaults] boolForKey:FZSettingsKeyRedesign]) {
        FZLog("redesign: off");
        return;
    }
    BOOL style = FZHookInstanceMethodNamed(@"UIWindow", @"setOverrideUserInterfaceStyle:", "v@:q",
                                           (IMP)fz_setOverrideUserInterfaceStyle, &fz_origSetStyle, "redesign.dark");
    BOOL controller = FZHookInstanceMethodNamed(@"UIViewController", @"setOverrideUserInterfaceStyle:", "v@:q",
                                                (IMP)fz_setControllerStyle, &fz_origSetControllerStyle, "redesign.dark.controller");
    BOOL key = FZHookInstanceMethodNamed(@"UIWindow", @"becomeKeyWindow", "v@:",
                                         (IMP)fz_becomeKeyWindow, &fz_origBecomeKey, "redesign.key");
    BOOL tint = FZHookInstanceMethodNamed(@"UITabBar", @"setTintColor:", "v@:@",
                                          (IMP)fz_setTabBarTint, &fz_origSetBarTint, "redesign.tabbar.tint");
    styleTabBar();
    styleNavigationBar();
    sActive = YES;
    (void)style; (void)controller; (void)key; (void)tint; // release builds compile FZLog out
    FZLog("redesign: on (dark=%d/%d key=%d tint=%d, %@ bars)", style, controller, key, tint, glassBars() ? @"system glass" : @"material");
}
