// Frozio settings store (preference stub). Frozio keeps its own UserDefaults suite and
// never writes NaviMus's settings (Application Support/*.json, iCloud KVS).
#pragma once
#import <Foundation/Foundation.h>

extern NSString *const FZSettingsSuiteName;     // "com.frozio.tweak"
extern NSString *const FZSettingsKeyAppIcon;    // "fz.appIcon": 0 = cyan (primary), 1 = white (alternate "White")
extern NSString *const FZSettingsKeyAccentInNaviMus; // "fz.redesign.accent.navimus": NO = NaviMus keeps its own tint
extern NSString *const FZSettingsKeyLockScreenLyrics; // "fz.lockScreenLyrics": YES = the sung line replaces the artist in Now Playing
extern NSString *const FZSettingsKeyCloudKitGuard; // "fz.cloudKitGuard": YES = SwiftData stays local-only (stock behaviour)

@interface FZSettings : NSObject
+ (NSUserDefaults *)defaults;
+ (void)registerDefaults;
@end
