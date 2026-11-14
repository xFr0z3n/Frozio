// Adapted from taurus/tweak/Sources/App/About/AboutSettings.m, Backup.m and Licenses.m @ fe3211c
// (GPL-3.0, github.com/xFr0z3n/taurus). Renamed SG→FZ; Spotify-only rows (cache clearing, device logs,
// welcome tour, app icons, flag overrides, stock mode) removed. Settings live in Frozio's own suite
// (FZSettings), not the app's standard defaults.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Settings/FZAboutPage.h"
#import "Settings/Kit/FZModPage.h"
#import "Settings/Kit/FZPageStyle.h"
#import "Settings/Kit/FZKitCore.h"
#import "Prefs/FZSettings.h"

#pragma mark - store

// A Frozio setting is any "fz." key, except state that mirrors the device rather than a choice:
// fz.appIcon follows what iOS shows (FZSettingsPage.m), so a backup can't carry it across.
static BOOL isSetting(NSString *key) {
    return [key hasPrefix:@"fz."] && ![key isEqualToString:FZSettingsKeyAppIcon];
}

static NSDictionary *storedSettings(void) {
    return [[FZSettings defaults] persistentDomainForName:FZSettingsSuiteName] ?: @{};
}

static void showAlert(NSString *title, NSString *message, UIAlertAction *confirm) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    if (confirm) [alert addAction:confirm];
    [alert addAction:[UIAlertAction actionWithTitle:confirm ? @"Cancel" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
    [FZTopController() presentViewController:alert animated:YES completion:nil];
}

// Hooks read their switches at launch, so a reset or an import takes effect by closing NaviMus.
static void closeApp(void) {
    [[FZSettings defaults] synchronize];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
}

static NSString *hostVersion(void) {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
}

#pragma mark - reset

static void resetAll(void) {
    NSUserDefaults *store = [FZSettings defaults];
    NSUInteger removed = 0;
    for (NSString *key in storedSettings()) {
        if (!isSetting(key)) continue;
        [store removeObjectForKey:key];
        removed++;
    }
    FZLog("reset: removed %lu keys", (unsigned long)removed);
    (void)removed; // release builds compile FZLog out
    closeApp();
}

void FZConfirmResetAll(void) {
    showAlert(@"Reset all settings?",
              @"Every Frozio setting goes back to its default and NaviMus closes. Open it again to start fresh. "
              @"NaviMus's own settings, servers and downloads are untouched.",
              [UIAlertAction actionWithTitle:@"Reset and close" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                  resetAll();
              }]);
}

#pragma mark - backup

void FZExportSettings(void) {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    [storedSettings() enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (isSetting(key) && [NSJSONSerialization isValidJSONObject:@[value]]) settings[key] = value;
    }];
    NSDictionary *file = @{
        @"frozio": @(FROZIO_VERSION),
        @"navimus": hostVersion(),
        @"settings": settings,
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"frozio-settings.json"]];
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        FZLogError("export: %@", error);
        showAlert(@"Couldn't export", error.localizedDescription ?: @"The settings file could not be written.", nil);
        return;
    }
    FZLog("export: %lu keys", (unsigned long)settings.count);

    UIViewController *top = FZTopController();
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = top.view;
    sheet.popoverPresentationController.sourceRect = (CGRect){CGPointMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds)), CGSizeZero};
    [top presentViewController:sheet animated:YES completion:nil];
}

static Class kindOf(id value) {
    for (Class kind in @[NSNumber.class, NSString.class, NSArray.class, NSDictionary.class]) {
        if ([value isKindOfClass:kind]) return kind;
    }
    return Nil;
}

static void importSettings(NSDictionary *settings) {
    NSUserDefaults *store = [FZSettings defaults];
    NSDictionary *stored = storedSettings();
    for (NSString *key in stored) {
        if (isSetting(key)) [store removeObjectForKey:key];
    }
    NSUInteger skipped = 0;
    for (NSString *key in settings) {
        id value = settings[key];
        id current = stored[key];
        BOOL fits = [key isKindOfClass:NSString.class] && isSetting(key)
            && [NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0]
            && (!current || kindOf(current) == kindOf(value));
        if (fits) [store setObject:value forKey:key];
        else skipped++;
    }
    FZLog("import: set %lu keys, skipped %lu", (unsigned long)(settings.count - skipped), (unsigned long)skipped);
    (void)skipped; // release builds compile FZLog out
    closeApp();
}

@interface FZSettingsPicker : NSObject <UIDocumentPickerDelegate>
@end

@implementation FZSettingsPicker

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    // The picker is still sliding away here, and an alert presented over it comes up half drawn
    // (title only, no buttons). Ask once its dismissal has finished.
    id<UIViewControllerTransitionCoordinator> transition = picker.transitionCoordinator;
    if (transition) {
        [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            [self confirmImportOf:urls.firstObject];
        }];
    } else {
        [self confirmImportOf:urls.firstObject];
    }
}

- (void)confirmImportOf:(NSURL *)url {
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    id file = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *settings = [file isKindOfClass:NSDictionary.class] ? file[@"settings"] : nil;
    if (![settings isKindOfClass:NSDictionary.class]) {
        showAlert(@"Not a settings file", @"Pick a file made by Export settings.", nil);
        return;
    }
    NSString *version = [file[@"frozio"] isKindOfClass:NSString.class] ? file[@"frozio"] : @"unknown";
    NSString *message = [NSString stringWithFormat:@"Your Frozio settings are replaced by the file's, exported from Frozio %@. "
                                                   @"Anything it doesn't have goes back to its default, and NaviMus closes.", version];
    showAlert(@"Import settings?", message, [UIAlertAction actionWithTitle:@"Import and close" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        importSettings(settings);
    }]);
}

@end

void FZImportSettings(void) {
    static FZSettingsPicker *delegate;
    if (!delegate) delegate = [FZSettingsPicker new];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = delegate;
    [FZTopController() presentViewController:picker animated:YES completion:nil];
}

#pragma mark - licenses

UIViewController *FZLicensesPage(void) {
    FZModRow *frozio = FZLinkRow(@"Frozio", @"GNU General Public License v3.0", [FZRepoURL stringByAppendingString:@"/blob/main/LICENSE"]);
    FZModRow *taurus = FZLinkRow(@"taurus", @"Settings kit and redesign kit · GPL-3.0", @"https://github.com/xFr0z3n/taurus");
    return [[FZModPage alloc] initWithTitle:@"Licenses" intro:@"Frozio's own license, and the code from others it includes." sections:@[
        FZSection(nil, @[frozio]),
        FZNotedSection(nil, @[taurus], @"Frozio's settings pages, glass and palette are adapted from taurus. "
                                       @"Each adapted file names its origin; see docs/LICENSES.md in the repo."),
    ] footer:nil];
}

#pragma mark - page

UIViewController *FZAboutPage(void) {
    FZModRow *reset = FZWithSymbol(FZActionRow(@"Reset all settings", nil, ^{ FZConfirmResetAll(); }), @"trash");
    reset.color = FZRed();
    NSString *navimus = hostVersion();
    NSArray<FZModSection *> *sections = @[
        FZSection(nil, @[
            FZStatRow(@"Version", ^NSString *{ return @(FROZIO_VERSION); }),
            FZStatRow(@"NaviMus", ^NSString *{ return navimus; }),
        ]),
        FZSection(nil, @[
            FZWithSymbol(FZLinkRow(@"Frozio on GitHub", @"Source, builds and issues.", FZRepoURL), @"chevron.left.forwardslash.chevron.right"),
            FZWithSymbol(FZPageRow(@"Licenses", ^UIViewController *{ return FZLicensesPage(); }), @"doc.text"),
        ]),
        FZSection(nil, @[
            FZWithSymbol(FZActionRow(@"Export settings", nil, ^{ FZExportSettings(); }), @"square.and.arrow.up"),
            FZWithSymbol(FZActionRow(@"Import settings", nil, ^{ FZImportSettings(); }), @"square.and.arrow.down"),
        ]),
        FZSection(nil, @[reset]),
    ];
    return [[FZModPage alloc] initWithTitle:@"About" intro:nil sections:sections footer:nil];
}
