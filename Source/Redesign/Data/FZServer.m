#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Redesign/Data/FZServer.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import <objc/runtime.h>

NSNotificationName const FZServerReadyNotification = @"FZServerReadyNotification";

static NSString *const kAuthNames[] = {@"u", @"t", @"s", @"p", @"v", @"c", @"apiKey"};

static NSObject *sLock;
static NSURL *sBase;                                   // scheme://host[:port][/prefix] before /rest/
static NSArray<NSURLQueryItem *> *sAuth;               // NaviMus's auth query items
static IMP fz_origResume;
static IMP fz_origDataTaskRequest, fz_origDataTaskRequestHandler, fz_origDataTaskURL, fz_origDataTaskURLHandler, fz_origAsset;

BOOL FZServerReady(void) {
    @synchronized (sLock) { return sBase != nil && sAuth.count > 0; }
}

// Learns the server from a NaviMus URL like https://host/rest/getAlbum.view?u=…&t=…&s=…&v=…&c=…
static void learn(NSURL *url, const char *seam) {
    if (!url) return;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSRange rest = [parts.path rangeOfString:@"/rest/"];
    if (rest.location == NSNotFound || !parts.host.length) return;
    NSMutableArray<NSURLQueryItem *> *auth = [NSMutableArray array];
    BOOL hasUser = NO, hasKey = NO;
    for (NSURLQueryItem *item in parts.queryItems) {
        for (NSUInteger i = 0; i < sizeof(kAuthNames) / sizeof(kAuthNames[0]); i++) {
            if (![item.name isEqualToString:kAuthNames[i]] || !item.value.length) continue;
            [auth addObject:item];
            if ([item.name isEqualToString:@"u"]) hasUser = YES;
            if ([item.name isEqualToString:@"t"] || [item.name isEqualToString:@"p"] || [item.name isEqualToString:@"apiKey"]) hasKey = YES;
        }
    }
    if (!hasKey || (!hasUser && ![[auth valueForKey:@"name"] containsObject:@"apiKey"])) return;
    // NaviMus streams through its own arpeggi-cache scheme; the server itself is http(s).
    NSString *scheme = [parts.scheme hasPrefix:@"https"] || [parts.scheme hasSuffix:@"https"] ? @"https" : @"http";
    if ([parts.scheme isEqualToString:@"http"] || [parts.scheme isEqualToString:@"https"]) scheme = parts.scheme;
    NSURLComponents *base = [NSURLComponents new];
    base.scheme = scheme;
    base.host = parts.host;
    base.port = parts.port;
    base.path = [parts.path substringToIndex:rest.location];
    BOOL first;
    @synchronized (sLock) {
        first = sBase == nil;
        sBase = base.URL;
        sAuth = auth;
    }
    if (first) {
        FZLog("server: NaviMus's login seen via %s", seam);
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:FZServerReadyNotification object:nil];
        });
    }
}

static id fz_dataTaskRequest(id self, SEL _cmd, NSURLRequest *request) {
    learn(request.URL, "dataTaskWithRequest:");
    return ((id (*)(id, SEL, id))fz_origDataTaskRequest)(self, _cmd, request);
}
static id fz_dataTaskRequestHandler(id self, SEL _cmd, NSURLRequest *request, id handler) {
    learn(request.URL, "dataTaskWithRequest:completionHandler:");
    return ((id (*)(id, SEL, id, id))fz_origDataTaskRequestHandler)(self, _cmd, request, handler);
}
static id fz_dataTaskURL(id self, SEL _cmd, NSURL *url) {
    learn(url, "dataTaskWithURL:");
    return ((id (*)(id, SEL, id))fz_origDataTaskURL)(self, _cmd, url);
}
static id fz_dataTaskURLHandler(id self, SEL _cmd, NSURL *url, id handler) {
    learn(url, "dataTaskWithURL:completionHandler:");
    return ((id (*)(id, SEL, id, id))fz_origDataTaskURLHandler)(self, _cmd, url, handler);
}
// Swift's async URLSession API (data(for:), which NaviMus uses) skips the dataTaskWith… methods; every
// task, however made, starts with -resume.
static void fz_resume(NSURLSessionTask *self, SEL _cmd) {
    learn(self.originalRequest.URL ?: self.currentRequest.URL, "-[NSURLSessionTask resume]");
#ifdef FROZIO_DEBUG
    NSURLRequest *r = self.originalRequest;
    NSString *path = r.URL.path;
    if ([path containsString:@"/rest/reportPlayback"] || [path containsString:@"/rest/scrobble"]) {
        NSMutableArray *q = [NSMutableArray array];
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:r.URL resolvingAgainstBaseURL:NO].queryItems) {
            if (![@[@"u", @"t", @"s", @"p", @"apiKey"] containsObject:item.name]) [q addObject:[NSString stringWithFormat:@"%@=%@", item.name, item.value]];
        }
        NSString *body = r.HTTPBody.length ? [[NSString alloc] initWithData:r.HTTPBody encoding:NSUTF8StringEncoding] : @"";
        FZLog("server: %@ %@ %@ body=%@", r.HTTPMethod, path.lastPathComponent, [q componentsJoinedByString:@"&"], body.length > 300 ? [body substringToIndex:300] : body);
    }
#endif
    ((void (*)(id, SEL))fz_origResume)(self, _cmd);
}

// The class that itself implements -resume for data tasks (a private __NSCF… class), found at run time from
// a task that's made and never started.
static Class resumeClass(void) {
    NSURLSessionTask *probe = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"about:blank"]];
    for (Class cls = probe.class; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        BOOL declares = NO;
        for (unsigned i = 0; i < count && !declares; i++) declares = method_getName(methods[i]) == @selector(resume);
        free(methods);
        if (declares) return cls;
    }
    return nil;
}

static id fz_assetInit(id self, SEL _cmd, NSURL *url, NSDictionary *options) {
    learn(url, "AVURLAsset");
    return ((id (*)(id, SEL, id, id))fz_origAsset)(self, _cmd, url, options);
}

static NSURL *requestURL(NSString *endpoint, NSDictionary<NSString *, NSString *> *parameters) {
    NSURL *base;
    NSArray *auth;
    @synchronized (sLock) { base = sBase; auth = sAuth; }
    if (!base) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithURL:base resolvingAgainstBaseURL:NO];
    url.path = [NSString stringWithFormat:@"%@/rest/%@.view", url.path ?: @"", endpoint];
    NSMutableArray<NSURLQueryItem *> *items = [auth mutableCopy];
    [items addObject:[NSURLQueryItem queryItemWithName:@"f" value:@"json"]];
    [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}

static NSURLSession *session(void) {
    static NSURLSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 20;
        s = [NSURLSession sessionWithConfiguration:config];
    });
    return s;
}

static NSError *error(NSString *message) {
    return [NSError errorWithDomain:@"FZServer" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

void FZServerGet(NSString *endpoint, NSDictionary<NSString *, NSString *> *parameters,
                 void (^completion)(NSDictionary *response, NSError *error)) {
    NSURL *url = requestURL(endpoint, parameters);
    if (!url) {
        completion(nil, error(@"NaviMus hasn't talked to the server yet"));
        return;
    }
    // Frozio's own session: its requests don't pass through the hooks above.
    [[session() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *failure) {
        NSDictionary *body = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *root = [body isKindOfClass:NSDictionary.class] ? body[@"subsonic-response"] : nil;
        NSError *problem = failure;
        if (!problem && ![root isKindOfClass:NSDictionary.class]) problem = error(@"Not a Subsonic response");
        if (!problem && ![root[@"status"] isEqual:@"ok"]) {
            id message = [root[@"error"] isKindOfClass:NSDictionary.class] ? root[@"error"][@"message"] : nil;
            problem = error([message isKindOfClass:NSString.class] ? message : @"The server refused the request");
        }
        if (problem) FZLogError("server: %@ failed: %@", endpoint, problem.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(problem ? nil : root, problem); });
    }] resume];
}

NSURL *FZServerCoverURL(NSString *coverArtID, NSInteger size) {
    if (!coverArtID.length) return nil;
    return requestURL(@"getCoverArt", @{@"id": coverArtID, @"size": @(size).stringValue});
}

void FZServerImage(NSURL *url, void (^completion)(UIImage *image)) {
    static NSCache<NSURL *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.totalCostLimit = 64 * 1024 * 1024; });
    if (!url) { completion(nil); return; }
    UIImage *hit = [cache objectForKey:url];
    if (hit) { completion(hit); return; }
    [[session() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *failure) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (image) [cache setObject:image forKey:url cost:data.length];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(image); });
    }] resume];
}

void FZInstallServer(void) {
    sLock = [NSObject new];
    // Every NSURLSession is a __NSURLSessionLocal, which implements these itself. Hooked there only: hooking
    // NSURLSession as well would chain the hook into itself.
    Class sessionClass = NSClassFromString(@"__NSURLSessionLocal") ?: NSURLSession.class;
    BOOL a = FZHookInstanceMethod(sessionClass, @selector(dataTaskWithRequest:), "@@:@", (IMP)fz_dataTaskRequest, &fz_origDataTaskRequest, "server.request");
    BOOL b = FZHookInstanceMethod(sessionClass, @selector(dataTaskWithRequest:completionHandler:), "@@:@@?", (IMP)fz_dataTaskRequestHandler, &fz_origDataTaskRequestHandler, "server.request.handler");
    BOOL c = FZHookInstanceMethod(sessionClass, @selector(dataTaskWithURL:), "@@:@", (IMP)fz_dataTaskURL, &fz_origDataTaskURL, "server.url");
    BOOL d = FZHookInstanceMethod(sessionClass, @selector(dataTaskWithURL:completionHandler:), "@@:@@?", (IMP)fz_dataTaskURLHandler, &fz_origDataTaskURLHandler, "server.url.handler");
    Class tasks = resumeClass();
    BOOL r = tasks && FZHookInstanceMethod(tasks, @selector(resume), "v@:", (IMP)fz_resume, &fz_origResume, "server.resume");
    BOOL e = FZHookInstanceMethod(AVURLAsset.class, @selector(initWithURL:options:), "@@:@@", (IMP)fz_assetInit, &fz_origAsset, "server.asset");
    FZLog("server: seams %d%d%d%d%d%d (resume on %@)", r, a, b, c, d, e, tasks ? NSStringFromClass(tasks) : @"-");
    (void)r; (void)a; (void)b; (void)c; (void)d; (void)e; // release builds compile FZLog out
}
