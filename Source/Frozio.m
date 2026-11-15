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
#import "Redesign/FZNaviMusTint.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/FZRNaviMusControls.h"
#import "Redesign/Player/FZRPlayer.h"
#import "Redesign/FZRLibrarySorts.h"
void FZInstallCoverReuseFix(void);
extern NSString *const FZKeyCoverReuseFix;
#import "Redesign/Data/FZServer.h"
#import "Lyrics/FZLockScreenLyrics.h"
#import "ArtistBlock/FZArtistBlock.h"
#import "Core/FZRemote.h"

__attribute__((constructor)) static void FrozioInit(void) {
    @autoreleasepool {
        FZLog("loaded v%s", FROZIO_VERSION);
        if (!FZVersionGatePassed()) return; // unknown NaviMus build: stay completely inert
        [FZSettings registerDefaults];
        // Runs before NaviMus's main(): SwiftData builds its ModelContainer later, after login.
        if ([[FZSettings defaults] boolForKey:FZSettingsKeyCloudKitGuard]) FZInstallCloudKitGuard();
        // Before NaviMus reads its settings.json: apply (or undo) the accent as NaviMus's own tint.
        FZSyncNaviMusTint();
        // The redesigned look: before any window or bar exists.
        FZRInstallAppLook();
        if (FZRRedesignActive()) {
            FZInstallServer();     // NaviMus's server and login, from its own requests
            FZRInstallPages();     // rebuilt pages laid over NaviMus's
            FZRInstallPlayer();    // the rebuilt mini player and player over NaviMus's
        }
        // Frozio settings: always available (it's how every other toggle is reached).
        FZRegisterPages();
        FZInstallSettingsEntry();
#ifdef FROZIO_DEBUG
        FZInstallScreenCensus(); // debug-only diagnostics for picking verified hook targets
#endif
        // Feature modules install here, each checking FZSettings and its own preconditions.
        // Lock screen lyrics: a pass-through hook that reads its switch live, so it installs either way.
        FZInstallLockScreenLyrics();
        // Blocked artists: after lyrics, so it sees NaviMus's own Now Playing info; before main(), so
        // NaviMus's next-track handler is seen as it registers.
        FZInstallRemote();          // NaviMus's command handlers and Now Playing (after lyrics)
        FZInstallArtistBlock();
        FZInstallLibrarySorts();    // Year and Favourites in NaviMus's album sort menu (reads its switch live)
        FZInstallCoverReuseFix();   // NaviMus's grids keep a reused cell's old cover (reads its switch live)
    }
}
