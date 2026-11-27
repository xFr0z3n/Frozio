// FZRTabReset: a tap on a tab opens that tab's first page (the user's wish, build 57: "clicking home or the others
// should send you to its default page"), whether it was already selected or not. NaviMus's tabs are SwiftUI
// NavigationStacks on UIKit navigation controllers; popping the UIKit stack updates SwiftUI's path as a back swipe
// does. Only real taps on the tab bar (-tabBar:didSelectItem:, which UIKit sends for those alone) are acted on.
#import <UIKit/UIKit.h>
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import "Prefs/FZSettings.h"
#import "Redesign/Player/FZRPlayer.h"

NSString *const FZRKeyTabsFirstPage = @"fz.redesign.tabsFirstPage";
static IMP fz_origDidSelect;

static UINavigationController *navigationIn(UIViewController *vc) {
    if ([vc isKindOfClass:UINavigationController.class]) return (UINavigationController *)vc;
    for (UIViewController *child in vc.childViewControllers) {
        UINavigationController *found = navigationIn(child);
        if (found) return found;
    }
    return nil;
}

static void fz_didSelect(UITabBarController *self, SEL _cmd, UITabBar *bar, UITabBarItem *item) {
    ((void (*)(id, SEL, id, id))fz_origDidSelect)(self, _cmd, bar, item);
    if (![[FZSettings defaults] boolForKey:FZRKeyTabsFirstPage]) return;
    UINavigationController *nav = navigationIn(self.selectedViewController);
    if (nav.viewControllers.count > 1) {
        FZLog("tabs: %@ back to its first page (%lu deep)", item.title, (unsigned long)nav.viewControllers.count);
        [nav popToRootViewControllerAnimated:NO];
    }
    FZRCloseStrayNaviMusPlayerSoon(self);
}

void FZRInstallTabReset(void) {
    FZHookInstanceMethod(UITabBarController.class, @selector(tabBar:didSelectItem:), "v@:@@", (IMP)fz_didSelect,
                         &fz_origDidSelect, "redesign.tabs.didSelect");
    // Back in the app: NaviMus may bring its own player back up under Frozio's.
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UITabBarController *tabs = FZRPlayerTabs();
        if (tabs) FZRCloseStrayNaviMusPlayerSoon(tabs);
    }];
}
