#import "FZVersionGate.h"
#import "FZLog.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>

typedef struct {
    const char *shortVersion; // CFBundleShortVersionString
    const char *build;        // CFBundleVersion
    const char *uuid;         // LC_UUID of the main executable
} FZKnownBuild;

// Verified in Phase 0: `ipsw macho info` cmd 010 and Info.plist (docs/CLASSES.md).
static const FZKnownBuild kFZKnownBuilds[] = {
    { "1.6.1", "173", "EF406BF6-6FAE-3B23-BA21-963FFBF19DB8" },
};

static NSString *FZMainExecutableUUID(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (!mh || mh->magic != MH_MAGIC_64 || mh->filetype != MH_EXECUTE) continue;
        const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
        const uint8_t *cmd = (const uint8_t *)(h + 1);
        for (uint32_t c = 0; c < h->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cmd;
            if (lc->cmdsize < sizeof(struct load_command)) return nil; // malformed: refuse
            if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
                const struct uuid_command *u = (const struct uuid_command *)lc;
                return [[[NSUUID alloc] initWithUUIDBytes:u->uuid] UUIDString];
            }
            cmd += lc->cmdsize;
        }
        return nil;
    }
    return nil;
}

BOOL FZVersionGatePassed(void) {
    static BOOL passed = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        id shortV = info[@"CFBundleShortVersionString"];
        id build  = info[@"CFBundleVersion"];
        NSString *sv = [shortV isKindOfClass:NSString.class] ? shortV : nil;
        NSString *bv = [build isKindOfClass:NSString.class] ? build : nil;
        NSString *uuid = FZMainExecutableUUID();

        for (size_t i = 0; i < sizeof(kFZKnownBuilds) / sizeof(kFZKnownBuilds[0]); i++) {
            const FZKnownBuild *k = &kFZKnownBuilds[i];
            if (sv && bv && uuid &&
                strcmp(sv.UTF8String, k->shortVersion) == 0 &&
                strcmp(bv.UTF8String, k->build) == 0 &&
                [uuid caseInsensitiveCompare:@(k->uuid)] == NSOrderedSame) {
                passed = YES;
                break;
            }
        }
        if (passed) {
            FZLog("version gate PASS: %@ (%@) uuid %@ bundle %@",
                  sv, bv, uuid, NSBundle.mainBundle.bundleIdentifier);
        } else {
            FZLogError("version gate FAIL: %@ (%@) uuid %@ bundle %@ -- installing no hooks",
                       sv ?: @"?", bv ?: @"?", uuid ?: @"?", NSBundle.mainBundle.bundleIdentifier);
        }
    });
    return passed;
}
