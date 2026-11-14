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

static void FZApplyAppIcon(NSInteger index) {
    UIApplication *app = UIApplication.sharedApplication;
    if (!app.supportsAlternateIcons) {
        FZLogError("app icon: alternate icons not supported (CFBundleAlternateIcons missing?)");
        return;
    }
    NSString *name = index == 1 ? kAltIconWhite : nil;
    NSString *current = app.alternateIconName;
    if ((current == nil && name == nil) || [current isEqualToString:name]) return;
    [app setAlternateIconName:name completionHandler:^(NSError *error) {
        if (error) FZLogError("app icon: setAlternateIconName(%@) failed: %@", name ?: @"<primary>", error);
        else FZLog("app icon: now %@", name ?: @"cyan (primary)");
    }];
}

// The stored choice follows what iOS actually shows (the user may have changed it elsewhere).
static void FZSyncStoredIcon(void) {
    NSInteger shown = [UIApplication.sharedApplication.alternateIconName isEqualToString:kAltIconWhite] ? 1 : 0;
    if (FZInt(FZSettingsKeyAppIcon, 0) != shown) FZSetInt(FZSettingsKeyAppIcon, shown);
}

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
    FZSyncStoredIcon();
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
    version.text = [NSString stringWithFormat:@"v%s for NaviMus %@", FROZIO_VERSION,
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
    FZModRow *icon = FZChoiceRow(@"App icon", @"The icon on your Home Screen.", FZSettingsKeyAppIcon, @[@"Cyan", @"White"], 0);
    icon.symbol = @"app.badge";
    icon.choiceNotes = @[@"Frozio's default icon.", @"A monochrome white icon."];
    icon.choiceFooter = @"iOS confirms an icon change with a short alert.";
    icon.chosen = ^(NSInteger index) { FZApplyAppIcon(index); };

    FZModRow *guard = FZSwitchRow(@"Keep library on this iPhone",
                                  @"Stops iCloud sync of NaviMus's library cache, as in the App Store build. "
                                  @"Turning it off can crash a re-signed app once a server is added.",
                                  FZSettingsKeyCloudKitGuard);
    guard.symbol = @"externaldrive.badge.icloud";
    guard.info = @"Re-signed apps often get iCloud containers without push notifications. SwiftData then tries "
                 @"to sync through CloudKit, and CloudKit aborts the app.";

    FZModRow *repo = FZLinkRow(@"Frozio on GitHub", @"Source, builds and issues.", FZRepoURL);
    repo.symbol = @"chevron.left.forwardslash.chevron.right";

    NSArray *sections = @[
        FZSection(@"Appearance", @[icon]),
        FZNotedSection(@"Fixes", @[guard], FZRestartNote),
        FZSection(@"About", @[repo]),
    ];
    return [[FZSettingsRootPage alloc] initWithTitle:@"Frozio" intro:nil sections:sections footer:nil];
}

void FZPresentSettings(UIViewController *owner) {
    if (!owner) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:FZMakeSettingsPage()];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}
