// FZRSnappy: "Snappy" in Frozio settings → Appearance (the user's request, build 73: "remove all animation and do
// everything instantly"). Every window's layer runs its animations 1000× faster, so UIKit's, SwiftUI's and Frozio's
// own transitions finish within a frame: pages, sheets, menus, the player. Video and audio aren't timed by layers and
// play as they are.
#import <UIKit/UIKit.h>
#import "Core/FZLog.h"
#import "Prefs/FZSettings.h"

NSString *const FZKeySnappy = @"fz.snappy";

static void apply(void) {
    BOOL snappy = [[FZSettings defaults] boolForKey:FZKeySnappy];
    float speed = snappy ? 1000 : 1;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.layer.speed != speed) window.layer.speed = speed;
        }
    }
}

void FZInstallSnappy(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIWindowDidBecomeVisibleNotification, UISceneDidActivateNotification, NSUserDefaultsDidChangeNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { apply(); }];
    }
    FZLog("snappy: %@", [[FZSettings defaults] boolForKey:FZKeySnappy] ? @"on" : @"off");
}
