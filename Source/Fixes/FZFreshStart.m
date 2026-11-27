// FZFreshStart: NaviMus restores the tab and the Library pages that were open when it was last closed
// (local_data/selectedTab.json, local_data/libraryRoutes.json per server, read at launch), and UIKit restores the
// scene's own saved state. The user wants a fresh app each launch: Home, and each tab on its first page. Before
// NaviMus's main() runs, Frozio writes "home" and an empty route list into those files and drops the scene's saved
// state. Only those: NaviMus's queue, position and everything else are left alone.
#import "Fixes/FZFreshStart.h"
#import "Core/FZLog.h"
#import "Prefs/FZSettings.h"

NSString *const FZKeyFreshStart = @"fz.freshStart";

void FZApplyFreshStart(void) {
    if (![[FZSettings defaults] boolForKey:FZKeyFreshStart]) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *arpeggi = [support stringByAppendingPathComponent:@"Arpeggi"];
    NSUInteger reset = 0;
    for (NSString *account in [fm contentsOfDirectoryAtPath:arpeggi error:nil]) {
        NSString *data = [[arpeggi stringByAppendingPathComponent:account] stringByAppendingPathComponent:@"local_data"];
        NSString *tab = [data stringByAppendingPathComponent:@"selectedTab.json"];
        NSString *routes = [data stringByAppendingPathComponent:@"libraryRoutes.json"];
        if ([fm fileExistsAtPath:tab]) { [@"\"home\"" writeToFile:tab atomically:YES encoding:NSUTF8StringEncoding error:nil]; reset++; }
        if ([fm fileExistsAtPath:routes]) { [@"[]" writeToFile:routes atomically:YES encoding:NSUTF8StringEncoding error:nil]; reset++; }
    }
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *saved = [library stringByAppendingPathComponent:@"Saved Application State"];
    for (NSString *name in [fm contentsOfDirectoryAtPath:saved error:nil]) {
        if ([name hasSuffix:@".savedState"]) [fm removeItemAtPath:[saved stringByAppendingPathComponent:name] error:nil];
    }
    FZLog("fresh start: %lu saved tab/route files reset, scene state dropped", (unsigned long)reset);
}
