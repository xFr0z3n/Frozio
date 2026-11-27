#import "Fixes/FZPausedStatus.h"
#import "Fixes/FZFreshStart.h"
#import "FZSettingsPage.h"
#import "Settings/FZAboutPage.h"
#import "ArtistBlock/FZArtistBlock.h"
#import "Settings/Kit/FZModPage.h"
#import "Settings/Kit/FZPageStyle.h"
#import "Settings/Kit/FZKitCore.h"
#import "Prefs/FZSettings.h"
#import "Redesign/Kit/FZRAccent.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Album/FZRAlbumPage.h"
#import "Redesign/FZRLibrarySorts.h"
#import "Diagnostics/FZLibrarySchema.h"

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

// The white icon's CFBundleAlternateIcons key: "AppIcon-White" when CI rebuilt the asset catalog
// (scripts/rebuild_assets.sh), "White" for the loose-PNG fallback (scripts/patch_icons.py).
static NSString *FZWhiteIconName(void) {
    static NSString *name;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *alts = NSBundle.mainBundle.infoDictionary[@"CFBundleIcons"][@"CFBundleAlternateIcons"];
        if ([alts isKindOfClass:NSDictionary.class]) {
            for (NSString *key in alts) if ([key rangeOfString:@"White"].location != NSNotFound) { name = key; break; }
        }
        FZLog("app icon: white alternate key = %@ (alternates: %@)", name ?: @"<none>", alts.allKeys);
    });
    return name;
}
#define kAltIconWhite FZWhiteIconName()
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

#pragma mark - restart

// A switch read at launch: offer to close NaviMus so it applies. nil when it's back to what's running.
static void FZOfferRestart(NSString *what) {
    if (!what) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Restart NaviMus?"
        message:[what stringByAppendingString:@" applies when NaviMus starts. Close it now and open it again."]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Close NaviMus" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[FZSettings defaults] synchronize];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [FZTopController() presentViewController:a animated:YES completion:nil];
}

#pragma mark - diagnostics (debug builds)

#ifdef FROZIO_DEBUG
static void FZShareLog(void) {
    // The library store's layout (names and counts only) for the rebuilt redesign screens.
    FZLogLibrarySchema();
    NSString *path = FZLogFilePath();
    if (!path || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        FZShowAlert(@"No log yet", path ?: @"Documents is unavailable.");
        return;
    }
    NSMutableArray *items = [NSMutableArray arrayWithObject:[NSURL fileURLWithPath:path]];
    NSString *old = [path stringByAppendingString:@".1"];
    if ([NSFileManager.defaultManager fileExistsAtPath:old]) [items addObject:[NSURL fileURLWithPath:old]];
    // NaviMus's own preferences file, to learn the tint format. The data folders are listed in the
    // log by name and size only (no contents); the only file attached is one named "settings*".
    // Server, login and credential files are never attached (and passwords live in the keychain).
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *roots = @[
        NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject ?: @"",
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"",
        NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject ?: @"",
    ];
    NSArray<NSString *> *skip = @[@"login", @"credential", @"server", @"auth", @"account", @"configuration"];
    for (NSString *root in roots) {
        if (!root.length) continue;
        NSDirectoryEnumerator<NSString *> *e = [fm enumeratorAtPath:root];
        NSUInteger listed = 0;
        for (NSString *rel in e) {
            if (e.level > 3) { [e skipDescendants]; continue; }
            NSString *full = [root stringByAppendingPathComponent:rel];
            NSString *name = rel.lastPathComponent.lowercaseString;
            if ([name hasSuffix:@".sqlite"] || [name hasSuffix:@"-wal"] || [name hasSuffix:@"-shm"] || [rel hasPrefix:@"Caches"]) continue;
            NSDictionary *a = [e fileAttributes];
            if (![a.fileType isEqualToString:NSFileTypeRegular]) continue;
            if (listed++ < 200) FZLog("data: %@/%@ (%llu B)", root.lastPathComponent, rel, a.fileSize);
            BOOL sensitive = NO;
            for (NSString *s in skip) if ([name containsString:s]) sensitive = YES;
            if (!sensitive && [name hasPrefix:@"settings"] && a.fileSize < 256 * 1024) {
                [items addObject:[NSURL fileURLWithPath:full]];
                FZLog("share: + %@", rel);
            }
        }
    }
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

    FZModRow *about = FZPageRow(@"About", ^UIViewController *{ return FZAboutPage(); });
    about.subtitle = @"Version, licenses, backup and reset.";
    about.symbol = @"info.circle";

    FZModRow *accent = FZStatActionRow(@"Accent colour", @"The redesign's accent on Frozio's own screens.",
                                       ^NSString *{ return FZRAccentLabel(); }, ^{ FZRPickAccent(); });
    accent.symbol = @"paintpalette";
    accent.refreshOn = FZRAccentDidChangeNotification;
    FZModRow *resetAccent = FZActionRow(@"Reset accent", @"Back to the redesign green #37F200.", ^{ FZRResetAccent(); });
    resetAccent.symbol = @"arrow.counterclockwise";

    FZModRow *inNaviMus = FZOptionRow(@"Use accent in NaviMus",
                                      @"Sets NaviMus's own tint to the accent. Off puts NaviMus's tint back.",
                                      FZSettingsKeyAccentInNaviMus);
    inNaviMus.symbol = @"paintbrush";
    inNaviMus.info = @"Frozio writes NaviMus's tint in its settings file before NaviMus starts, keeping a backup of "
                     @"the original. Picking a tint in NaviMus's own settings while this is on is overridden next launch.";

    FZModRow *lockLyrics = FZOptionRow(@"Lock screen lyrics",
                                       @"The line being sung in place of the artist on the lock screen, Control Center and CarPlay.",
                                       FZSettingsKeyLockScreenLyrics);
    lockLyrics.symbol = @"quote.bubble";
    lockLyrics.info = @"Frozio uses the synced lyrics NaviMus has saved on this iPhone and fetches nothing itself. "
                      @"A song shows its lines once NaviMus has loaded its lyrics, for example after opening the lyrics view once.";

    FZModRow *blocked = FZPageRow(@"Blocked artists", ^UIViewController *{ return FZArtistBlockPage(); });
    blocked.symbol = @"person.crop.circle.badge.xmark";
    blocked.value = ^NSString *{
        NSUInteger count = FZBlockedArtists().count;
        if (!FZHidden(FZKeyArtistBlock)) return count ? @"Off" : @"None";
        return count ? @(count).stringValue : @"None";
    };

    FZModRow *redesign = FZOptionRow(@"Redesigned look",
                                     @"spoti.pw's redesign on NaviMus's screens: always dark, with its own bars and accent.",
                                     FZSettingsKeyRedesign);
    redesign.symbol = @"sparkles";
    redesign.glows = YES;
    redesign.info = @"Black throughout, whatever NaviMus's own appearance setting says. On iOS 26 the tab and "
                    @"navigation bars are the system's Liquid Glass; before iOS 26 they get the redesign's blur.";
    redesign.changed = ^(BOOL on) { FZOfferRestart(on == FZRRedesignActive() ? nil : @"The redesigned look"); };

    FZModRow *pages = FZPageRow(@"Redesigned pages", ^UIViewController *{ return FZRRedesignOptionsPage(); });
    pages.subtitle = @"Buttons, circles and lines of the rebuilt pages.";
    pages.symbol = @"slider.horizontal.3";

    NSMutableArray *appearance = [NSMutableArray arrayWithObjects:redesign, pages, accent, resetAccent, inNaviMus, nil];
#ifdef FROZIO_ICON_PICKER
    // Hidden: setAlternateIconName fails with NSOSStatusErrorDomain -54 on the user's re-signed
    // install, with loose PNGs and with catalog icons alike (docs/FEATURES.md, Known issues).
    [appearance addObject:icon];
#else
    (void)icon;
#endif
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        FZNotedSection(@"Appearance", appearance, @"Changes to NaviMus's tint apply after you restart the app."),
        FZNotedSection(@"Lyrics", @[lockLyrics, FZWithSymbol(FZSwitchRow(@"Look up lyrics online", @"When NaviMus and your server have none: taurus's sources (BiniLyrics, Musixmatch, Unison, NetEase, LRCLIB, QQ Music, KuGou). Sends the song's title, artist, album and length.", @"fz.lyrics.lrclib"), @"magnifyingglass")], @"Applies right away, from the next line."),
        FZNotedSection(@"Playback", @[blocked, FZWithSymbol(FZChoiceRow(@"Clear paused status", @"Tells your server \"stopped\" after this long paused, so Now Playing (and Discord status plugins) stop showing the paused song. Needs NaviMus's Report playback.", FZKeyPausedStatus, FZPausedStatusChoices(), 2), @"pause.circle")], nil),
        FZNotedSection(@"Library", @[FZWithSymbol(FZSwitchRow(@"More sort options", @"Year (newest or oldest first) and Favourites for Albums.", FZKeyLibrarySorts), @"arrow.up.arrow.down"),
                                      FZWithSymbol(FZSwitchRow(@"Fix wrong covers in lists", @"NaviMus shows an earlier album's cover on a reused row.", @"fz.fix.coverReuse"), @"photo.on.rectangle")],
                       @"Applies the next time a sort menu opens or a list scrolls."),
        FZNotedSection(@"Fixes", @[guard, FZWithSymbol(FZSwitchRow(@"Start fresh", @"Every launch opens Home, each tab on its first page, instead of where you left off.", FZKeyFreshStart), @"house")], FZRestartNote),
    ]];
#ifdef FROZIO_DEBUG
    FZModRow *share = FZStatActionRow(@"Share log", @"Send frozio.log with AirDrop, Mail, Messages or Save to Files.",
                                      ^NSString *{ return FZLogSize(); }, ^{ FZShareLog(); });
    share.symbol = @"square.and.arrow.up";
    FZModRow *clear = FZActionRow(@"Clear log", @"Start a fresh log before reproducing a problem.", ^{ FZClearLog(); });
    clear.symbol = @"trash";
    [sections addObject:FZNotedSection(@"Diagnostics", @[share, clear], @"Debug build: Frozio writes everything it does to this log.")];
#endif
    [sections addObject:FZSection(@"About", @[about])];
    return [[FZSettingsRootPage alloc] initWithTitle:@"Frozio" intro:nil sections:sections footer:nil];
}

void FZPresentSettings(UIViewController *owner) {
    if (!owner) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:FZMakeSettingsPage()];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}
