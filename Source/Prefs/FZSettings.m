#import "FZSettings.h"

NSString *const FZSettingsSuiteName  = @"com.frozio.tweak";
NSString *const FZSettingsKeyAppIcon = @"fz.appIcon";

@implementation FZSettings

+ (NSUserDefaults *)defaults {
    static NSUserDefaults *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:FZSettingsSuiteName] ?: NSUserDefaults.standardUserDefaults;
    });
    return d;
}

+ (void)registerDefaults {
    [[self defaults] registerDefaults:@{
        FZSettingsKeyAppIcon: @"cyan",
    }];
}

@end
