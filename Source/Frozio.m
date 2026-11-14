// Frozio entry point. The constructor evaluates the version gate; every module installs itself
// only when the gate passes, and each checks its own setting and preconditions.
#import <Foundation/Foundation.h>
#import "Core/FZLog.h"
#import "Core/FZVersionGate.h"
#import "Prefs/FZSettings.h"
#import "Fixes/FZCloudKitGuard.h"
#import "Diagnostics/FZScreenCensus.h"
#import "Settings/FZSettingsEntry.h"
#import "Settings/Kit/FZPage.h"

__attribute__((constructor)) static void FrozioInit(void) {
    @autoreleasepool {
        FZLog("loaded v%s", FROZIO_VERSION);
        if (!FZVersionGatePassed()) return; // unknown NaviMus build: stay completely inert
        [FZSettings registerDefaults];
        // Runs before NaviMus's main(): SwiftData builds its ModelContainer later, after login.
        if ([[FZSettings defaults] boolForKey:FZSettingsKeyCloudKitGuard]) FZInstallCloudKitGuard();
        // Frozio settings: always available (it's how every other toggle is reached).
        FZRegisterPages();
        FZInstallSettingsEntry();
#ifdef FROZIO_DEBUG
        FZInstallScreenCensus(); // debug-only diagnostics for picking verified hook targets
#endif
        // Feature modules install here, each checking FZSettings and its own preconditions.
    }
}
