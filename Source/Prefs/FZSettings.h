// Frozio settings store (preference stub). Frozio keeps its own UserDefaults suite and
// never writes NaviMus's settings (Application Support/*.json, iCloud KVS).
#pragma once
#import <Foundation/Foundation.h>

extern NSString *const FZSettingsSuiteName;     // "com.frozio.tweak"
extern NSString *const FZSettingsKeyAppIcon;    // "fz.appIcon": "cyan" (primary) | "white" (alternate)
extern NSString *const FZSettingsKeyCloudKitGuard; // "fz.cloudKitGuard": YES = SwiftData stays local-only (stock behaviour)

@interface FZSettings : NSObject
+ (NSUserDefaults *)defaults;
+ (void)registerDefaults;
@end
