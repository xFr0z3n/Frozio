// FrozioHarness: a Simulator-only host app for Frozio's UI (settings pages, redesign kit).
//
// NaviMus is an arm64 device binary, so it can't run in the Simulator on this Mac. The harness
// compiles Frozio's own sources for the Simulator and stands in for NaviMus's Settings tab: a
// dark navigation stack titled "Settings", with the Frozio entry button top-right as on device.
// Frozio.m (the constructor and version gate) is not linked, so no hook is ever installed here.
//
// Launch argument -FZHarnessOpenSettings YES (the default for `make run`) opens Frozio settings
// straight away, so a rebuild lands on the page being worked on.
#import <UIKit/UIKit.h>
#import "Prefs/FZSettings.h"
#import "Settings/FZSettingsPage.h"
#import "Settings/Kit/FZPage.h"

@interface FZHarnessSettingsStandIn : UIViewController
@end

@implementation FZHarnessSettingsStandIn
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:FZLogoImage() ?: [UIImage systemImageNamed:@"snowflake"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openFrozio)];

    UILabel *note = [UILabel new];
    note.translatesAutoresizingMaskIntoConstraints = NO;
    note.numberOfLines = 0;
    note.textAlignment = NSTextAlignmentCenter;
    note.textColor = UIColor.secondaryLabelColor;
    note.text = @"Stand-in for NaviMus's Settings tab.\nTap the Frozio button top-right.";
    [self.view addSubview:note];
    [NSLayoutConstraint activateConstraints:@[
        [note.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [note.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [note.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-48],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    static BOOL opened;
    if (!opened && [NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessOpenSettings"]) {
        opened = YES;
        [self openFrozio];
    }
}

- (void)openFrozio {
    FZPresentSettings(self);
}
@end

@interface FZHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation FZHarnessDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    // Same order as Frozio.m, minus the version gate and every NaviMus hook.
    [FZSettings registerDefaults];
    FZRegisterPages();

    UITabBarController *tabs = [UITabBarController new];
    UINavigationController *settings =
        [[UINavigationController alloc] initWithRootViewController:[FZHarnessSettingsStandIn new]];
    settings.navigationBar.prefersLargeTitles = YES;
    settings.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
                                                        image:[UIImage systemImageNamed:@"gear"]
                                                          tag:0];
    tabs.viewControllers = @[settings];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(FZHarnessDelegate.class));
    }
}
