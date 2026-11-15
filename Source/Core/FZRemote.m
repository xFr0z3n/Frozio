#import <objc/runtime.h>
#import "Core/FZRemote.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

NSNotificationName const FZNowPlayingDidChangeNotification = @"FZNowPlayingDidChangeNotification";

static IMP fz_origAddTarget, fz_origSetInfo;
static NSMapTable<MPRemoteCommand *, id> *sHandlers;   // main thread; the command's last NaviMus handler
static NSDictionary *sInfo;                              // main thread

NSDictionary *FZNowPlayingInfo(void) { return sInfo; }

NSString *FZNowPlayingSongID(void) {
    id song = sInfo[MPNowPlayingInfoPropertyExternalContentIdentifier];
    return [song isKindOfClass:NSString.class] ? song : nil;
}

BOOL FZNowPlayingIsPlaying(void) {
    NSNumber *rate = sInfo[MPNowPlayingInfoPropertyPlaybackRate];
    return sInfo && (!rate || rate.doubleValue > 0);
}

static id fz_addTargetWithHandler(MPRemoteCommand *self, SEL _cmd, MPRemoteCommandHandlerStatus (^handler)(MPRemoteCommandEvent *)) {
    id target = ((id (*)(id, SEL, id))fz_origAddTarget)(self, _cmd, handler);
    if (handler) {
        id copy = [handler copy];
        dispatch_block_t keep = ^{ [sHandlers setObject:copy forKey:self]; };
        if (NSThread.isMainThread) keep(); else dispatch_async(dispatch_get_main_queue(), keep);
    }
    return target;
}

// NaviMus's handler gets an event like the one the system sends for the lock screen's buttons.
// MPRemoteCommandEvent's -init aborts, so it comes from the factory +eventWithCommand:mediaRemoteType:options:
// (private, checked at run time with its exact types; verified on iOS 17.5.1 and 26.5), typed by the command's
// own -mediaRemoteCommandType.
static MPRemoteCommandEvent *eventFor(MPRemoteCommand *command) {
    Class eventClass = NSClassFromString(@"MPRemoteCommandEvent");
    SEL make = NSSelectorFromString(@"eventWithCommand:mediaRemoteType:options:");
    SEL typeOf = NSSelectorFromString(@"mediaRemoteCommandType");
    Method factory = eventClass ? class_getClassMethod(eventClass, make) : NULL;
    Method type = command ? class_getInstanceMethod(object_getClass(command), typeOf) : NULL;
    if (!factory || !type || !FZTypesMatchNoDigits(method_getTypeEncoding(factory), "@@:@I@")
        || !FZTypesMatchNoDigits(method_getTypeEncoding(type), "I@:")) {
        FZLogError("remote: no way to make an event here (factory=%d type=%d)", factory != NULL, type != NULL);
        return nil;
    }
    unsigned int mediaRemoteType = ((unsigned int (*)(id, SEL))method_getImplementation(type))(command, typeOf);
    return ((id (*)(Class, SEL, id, unsigned int, id))method_getImplementation(factory))(eventClass, make, command, mediaRemoteType, @{});
}

BOOL FZRemoteSend(MPRemoteCommand *command) {
    MPRemoteCommandHandlerStatus (^handler)(MPRemoteCommandEvent *) = command ? [sHandlers objectForKey:command] : nil;
    if (!handler) return NO;
    @try {
        MPRemoteCommandEvent *event = eventFor(command);
        return event && handler(event) == MPRemoteCommandHandlerStatusSuccess;
    } @catch (NSException *e) {
        FZLogError("remote: NaviMus's handler threw %@", e.name);
        return NO;
    }
}

static void fz_setNowPlayingInfo(id self, SEL _cmd, NSDictionary *info) {
    ((void (*)(id, SEL, NSDictionary *))fz_origSetInfo)(self, _cmd, info);
    NSDictionary *copy = [info copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        sInfo = copy;
        [NSNotificationCenter.defaultCenter postNotificationName:FZNowPlayingDidChangeNotification object:nil];
    });
}

void FZInstallRemote(void) {
    sHandlers = [NSMapTable weakToStrongObjectsMapTable];
    // Installed after lock screen lyrics, so it sees NaviMus's own info only: lyrics re-sends go straight to
    // the original setter.
    BOOL handlers = FZHookInstanceMethodNamed(@"MPRemoteCommand", @"addTargetWithHandler:", "@@:@?",
                                              (IMP)fz_addTargetWithHandler, &fz_origAddTarget, "remote.handlers");
    BOOL info = FZHookInstanceMethodNamed(@"MPNowPlayingInfoCenter", @"setNowPlayingInfo:", "v@:@",
                                          (IMP)fz_setNowPlayingInfo, &fz_origSetInfo, "remote.nowplaying");
    if (!handlers || !info) FZLogError("remote: hooks incomplete (handlers=%d info=%d)", handlers, info);
}
