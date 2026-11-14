#import "Redesign/FZNaviMusTint.h"
#import "Redesign/Kit/FZRAccent.h"
#import "Prefs/FZSettings.h"
#import "Core/FZLog.h"
#import <UIKit/UIKit.h>

static NSString *const kTintKey = @"appTintColorPreset";
static NSString *const kTintByAppearanceKey = @"tintColorBasedOnAppearance";
static NSString *const kDateKey = @"dateLastPersisted";

static NSString *FZNaviMusSettingsDir(void) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return support ? [support stringByAppendingPathComponent:@"Arpeggi/shared_data"] : nil;
}

static NSMutableDictionary *FZReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [obj isKindOfClass:NSMutableDictionary.class] ? obj : nil;
}

static BOOL FZWriteJSON(NSDictionary *dict, NSString *path) {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&err];
    if (!data) { FZLogError("tint: encode failed: %@", err); return NO; }
    if (![data writeToFile:path options:NSDataWritingAtomic error:&err]) { FZLogError("tint: write failed: %@", err); return NO; }
    return YES;
}

static BOOL FZTintIsKnownShape(id tint) {
    if (![tint isKindOfClass:NSDictionary.class]) return NO;
    NSString *type = tint[@"type"];
    if ([type isEqualToString:@"preset"]) return [tint[@"preset"] isKindOfClass:NSString.class];
    if ([type isEqualToString:@"custom"]) {
        NSDictionary *c = tint[@"color"];
        return [c isKindOfClass:NSDictionary.class] && [c[@"red"] isKindOfClass:NSNumber.class]
            && [c[@"green"] isKindOfClass:NSNumber.class] && [c[@"blue"] isKindOfClass:NSNumber.class];
    }
    return NO;
}

static BOOL FZSameColour(NSDictionary *tint, CGFloat r, CGFloat g, CGFloat b) {
    if (![tint[@"type"] isEqualToString:@"custom"]) return NO;
    NSDictionary *c = tint[@"color"];
    CGFloat eps = 0.5 / 255.0;
    return fabs([c[@"red"] doubleValue] - r) < eps && fabs([c[@"green"] doubleValue] - g) < eps
        && fabs([c[@"blue"] doubleValue] - b) < eps && fabs([c[@"opacity"] doubleValue] - 1) < eps;
}

void FZSyncNaviMusTint(void) {
    @try {
        NSString *dir = FZNaviMusSettingsDir();
        NSString *path = [dir stringByAppendingPathComponent:@"settings.json"];
        NSString *backupPath = [path stringByAppendingString:@".frozio-backup"];
        NSFileManager *fm = NSFileManager.defaultManager;
        BOOL on = [[FZSettings defaults] boolForKey:FZSettingsKeyAccentInNaviMus];

        if (!path || ![fm fileExistsAtPath:path]) {
            FZLog("tint: no NaviMus settings.json yet (first launch?); nothing to do");
            return;
        }
        NSString *version = [[NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"settingsMigrationVersion.json"]
                                                       encoding:NSUTF8StringEncoding error:nil]
                             stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![version isEqualToString:@"2"]) {
            FZLogError("tint: settingsMigrationVersion is %@, expected 2; file left untouched", version ?: @"<missing>");
            return;
        }
        NSMutableDictionary *settings = FZReadJSON(path);
        if (!settings || !FZTintIsKnownShape(settings[kTintKey])) {
            FZLogError("tint: settings.json has an unexpected shape; file left untouched");
            return;
        }

        if (!on) {
            // Switch off: put NaviMus's own tint back if Frozio changed it earlier.
            NSMutableDictionary *backup = FZReadJSON(backupPath);
            if (!backup) return;
            if (FZTintIsKnownShape(backup[kTintKey])) {
                settings[kTintKey] = backup[kTintKey];
                if (backup[kTintByAppearanceKey]) settings[kTintByAppearanceKey] = backup[kTintByAppearanceKey];
                settings[kDateKey] = @(NSDate.date.timeIntervalSinceReferenceDate);
                if (FZWriteJSON(settings, path)) FZLog("tint: restored NaviMus's own tint %@", backup[kTintKey]);
            }
            [fm removeItemAtPath:backupPath error:nil];
            return;
        }

        CGFloat r = 0, g = 0, b = 0, a = 1;
        if (![FZRAccentColor() getRed:&r green:&g blue:&b alpha:&a]) return;
        if (FZSameColour(settings[kTintKey], r, g, b) && ![settings[kTintByAppearanceKey] boolValue]) {
            FZLog("tint: NaviMus already uses the accent (%@)", FZRAccentLabel());
            return;
        }
        if (![fm fileExistsAtPath:backupPath]) {
            NSDictionary *original = @{kTintKey: settings[kTintKey], kTintByAppearanceKey: settings[kTintByAppearanceKey] ?: @NO};
            if (!FZWriteJSON(original, backupPath)) return; // no backup, no change
        }
        settings[kTintKey] = @{@"type": @"custom",
                               @"color": @{@"red": @(r), @"green": @(g), @"blue": @(b), @"opacity": @1}};
        settings[kTintByAppearanceKey] = @NO;
        settings[kDateKey] = @(NSDate.date.timeIntervalSinceReferenceDate); // newer than the iCloud copy
        if (FZWriteJSON(settings, path)) FZLog("tint: NaviMus tint set to %@", FZRAccentLabel());
    } @catch (NSException *e) {
        FZLogError("tint: %@", e); // never take NaviMus down
    }
}
