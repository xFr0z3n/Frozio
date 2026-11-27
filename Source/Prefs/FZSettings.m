#import "FZSettings.h"

NSString *const FZSettingsSuiteName  = @"com.frozio.tweak";
NSString *const FZSettingsKeyAppIcon = @"fz.appIcon";
NSString *const FZSettingsKeyCloudKitGuard = @"fz.cloudKitGuard";
NSString *const FZSettingsKeyAccentInNaviMus = @"fz.redesign.accent.navimus";
NSString *const FZSettingsKeyLockScreenLyrics = @"fz.lockScreenLyrics";
NSString *const FZSettingsKeyRedesign = @"fz.redesign";

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
        FZSettingsKeyAppIcon: @0,
        FZSettingsKeyCloudKitGuard: @YES,
        @"fz.playback.pausedStatusClear": @2,   // FZKeyPausedStatus: 2 minutes
        @"fz.redesign.tabsFirstPage": @YES,     // FZRKeyTabsFirstPage
        @"fz.freshStart": @YES,                 // FZKeyFreshStart: Home and first pages each launch
        // The user's own settings export (2026-11-15) as everyone's starting point: the redesign on, the accent
        // 0x07D2FF in NaviMus too, lock screen lyrics, circles behind bar buttons but not behind shuffle and download,
        // the mini player without download and swipe, the player with the Fluid background, sleep timer in the right
        // slot and no AirPlay or download buttons, Year sort oldest first.
        FZSettingsKeyAccentInNaviMus: @YES,
        FZSettingsKeyLockScreenLyrics: @YES,
        FZSettingsKeyRedesign: @YES,
        @"fz.artistBlock": @NO,
        @"fz.library.albums.yearNewestFirst": @NO,
        @"fz.redesign.accent": @512767,
        @"fz.redesign.circle.actions": @NO,
        @"fz.redesign.circle.back": @YES,
        @"fz.redesign.circle.more": @YES,
        @"fz.redesign.circle.others": @YES,
        @"fz.redesign.mini.download": @NO,
        @"fz.redesign.mini.swipe": @NO,
        @"fz.redesign.player.airplay": @NO,
        @"fz.redesign.player.background": @2,
        @"fz.redesign.player.download": @NO,
        @"fz.redesign.player.rightSlot": @1,
        @"fz.redesign.player.sleep": @YES,
        // The cover stays its size on pause (the user, 2026-11-15: it zoomed in and out).
        @"fz.redesign.player.shrink": @NO,
    }];
}

@end
