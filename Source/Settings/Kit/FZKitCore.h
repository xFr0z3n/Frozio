// FZKitCore: what the settings kit (adapted from taurus, GPL-3.0) needs from a "core", mapped onto
// Frozio. Preferences live in Frozio's own suite (FZSettings, "com.frozio.tweak"). Spotify's
// remote-config flags don't exist in NaviMus, so the flag override API is inert.
#pragma once
#import <UIKit/UIKit.h>
#import "Core/FZLog.h"
#import "Settings/Kit/FZViewTree.h"

BOOL FZFlag(NSString *key, BOOL fallback);
BOOL FZEnabled(NSString *key);   // an unset switch is on
BOOL FZHidden(NSString *key);    // an unset switch is off
void FZSetEnabled(NSString *key, BOOL on);
NSInteger FZInt(NSString *key, NSInteger fallback);
void FZSetInt(NSString *key, NSInteger value);

// Spotify flag overrides: no such thing in NaviMus. Always nil / no-op.
id FZFlagOverride(NSString *key);
void FZSetFlagOverride(NSString *key, id value);
id FZLockedFlagValue(NSString *key, BOOL *beatsOverride);

// Frozio ships only the redesign look (docs/DECISIONS.md).
static inline BOOL FZRedesignedUI(void) { return YES; }

// The kit logs with NSString formats.
#ifdef FROZIO_DEBUG
#define FZLogNS(...) FZLogWrite(NO, __VA_ARGS__)
#else
#define FZLogNS(...) do { } while (0)
#endif
