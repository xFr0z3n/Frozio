// See FZRQueue.h.
#import <objc/message.h>
#import "Redesign/Player/FZRQueue.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

NSNotificationName const FZRQueueDidChangeNotification = @"fz.redesign.queueDidChange";

static __weak id sManager;
static IMP fz_origItemChanged, fz_origRoute, fz_origFinished, fz_origAddObserver;
static Class sManagerClass;

static void remember(id manager, const char *how) {
    if (!manager || manager == sManager) return;
    sManager = manager;
    FZLog("queue: NaviMus's AudioManager found (%s)", how);
}

static void changed(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:FZRQueueDidChangeNotification object:nil];
    });
}

static void fz_itemChanged(id self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origItemChanged)(self, _cmd);
    remember(self, "handleItemChanged");
    changed();
}

static void fz_route(id self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origRoute)(self, _cmd);
    remember(self, "updateCurrentRoute");
}

static void fz_finished(id self, SEL _cmd, id note) {
    ((void (*)(id, SEL, id))fz_origFinished)(self, _cmd, note);
    remember(self, "playerDidFinishPlaying");
    changed();
}

// Swift calls AudioManager's own methods directly, so the hooks above never ran on device (build 43). It registers
// for notifications when it starts, through NSNotificationCenter: the observer is the AudioManager itself.
static void fz_addObserver(NSNotificationCenter *self, SEL _cmd, id observer, SEL selector, NSNotificationName name, id object) {
    ((void (*)(id, SEL, id, SEL, NSNotificationName, id))fz_origAddObserver)(self, _cmd, observer, selector, name, object);
    if (sManagerClass && observer && [observer isKindOfClass:sManagerClass]) remember(observer, "addObserver");
}

NSDictionary<NSString *, id> *FZRNaviMusQueue(void) {
    id manager = sManager;
    Class bridge = NSClassFromString(@"FZNaviMus");
    SEL sel = NSSelectorFromString(@"queue:");
    if (!manager || ![bridge respondsToSelector:sel]) return nil;
    NSDictionary *raw = ((NSDictionary *(*)(id, SEL, id))objc_msgSend)(bridge, sel, manager);
    NSMutableDictionary *queue = [NSMutableDictionary dictionary];
    NSDictionary *names = @{@"_currentQueueItem": @"current", @"_primaryQueue": @"next", @"_secondaryQueue": @"context",
                            @"_continuousQueue": @"autoplay", @"_queueHistory": @"history"};
    [raw enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (names[key]) queue[names[key]] = value;
    }];
#ifdef FROZIO_DEBUG
    static NSString *logged;
    NSString *summary = [NSString stringWithFormat:@"next %lu, context %lu, autoplay %lu, history %lu, current %@",
                         (unsigned long)[queue[@"next"] count], (unsigned long)[queue[@"context"] count], (unsigned long)[queue[@"autoplay"] count],
                         (unsigned long)[queue[@"history"] count], queue[@"current"][@"title"] ?: @"-"];
    if (![summary isEqualToString:logged]) { FZLog("queue: %@", summary); logged = summary; }
#endif
    return queue;
}

void FZRInstallQueue(void) {
    NSString *name = @"_TtC7Arpeggi12AudioManager";
    BOOL item = FZHookInstanceMethodNamed(name, @"handleItemChanged", "v@:", (IMP)fz_itemChanged, &fz_origItemChanged, "queue.itemChanged");
    BOOL route = FZHookInstanceMethodNamed(name, @"updateCurrentRoute", "v@:", (IMP)fz_route, &fz_origRoute, "queue.route");
    BOOL finished = FZHookInstanceMethodNamed(name, @"playerDidFinishPlaying:", "v@:@", (IMP)fz_finished, &fz_origFinished, "queue.finished");
    sManagerClass = NSClassFromString(name);
    BOOL observe = sManagerClass && FZHookInstanceMethod(NSNotificationCenter.class, @selector(addObserver:selector:name:object:), "v@:@:@@",
                                                         (IMP)fz_addObserver, &fz_origAddObserver, "queue.addObserver");
    FZLog("queue: hooks %d/%d/%d/%d", item, route, finished, observe);
}
