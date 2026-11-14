#import "FZCloudKitGuard.h"
#import "FZLog.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <string.h>

static void (*fz_origSetOptions)(id, SEL, id);

static id fz_cloudKitContainerOptions(id self, SEL _cmd) {
    return nil; // never mirror: matches the App Store build's empty iCloud container list
}

static void fz_setCloudKitContainerOptions(id self, SEL _cmd, id options) {
    if (options) FZLog("CloudKit guard: dropped cloudKitContainerOptions on %{public}@", self);
    if (fz_origSetOptions) fz_origSetOptions(self, _cmd, nil);
}

// Returns YES if `m` has exactly the expected type encoding (ignoring frame-size digits).
static BOOL FZMethodTypesMatch(Method m, const char *expectedNoDigits) {
    const char *enc = method_getTypeEncoding(m);
    if (!enc) return NO;
    char buf[64]; size_t j = 0;
    for (size_t i = 0; enc[i] && j < sizeof(buf) - 1; i++) {
        if (enc[i] < '0' || enc[i] > '9') buf[j++] = enc[i];
    }
    buf[j] = 0;
    return strcmp(buf, expectedNoDigits) == 0;
}

void FZInstallCloudKitGuard(void) {
    Class cls = NSClassFromString(@"NSPersistentStoreDescription");
    if (!cls) { FZLogError("CloudKit guard: NSPersistentStoreDescription not loaded; skipped"); return; }

    // Selectors by name: Frozio doesn't link CoreData (the app already loads it via SwiftData).
    Method getter = class_getInstanceMethod(cls, NSSelectorFromString(@"cloudKitContainerOptions"));
    Method setter = class_getInstanceMethod(cls, NSSelectorFromString(@"setCloudKitContainerOptions:"));
    if (!getter || !setter) { FZLogError("CloudKit guard: selectors missing; skipped"); return; }
    if (!FZMethodTypesMatch(getter, "@@:") || !FZMethodTypesMatch(setter, "v@:@")) {
        FZLogError("CloudKit guard: unexpected type encodings (%{public}s / %{public}s); skipped",
                   method_getTypeEncoding(getter), method_getTypeEncoding(setter));
        return;
    }

    // Replace on the class itself (the methods are declared there), so subclasses inherit the guard.
    fz_origSetOptions = (void (*)(id, SEL, id))method_setImplementation(setter, (IMP)fz_setCloudKitContainerOptions);
    method_setImplementation(getter, (IMP)fz_cloudKitContainerOptions);
    FZLog("CloudKit guard installed: SwiftData stays local-only");
}
