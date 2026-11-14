#import "FZCloudKitGuard.h"
#import "Core/FZLog.h"
#import "Core/FZHook.h"

static IMP fz_origGetOptions;
static IMP fz_origSetOptions;

static id fz_cloudKitContainerOptions(id self, SEL _cmd) {
    return nil; // never mirror: matches the App Store build's empty iCloud container list
}

static void fz_setCloudKitContainerOptions(id self, SEL _cmd, id options) {
    if (options) FZLog("CloudKit guard: dropped cloudKitContainerOptions on %@", self);
    ((void (*)(id, SEL, id))fz_origSetOptions)(self, _cmd, nil);
}

void FZInstallCloudKitGuard(void) {
    // Public Core Data API (iOS 13+). Selectors by name: Frozio doesn't link CoreData,
    // the app already loads it via SwiftData.
    NSString *cls = @"NSPersistentStoreDescription";
    BOOL set = FZHookInstanceMethodNamed(cls, @"setCloudKitContainerOptions:", "v@:@",
                                         (IMP)fz_setCloudKitContainerOptions, &fz_origSetOptions, "cloudkit-guard.set");
    BOOL get = set && FZHookInstanceMethodNamed(cls, @"cloudKitContainerOptions", "@@:",
                                                (IMP)fz_cloudKitContainerOptions, &fz_origGetOptions, "cloudkit-guard.get");
    if (set && get) FZLog("CloudKit guard installed: SwiftData stays local-only");
    else FZLogError("CloudKit guard incomplete (set=%d get=%d)", set, get);
}
