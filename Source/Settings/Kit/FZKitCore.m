#import "FZKitCore.h"
#import "Prefs/FZSettings.h"

BOOL FZFlag(NSString *key, BOOL fallback) {
    if (!key) return fallback;
    id v = [[FZSettings defaults] objectForKey:key];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}

BOOL FZEnabled(NSString *key) { return FZFlag(key, YES); }
BOOL FZHidden(NSString *key) { return FZFlag(key, NO); }

void FZSetEnabled(NSString *key, BOOL on) {
    if (key) [[FZSettings defaults] setBool:on forKey:key];
}

NSInteger FZInt(NSString *key, NSInteger fallback) {
    if (!key) return fallback;
    id v = [[FZSettings defaults] objectForKey:key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : fallback;
}

void FZSetInt(NSString *key, NSInteger value) {
    if (key) [[FZSettings defaults] setInteger:value forKey:key];
}

id FZFlagOverride(NSString *key) { return nil; }
void FZSetFlagOverride(NSString *key, id value) {}
id FZLockedFlagValue(NSString *key, BOOL *beatsOverride) {
    if (beatsOverride) *beatsOverride = NO;
    return nil;
}
