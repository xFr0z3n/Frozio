#import "FZHook.h"
#import "FZLog.h"
#import <string.h>

BOOL FZTypesMatchNoDigits(const char *encoding, const char *expectedNoDigits) {
    if (!encoding || !expectedNoDigits) return NO;
    char buf[128]; size_t j = 0;
    for (size_t i = 0; encoding[i] && j < sizeof(buf) - 1; i++) {
        if (encoding[i] < '0' || encoding[i] > '9') buf[j++] = encoding[i];
    }
    buf[j] = 0;
    return strcmp(buf, expectedNoDigits) == 0;
}

BOOL FZHookInstanceMethod(Class cls, SEL sel, const char *types, IMP replacement, IMP *original, const char *tag) {
    if (!cls || !sel || !replacement || !original) {
        FZLogError("hook %s: bad arguments; skipped", tag);
        return NO;
    }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        FZLogError("hook %s: -[%@ %@] not found; skipped", tag, NSStringFromClass(cls), NSStringFromSelector(sel));
        return NO;
    }
    const char *enc = method_getTypeEncoding(m);
    if (!FZTypesMatchNoDigits(enc, types)) {
        FZLogError("hook %s: -[%@ %@] has types %s, expected %s; skipped",
                   tag, NSStringFromClass(cls), NSStringFromSelector(sel), enc ?: "(null)", types);
        return NO;
    }
    // Declared on cls itself? Swap in place. Inherited? Add an override on cls so the superclass is unaffected.
    if (class_addMethod(cls, sel, replacement, enc)) {
        *original = method_getImplementation(m); // the inherited implementation
    } else {
        *original = method_setImplementation(m, replacement);
    }
    FZLog("hook %s: -[%@ %@] installed", tag, NSStringFromClass(cls), NSStringFromSelector(sel));
    return YES;
}

BOOL FZHookInstanceMethodNamed(NSString *className, NSString *selector, const char *types,
                               IMP replacement, IMP *original, const char *tag) {
    Class cls = NSClassFromString(className);
    if (!cls) {
        FZLogError("hook %s: class %@ not loaded; skipped", tag, className);
        return NO;
    }
    return FZHookInstanceMethod(cls, NSSelectorFromString(selector), types, replacement, original, tag);
}
