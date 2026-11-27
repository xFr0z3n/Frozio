// FZRTabReset: a second tap on the tab already shown opens its first page; another tab keeps its place (the user's wish, build 57: "clicking home or the others
// should send you to its default page"), whether it was already selected or not. NaviMus's tabs are SwiftUI
// NavigationStacks on UIKit navigation controllers; popping the UIKit stack updates SwiftUI's path as a back swipe
// does. Only real taps on the tab bar (UIKit's -_tabBarItemClicked:, sent for those alone) are acted on.
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

static void fz_didSelect(UITabBarController *self, SEL _cmd, id sender) {
    UIViewController *before = self.selectedViewController;
    ((void (*)(id, SEL, id))fz_origDidSelect)(self, _cmd, sender);
    UITabBarItem *item = self.selectedViewController.tabBarItem;
    FZRCloseStrayNaviMusPlayerSoon(self);
    // Another tab keeps the page and place it was left on (the user, build 73: "windows should save when switching
    // tabs, only not on app restart"); a tap on the tab already shown goes to its first page, as iOS does.
    if (self.selectedViewController != before) return;
    if (![[FZSettings defaults] boolForKey:FZRKeyTabsFirstPage]) return;
    UINavigationController *nav = navigationIn(self.selectedViewController);
    if (nav.viewControllers.count > 1) {
        FZLog("tabs: %@ back to its first page (%lu deep)", item.title, (unsigned long)nav.viewControllers.count);
        [nav popToRootViewControllerAnimated:YES];
    }
}

void FZRInstallTabReset(void) {
    // UIKit's handler for a tap on a tab (iOS 17: -tabBar:didSelectItem: isn't sent to the controller).
    BOOL ok = FZHookInstanceMethod(UITabBarController.class, NSSelectorFromString(@"_tabBarItemClicked:"), "v@:@", (IMP)fz_didSelect,
                                   &fz_origDidSelect, "redesign.tabs.clicked");
    FZLog("tabs: first-page hook %@", ok ? @"installed" : @"NOT installed");
    // Back in the app: NaviMus may bring its own player back up under Frozio's.
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UITabBarController *tabs = FZRPlayerTabs();
        if (tabs) FZRCloseStrayNaviMusPlayerSoon(tabs);
    }];
}
