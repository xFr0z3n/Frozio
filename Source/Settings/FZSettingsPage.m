#import "FZSettingsPage.h"
#import "Settings/Kit/FZModPage.h"
#import "Settings/Kit/FZPageStyle.h"
#import "Settings/Kit/FZKitCore.h"
#import "Prefs/FZSettings.h"

UIImage *FZLogoImage(void) {
    static UIImage *logo;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frozio.bundle/logo.png"];
        logo = [UIImage imageWithContentsOfFile:path];
        if (!logo) FZLogError("settings: logo not found at %@", path);
    });
    return logo;
}

#pragma mark - app icon

static NSString *const kAltIconWhite = @"White"; // CFBundleAlternateIcons key written by scripts/patch_icons.py
static NSNotificationName const FZAppIconDidChange = @"FZAppIconDidChange";

// What iOS shows right now is the source of truth (not a stored preference).
static NSString *FZShownIcon(void) {
    return [UIApplication.sharedApplication.alternateIconName isEqualToString:kAltIconWhite] ? @"White" : @"Cyan";
}

static void FZShowAlert(NSString *title, NSString *message) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [FZTopController() presentViewController:a animated:YES completion:nil];
}

static void FZApplyAppIcon(NSInteger index) {
    UIApplication *app = UIApplication.sharedApplication;
    NSString *name = index == 1 ? kAltIconWhite : nil;
    FZLog("app icon: requested %@ (supports=%d, current=%@)", name ?: @"<primary>", app.supportsAlternateIcons, app.alternateIconName ?: @"<primary>");
    if (!app.supportsAlternateIcons) {
        FZShowAlert(@"Icons unavailable",
                    @"This build has no alternate icons registered (CFBundleAlternateIcons). Your signer may have rewritten Info.plist.");
        return;
    }
    NSString *current = app.alternateIconName;
    if ((current == nil && name == nil) || [current isEqualToString:name]) return;
    // iOS rejects icon changes while a presentation is still animating; the menu that picked the
    // icon is dismissing right now, so wait for it to finish.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [app setAlternateIconName:name completionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    FZLogError("app icon: setAlternateIconName(%@) failed: %@", name ?: @"<primary>", error);
                    FZShowAlert(@"Couldn't change the icon",
                                [NSString stringWithFormat:@"%@ (%@ %ld)", error.localizedDescription, error.domain, (long)error.code]);
                } else {
                    FZSetInt(FZSettingsKeyAppIcon, index);
                    FZLog("app icon: now %@", name ?: @"cyan (primary)");
                }
                [NSNotificationCenter.defaultCenter postNotificationName:FZAppIconDidChange object:nil];
            });
        }];
    });
}

#pragma mark - diagnostics (debug builds)

#ifdef FROZIO_DEBUG
static void FZShareLog(void) {
    NSString *path = FZLogFilePath();
    if (!path || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        FZShowAlert(@"No log yet", path ?: @"Documents is unavailable.");
        return;
    }
    NSMutableArray *items = [NSMutableArray arrayWithObject:[NSURL fileURLWithPath:path]];
    NSString *old = [path stringByAppendingString:@".1"];
    if ([NSFileManager.defaultManager fileExistsAtPath:old]) [items addObject:[NSURL fileURLWithPath:old]];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    UIViewController *host = FZTopController();
    share.popoverPresentationController.sourceView = host.view;
    share.popoverPresentationController.sourceRect = (CGRect){CGPointMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds)), CGSizeZero};
    [host presentViewController:share animated:YES completion:nil];
}

static void FZClearLog(void) {
    NSString *path = FZLogFilePath();
    if (!path) return;
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    [NSFileManager.defaultManager removeItemAtPath:[path stringByAppendingString:@".1"] error:nil];
    FZLog("log cleared by user");
    FZShowAlert(@"Log cleared", @"New lines start now.");
}

static NSString *FZLogSize(void) {
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:FZLogFilePath() error:nil];
    return attrs ? [NSByteCountFormatter stringFromByteCount:(long long)attrs.fileSize countStyle:NSByteCountFormatterCountStyleFile] : @"empty";
}
#endif

#pragma mark - page

@interface FZSettingsRootPage : FZModPage
@end

@implementation FZSettingsRootPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableHeaderView = [self makeHeader];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)done {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

// Logo, name and version, centred over the first card.
- (UIView *)makeHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 168)];
    UIImageView *logo = [[UIImageView alloc] initWithImage:FZLogoImage()];
    logo.contentMode = UIViewContentModeScaleAspectFit;
    logo.layer.cornerRadius = 20;
    logo.layer.cornerCurve = kCACornerCurveContinuous;
    logo.clipsToBounds = YES;
    logo.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *name = [UILabel new];
    name.text = @"Frozio";
    name.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    name.textColor = UIColor.whiteColor;

    UILabel *version = [UILabel new];
#ifdef FROZIO_DEBUG
    NSString *kind = @"debug";
#else
    NSString *kind = @"release";
#endif
    version.text = [NSString stringWithFormat:@"v%s %@ · NaviMus %@", FROZIO_VERSION, kind,
                    NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"?"];
    version.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    version.textColor = [UIColor colorWithWhite:1 alpha:0.65];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[logo, name, version]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 6;
    [stack setCustomSpacing:12 afterView:logo];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [logo.widthAnchor constraintEqualToConstant:84],
        [logo.heightAnchor constraintEqualToConstant:84],
        [stack.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];
    return header;
}

@end

UIViewController *FZMakeSettingsPage(void) {
    FZModRow *icon = FZMenuRow(@"App icon", @[@"Cyan", @"White"], ^NSString *{ return FZShownIcon(); },
                               ^(NSInteger index) { FZApplyAppIcon(index); });
    icon.subtitle = @"Cyan is Frozio's icon, White a monochrome one. iOS confirms a change with a short alert.";
    icon.symbol = @"app.badge";
    icon.refreshOn = FZAppIconDidChange;

    FZModRow *guard = FZSwitchRow(@"Keep library on this iPhone",
                                  @"Stops iCloud sync of NaviMus's library cache, as in the App Store build. "
                                  @"Turning it off can crash a re-signed app once a server is added.",
                                  FZSettingsKeyCloudKitGuard);
    guard.symbol = @"externaldrive.badge.icloud";
    guard.info = @"Re-signed apps often get iCloud containers without push notifications. SwiftData then tries "
                 @"to sync through CloudKit, and CloudKit aborts the app.";

    FZModRow *repo = FZLinkRow(@"Frozio on GitHub", @"Source, builds and issues.", FZRepoURL);
    repo.symbol = @"chevron.left.forwardslash.chevron.right";

    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        FZSection(@"Appearance", @[icon]),
        FZNotedSection(@"Fixes", @[guard], FZRestartNote),
    ]];
#ifdef FROZIO_DEBUG
    FZModRow *share = FZStatActionRow(@"Share log", @"Send frozio.log with AirDrop, Mail, Messages or Save to Files.",
                                      ^NSString *{ return FZLogSize(); }, ^{ FZShareLog(); });
    share.symbol = @"square.and.arrow.up";
    FZModRow *clear = FZActionRow(@"Clear log", @"Start a fresh log before reproducing a problem.", ^{ FZClearLog(); });
    clear.symbol = @"trash";
    [sections addObject:FZNotedSection(@"Diagnostics", @[share, clear], @"Debug build: Frozio writes everything it does to this log.")];
#endif
    [sections addObject:FZSection(@"About", @[repo])];
    return [[FZSettingsRootPage alloc] initWithTitle:@"Frozio" intro:nil sections:sections footer:nil];
}

void FZPresentSettings(UIViewController *owner) {
    if (!owner) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:FZMakeSettingsPage()];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}
