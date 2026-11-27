// FZPausedStatus: NaviMus's "Report playback" (OpenSubsonic reportPlayback) tells the server "paused" and the
// server keeps showing the song as paused for as long as it likes (the user's Discord RPC plugin on Navidrome then
// shows a running "paused for" timer). After the chosen time paused, Frozio tells the server "stopped" once, from
// NaviMus's own last paused report with only the state changed, and holds back NaviMus's later paused reports for
// that song until it plays again.
//
// The "stopped" report goes out through a background URL session with an earliest start date, so it's sent on
// time even while the app is suspended (iOS suspends a paused music app within seconds of leaving it). Playing
// again cancels it.
#import <UIKit/UIKit.h>
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import "Prefs/FZSettings.h"
#import "Fixes/FZPausedStatus.h"

NSString *const FZKeyPausedStatus = @"fz.playback.pausedStatusClear";   // index into FZPausedStatusChoices
static NSString *const kMarker = @"FZPausedStatusOwn";
static NSString *const kSessionID = @"com.frozio.pausedStatus";

static IMP fz_origResume;
static NSURLSessionTask *sPending;     // the scheduled "stopped" report
static NSString *sPausedMedia;         // the paused song a "stopped" report is scheduled or sent for
static NSDate *sStopAt;                // when that report goes out
static NSObject *sLock;

NSArray<NSString *> *FZPausedStatusChoices(void) { return @[@"Never", @"1 minute", @"2 minutes", @"5 minutes", @"10 minutes"]; }

static NSTimeInterval timeout(void) {
    static const NSTimeInterval seconds[] = {0, 60, 120, 300, 600};
    NSInteger i = [[FZSettings defaults] integerForKey:FZKeyPausedStatus];
    return i >= 0 && i < 5 ? seconds[i] : 120;
}

static NSURLSession *backgroundSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:kSessionID];
        config.discretionary = NO;
        config.sessionSendsLaunchEvents = NO;
        session = [NSURLSession sessionWithConfiguration:config];
    });
    return session;
}

// The request's parameters, from its query or (POST) its form body.
static NSDictionary<NSString *, NSString *> *parameters(NSURLRequest *request) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO].queryItems) {
        if (item.value) out[item.name] = item.value;
    }
    if (request.HTTPBody.length) {
        NSURLComponents *body = [NSURLComponents new];
        body.percentEncodedQuery = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        for (NSURLQueryItem *item in body.queryItems) if (item.value) out[item.name] = item.value;
    }
    return out;
}

static NSString *replacingState(NSString *query, NSString *state) {
    NSURLComponents *parts = [NSURLComponents new];
    parts.percentEncodedQuery = query;
    NSMutableArray *items = [NSMutableArray array];
    for (NSURLQueryItem *item in parts.queryItems) {
        [items addObject:[item.name isEqualToString:@"state"] ? [NSURLQueryItem queryItemWithName:@"state" value:state] : item];
    }
    parts.queryItems = items;
    return parts.percentEncodedQuery;
}

static void cancelPending(void) {
    NSURLSessionTask *task = sPending;
    sPending = nil;
    if (task) { [task cancel]; FZLog("paused status: scheduled \"stopped\" cancelled"); }
}

static void schedule(NSURLRequest *paused, NSString *media) {
    cancelPending();
    NSTimeInterval after = timeout();
    if (after <= 0) return;
    NSURLComponents *url = [NSURLComponents componentsWithURL:paused.URL resolvingAgainstBaseURL:NO];
    if (url.percentEncodedQuery) url.percentEncodedQuery = replacingState(url.percentEncodedQuery, @"stopped");
    NSMutableURLRequest *stopped = [NSMutableURLRequest requestWithURL:url.URL];
    stopped.HTTPMethod = paused.HTTPMethod ?: @"GET";
    [paused.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        if (![k.lowercaseString isEqualToString:@"content-length"]) [stopped setValue:v forHTTPHeaderField:k];
    }];
    [NSURLProtocol setProperty:@YES forKey:kMarker inRequest:stopped];
    NSURLSessionTask *task;
    if (paused.HTTPBody.length) {
        NSString *body = replacingState([[NSString alloc] initWithData:paused.HTTPBody encoding:NSUTF8StringEncoding], @"stopped");
        NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frozio-stopped-report"];
        [[body dataUsingEncoding:NSUTF8StringEncoding] writeToFile:file atomically:YES];
        task = [backgroundSession() uploadTaskWithRequest:stopped fromFile:[NSURL fileURLWithPath:file]];
    } else {
        task = [backgroundSession() downloadTaskWithRequest:stopped];
    }
    task.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:after];
    sPending = task;
    @synchronized (sLock) { sPausedMedia = media; sStopAt = task.earliestBeginDate; }
    [task resume];
    FZLog("paused status: \"stopped\" scheduled in %.0f s for %@", after, media);
}

static void fz_resume(NSURLSessionTask *self, SEL _cmd) {
    NSURLRequest *request = self.originalRequest;
    if ([request.URL.path containsString:@"/rest/reportPlayback"] && ![NSURLProtocol propertyForKey:kMarker inRequest:request]) {
        NSDictionary *p = parameters(request);
        NSString *state = [p[@"state"] lowercaseString], *media = p[@"mediaId"] ?: p[@"id"] ?: @"";
        if ([state isEqualToString:@"paused"]) {
            BOOL stopped;
            @synchronized (sLock) { stopped = [sPausedMedia isEqualToString:media] && sStopAt.timeIntervalSinceNow <= 0; }
            if (stopped) {
                // The server was told "stopped": a later "paused" (NaviMus resends on seek or relaunch) would bring
                // the song back as paused.
                FZLog("paused status: NaviMus's paused report held back (server told stopped)");
                [self cancel];
                return;
            }
            schedule(request, media);   // the wait counts from NaviMus's latest paused report
        } else if (state.length) {
            // playing / starting / stopped: NaviMus's own report goes through and nothing more is sent.
            cancelPending();
            @synchronized (sLock) { sPausedMedia = nil; sStopAt = nil; }
        }
    }
    ((void (*)(id, SEL))fz_origResume)(self, _cmd);
}

void FZInstallPausedStatus(void) {
    sLock = [NSObject new];
    // The private class that implements -resume for data tasks, as FZServer finds it.
    NSURLSessionTask *probe = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"about:blank"]];
    Class cls = nil;
    for (Class c = probe.class; c && c != NSObject.class && !cls; c = class_getSuperclass(c)) {
        unsigned count = 0;
        Method *methods = class_copyMethodList(c, &count);
        for (unsigned i = 0; i < count && !cls; i++) if (method_getName(methods[i]) == @selector(resume)) cls = c;
        free(methods);
    }
    if (!cls) { FZLogError("paused status: no -resume to hook"); return; }
    FZHookInstanceMethod(cls, @selector(resume), "v@:", (IMP)fz_resume, &fz_origResume, "pausedStatus.resume");
    // Background tasks from an earlier run that are still waiting belong to a song that may play by now.
    [backgroundSession() getAllTasksWithCompletionHandler:^(NSArray<NSURLSessionTask *> *tasks) {
        for (NSURLSessionTask *task in tasks) [task cancel];
    }];
}
