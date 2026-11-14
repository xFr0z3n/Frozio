// Frozio entry point. Phase 1: no hooks. The constructor only evaluates the version
// gate; feature modules (Phase 2+) install themselves only when it passes.
#import <Foundation/Foundation.h>
#import "FZLog.h"
#import "FZVersionGate.h"
#import "Prefs/FZSettings.h"

__attribute__((constructor)) static void FrozioInit(void) {
    @autoreleasepool {
        FZLog("loaded v%{public}s", FROZIO_VERSION);
        if (!FZVersionGatePassed()) return; // unknown NaviMus build: stay completely inert
        [FZSettings registerDefaults];
        // Phase 2+: feature modules install here, each checking FZSettings and its own preconditions.
    }
}
