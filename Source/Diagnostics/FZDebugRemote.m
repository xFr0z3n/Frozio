// FZDebugRemote: a debug-build-only HTTP control port for driving Frozio on the user's iPhone from the Mac
// over the USB CoreDevice tunnel (scripts/fzr). Screenshots, taps and drags, the view and accessibility
// trees, view controllers, the log, Frozio's defaults and ObjC runtime introspection of NaviMus.
//
// Compiled into FROZIO_DEBUG builds only, and it listens only when the app was launched with
// `-FZRemoteToken <token>` (devicectl passes it); every request must carry `t=<token>`. A normal launch
// from the home screen never opens the port.
#ifdef FROZIO_DEBUG
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <MediaPlayer/MediaPlayer.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <signal.h>
#import <fcntl.h>
#import <sys/ucontext.h>
#import "Core/FZLog.h"
#import "Redesign/FZRTap.h"
#import "Diagnostics/FZDebugRemote.h"
#import "Core/FZRemote.h"
#import "Prefs/FZSettings.h"
#import "Redesign/Player/FZRQueue.h"

static const uint16_t kPort = 7357;
static NSString *sToken;
static int sListen = -1;
static dispatch_source_t sAcceptSource;
static dispatch_queue_t sQueue;

#pragma mark - helpers

static NSArray<UIWindow *> *allWindows(void) {
    NSMutableArray *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    [windows sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        return a.windowLevel < b.windowLevel ? NSOrderedAscending : a.windowLevel > b.windowLevel ? NSOrderedDescending : NSOrderedSame;
    }];
    return windows;
}

static UIWindow *keyWindow(void) {
    for (UIWindow *w in allWindows().reverseObjectEnumerator) if (w.isKeyWindow) return w;
    return allWindows().firstObject;
}

/// The topmost visible window that takes a touch at `p` (screen points), the way the system picks one.
static UIWindow *windowAt(CGPoint p) {
    for (UIWindow *w in allWindows().reverseObjectEnumerator) {
        if (w.hidden || w.alpha < 0.01 || !w.userInteractionEnabled) continue;
        CGPoint local = [w convertPoint:p fromCoordinateSpace:w.screen.coordinateSpace];
        if ([w hitTest:local withEvent:nil]) return w;
    }
    return keyWindow();
}

static NSString *rect(CGRect r) {
    return [NSString stringWithFormat:@"(%.0f,%.0f %.0fx%.0f)", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static NSString *oneLine(NSString *s) {
    if (!s.length) return nil;
    s = [[s componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    return s.length > 80 ? [[s substringToIndex:80] stringByAppendingString:@"…"] : s;
}

static NSString *controllerType(UIViewController *vc) {
    Class probe = NSClassFromString(@"FZProbe");
    SEL sel = NSSelectorFromString(@"rootViewType:");
    if (probe && [probe respondsToSelector:sel]) {
        NSString *(*fn)(id, SEL, id) = (void *)[probe methodForSelector:sel];
        NSString *type = fn(probe, sel, vc);
        if (type) return [NSString stringWithFormat:@"%@ [%@]", NSStringFromClass(vc.class), type];
    }
    return NSStringFromClass(vc.class);
}

#pragma mark - trees

static void dumpView(UIView *v, NSInteger depth, NSInteger maxDepth, BOOL all, NSMutableString *out) {
    if (!all && (v.hidden || v.alpha < 0.01)) return;
    UIWindow *w = v.window;
    CGRect frame = w ? [v convertRect:v.bounds toView:nil] : v.frame;
    NSMutableString *line = [NSMutableString stringWithFormat:@"%@%@ %@", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
                             NSStringFromClass(v.class), rect(frame)];
    if (v.hidden) [line appendString:@" hidden"];
    if (v.alpha < 1) [line appendFormat:@" a=%.2f", v.alpha];
    if (!v.userInteractionEnabled) [line appendString:@" noTouch"];
    UIResponder *next = v.nextResponder;
    if ([next isKindOfClass:UIViewController.class]) [line appendFormat:@" <%@>", controllerType((UIViewController *)next)];
    NSString *label = oneLine(v.accessibilityLabel);
    if (label) [line appendFormat:@" \"%@\"", label];
    if ([v isKindOfClass:UILabel.class]) { NSString *t = oneLine(((UILabel *)v).text); if (t) [line appendFormat:@" text=\"%@\"", t]; }
    if ([v isKindOfClass:UIButton.class]) { NSString *t = oneLine(((UIButton *)v).currentTitle); if (t) [line appendFormat:@" title=\"%@\"", t]; }
    [out appendString:line]; [out appendString:@"\n"];
    if (depth >= maxDepth) return;
    for (UIView *sub in v.subviews) dumpView(sub, depth + 1, maxDepth, all, out);
}

static void dumpAX(id element, NSInteger depth, NSMutableString *out, NSInteger *count) {
    if (depth > 40 || *count > 3000) return;
    NSArray *children = nil;
    if ([element respondsToSelector:@selector(accessibilityElements)]) children = [element accessibilityElements];
    if (!children.count && [element respondsToSelector:@selector(accessibilityElementCount)]) {
        NSInteger n = [element accessibilityElementCount];
        if (n > 0 && n != NSNotFound) {
            NSMutableArray *list = [NSMutableArray array];
            for (NSInteger i = 0; i < n; i++) { id c = [element accessibilityElementAtIndex:i]; if (c) [list addObject:c]; }
            children = list;
        }
    }
    BOOL isElement = [element respondsToSelector:@selector(isAccessibilityElement)] && [element isAccessibilityElement];
    if (isElement) {
        (*count)++;
        NSString *label = oneLine([element accessibilityLabel]) ?: @"";
        NSString *value = oneLine([element accessibilityValue]);
        UIAccessibilityTraits traits = [element accessibilityTraits];
        NSMutableArray *t = [NSMutableArray array];
        if (traits & UIAccessibilityTraitButton) [t addObject:@"button"];
        if (traits & UIAccessibilityTraitSelected) [t addObject:@"selected"];
        if (traits & UIAccessibilityTraitHeader) [t addObject:@"header"];
        if (traits & UIAccessibilityTraitStaticText) [t addObject:@"text"];
        if (traits & UIAccessibilityTraitImage) [t addObject:@"image"];
        if (traits & UIAccessibilityTraitAdjustable) [t addObject:@"adjustable"];
        if (traits & UIAccessibilityTraitNotEnabled) [t addObject:@"disabled"];
        [out appendFormat:@"%@ \"%@\"%@ [%@] %@\n", rect([element accessibilityFrame]), label,
                          value ? [NSString stringWithFormat:@" =\"%@\"", value] : @"",
                          [t componentsJoinedByString:@","], NSStringFromClass([element class])];
        if (!children.count) return;
    }
    if (children.count) { for (id c in children) dumpAX(c, depth + 1, out, count); return; }
    if ([element isKindOfClass:UIView.class]) {
        UIView *v = element;
        if (v.hidden || v.alpha < 0.01) return;
        for (UIView *sub in v.subviews) dumpAX(sub, depth + 1, out, count);
    }
}

static id findAX(id el, NSString *want, NSInteger depth) {
    if (depth > 40) return nil;
    if ([el respondsToSelector:@selector(isAccessibilityElement)] && [el isAccessibilityElement] &&
        [[el accessibilityLabel] rangeOfString:want options:NSCaseInsensitiveSearch].location != NSNotFound) return el;
    NSArray *children = [el respondsToSelector:@selector(accessibilityElements)] ? [el accessibilityElements] : nil;
    if (children.count) { for (id c in children) { id f = findAX(c, want, depth + 1); if (f) return f; } return nil; }
    if ([el isKindOfClass:UIView.class]) {
        for (UIView *s in ((UIView *)el).subviews) { if (s.hidden) continue; id f = findAX(s, want, depth + 1); if (f) return f; }
    }
    return nil;
}

static void dumpVC(UIViewController *vc, NSInteger depth, NSMutableString *out) {
    if (!vc) return;
    [out appendFormat:@"%@%@ %@%@\n", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], controllerType(vc),
                      vc.isViewLoaded ? rect([vc.view convertRect:vc.view.bounds toView:nil]) : @"(not loaded)",
                      vc.title.length ? [NSString stringWithFormat:@" title=\"%@\"", vc.title] : @""];
    for (UIViewController *child in vc.childViewControllers) dumpVC(child, depth + 1, out);
    if (vc.presentedViewController && vc.presentedViewController.presentingViewController == vc) {
        [out appendFormat:@"%@presents:\n", [@"" stringByPaddingToLength:depth * 2 + 2 withString:@" " startingAtIndex:0]];
        dumpVC(vc.presentedViewController, depth + 2, out);
    }
}

#pragma mark - runtime

static NSString *describeClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) return [NSString stringWithFormat:@"no class %@\n", name];
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"chain:"];
    for (Class c = cls; c; c = class_getSuperclass(c)) [out appendFormat:@" %@", NSStringFromClass(c)];
    [out appendString:@"\n"];
    unsigned n = 0;
    Ivar *ivars = class_copyIvarList(cls, &n);
    for (unsigned i = 0; i < n; i++) [out appendFormat:@"ivar %s %s\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: ""];
    free(ivars);
    objc_property_t *props = class_copyPropertyList(cls, &n);
    for (unsigned i = 0; i < n; i++) [out appendFormat:@"prop %s\n", property_getName(props[i])];
    free(props);
    Method *methods = class_copyMethodList(cls, &n);
    for (unsigned i = 0; i < n; i++) [out appendFormat:@"- %@ %s\n", NSStringFromSelector(method_getName(methods[i])), method_getTypeEncoding(methods[i]) ?: ""];
    free(methods);
    methods = class_copyMethodList(object_getClass(cls), &n);
    for (unsigned i = 0; i < n; i++) [out appendFormat:@"+ %@\n", NSStringFromSelector(method_getName(methods[i]))];
    free(methods);
    return out;
}

static NSString *listClasses(NSString *filter) {
    unsigned n = 0;
    Class *classes = objc_copyClassList(&n);
    NSMutableArray *names = [NSMutableArray array];
    for (unsigned i = 0; i < n; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if (filter.length && [name rangeOfString:filter options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        [names addObject:name];
    }
    free(classes);
    [names sortUsingSelector:@selector(compare:)];
    return [[names componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

#pragma mark - HTTP

typedef struct { NSData *body; NSString *type; int status; } Reply;

static Reply text(NSString *s) { return (Reply){ [s dataUsingEncoding:NSUTF8StringEncoding], @"text/plain; charset=utf-8", 200 }; }
static Reply fail(int status, NSString *s) { return (Reply){ [s dataUsingEncoding:NSUTF8StringEncoding], @"text/plain; charset=utf-8", status }; }

static Reply json(id object) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    return d ? (Reply){ d, @"application/json", 200 } : fail(500, @"not JSON-able");
}

static id plistSafe(id v) {
    if ([v isKindOfClass:NSData.class]) return [NSString stringWithFormat:@"<data %lu bytes>", (unsigned long)((NSData *)v).length];
    if ([v isKindOfClass:NSDate.class]) return ((NSDate *)v).description;
    if ([v isKindOfClass:NSArray.class]) { NSMutableArray *a = [NSMutableArray array]; for (id x in v) [a addObject:plistSafe(x)]; return a; }
    if ([v isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        [(NSDictionary *)v enumerateKeysAndObjectsUsingBlock:^(id k, id x, BOOL *stop) { d[[k description]] = plistSafe(x); }];
        return d;
    }
    if ([v isKindOfClass:NSString.class] || [v isKindOfClass:NSNumber.class]) return v;
    return [v description] ?: @"";
}

static Reply screenshot(double scale, double quality) {
    UIWindowScene *scene = keyWindow().windowScene;
    CGRect bounds = scene.coordinateSpace.bounds;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = UIScreen.mainScreen.scale * scale;
    format.opaque = YES;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.blackColor setFill];
        UIRectFill(bounds);
        for (UIWindow *w in allWindows()) {
            if (w.hidden || w.alpha < 0.01 || w.windowScene != scene) continue;
            [w drawViewHierarchyInRect:w.frame afterScreenUpdates:NO];
        }
    }];
    return (Reply){ UIImageJPEGRepresentation(image, quality), @"image/jpeg", 200 };
}

static Reply handle(NSString *path, NSDictionary<NSString *, NSString *> *q) {
    double (^num)(NSString *, double) = ^double(NSString *key, double fallback) { return q[key] ? q[key].doubleValue : fallback; };

    if ([path isEqualToString:@"/ping"]) {
        return json(@{ @"ok": @YES, @"frozio": @FROZIO_VERSION,
                       @"state": @(UIApplication.sharedApplication.applicationState),
                       @"screen": NSStringFromCGRect(UIScreen.mainScreen.bounds) });
    }
    if ([path isEqualToString:@"/shot"]) return screenshot(num(@"scale", 0.5), num(@"q", 0.7));
    if ([path isEqualToString:@"/tree"]) {
        NSMutableString *out = [NSMutableString string];
        BOOL all = [q[@"all"] isEqualToString:@"1"];
        NSInteger depth = (NSInteger)num(@"depth", 60);
        for (UIWindow *w in allWindows()) {
            if (!all && w.hidden) continue;
            [out appendFormat:@"== window %@ level=%.0f key=%d\n", NSStringFromClass(w.class), w.windowLevel, w.isKeyWindow];
            dumpView(w, 0, depth, all, out);
        }
        return text(out);
    }
    if ([path isEqualToString:@"/ax"]) {
        NSMutableString *out = [NSMutableString string];
        NSInteger count = 0;
        for (UIWindow *w in allWindows()) {
            if (w.hidden) continue;
            [out appendFormat:@"== window %@ level=%.0f\n", NSStringFromClass(w.class), w.windowLevel];
            dumpAX(w, 0, out, &count);
        }
        return text(out);
    }
    if ([path isEqualToString:@"/vcs"]) {
        NSMutableString *out = [NSMutableString string];
        for (UIWindow *w in allWindows()) {
            if (w.hidden) continue;
            [out appendFormat:@"== window %@ level=%.0f\n", NSStringFromClass(w.class), w.windowLevel];
            dumpVC(w.rootViewController, 0, out);
        }
        return text(out);
    }
    if ([path isEqualToString:@"/hit"]) {
        CGPoint p = CGPointMake(num(@"x", 0), num(@"y", 0));
        UIWindow *w = windowAt(p);
        UIView *v = [w hitTest:[w convertPoint:p fromCoordinateSpace:w.screen.coordinateSpace] withEvent:nil];
        NSMutableString *out = [NSMutableString stringWithFormat:@"window %@\n", NSStringFromClass(w.class)];
        for (; v; v = v.superview) {
            [out appendFormat:@"%@ %@%@\n", NSStringFromClass(v.class), rect([v convertRect:v.bounds toView:nil]),
                              [v.nextResponder isKindOfClass:UIViewController.class] ? [NSString stringWithFormat:@" <%@>", controllerType((UIViewController *)v.nextResponder)] : @""];
        }
        return text(out);
    }
    if ([path isEqualToString:@"/tap"]) {
        CGPoint p = CGPointMake(num(@"x", 0), num(@"y", 0));
        UIWindow *w = windowAt(p);
        CGPoint local = [w convertPoint:p fromCoordinateSpace:w.screen.coordinateSpace];
        BOOL ok = FZRTapHeld(w, local, num(@"hold", 0.08));
        return text(ok ? [NSString stringWithFormat:@"tapped %@ in %@\n", NSStringFromCGPoint(p), NSStringFromClass(w.class)] : @"tap failed\n");
    }
    if ([path isEqualToString:@"/drag"]) {
        CGPoint a = CGPointMake(num(@"x1", 0), num(@"y1", 0)), b = CGPointMake(num(@"x2", 0), num(@"y2", 0));
        UIWindow *w = windowAt(a);
        id<UICoordinateSpace> space = w.screen.coordinateSpace;
        BOOL ok = FZRDrag(w, [w convertPoint:a fromCoordinateSpace:space], [w convertPoint:b fromCoordinateSpace:space], num(@"dur", 0.3));
        return text(ok ? @"dragging\n" : @"drag failed\n");
    }
    if ([path isEqualToString:@"/press"]) {
        // Accessibility-activate the first element whose label matches (case-insensitive substring).
        NSString *want = q[@"label"];
        if (!want.length) return fail(400, @"label=");
        id found = nil;
        for (UIWindow *w in allWindows().reverseObjectEnumerator) if (!w.hidden && !found) found = findAX(w, want, 0);
        if (!found) return fail(404, @"no such element\n");
        BOOL ok = [found accessibilityActivate];
        return text([NSString stringWithFormat:@"%@ \"%@\" activate=%d frame=%@\n", NSStringFromClass([found class]),
                                               [found accessibilityLabel], ok, rect([found accessibilityFrame])]);
    }
    if ([path isEqualToString:@"/log"]) {
        NSString *log = [NSString stringWithContentsOfFile:FZLogFilePath() encoding:NSUTF8StringEncoding error:nil] ?: @"";
        NSArray *lines = [log componentsSeparatedByString:@"\n"];
        NSInteger tail = (NSInteger)num(@"tail", 200);
        if ((NSInteger)lines.count > tail) lines = [lines subarrayWithRange:NSMakeRange(lines.count - tail, tail)];
        NSString *grep = q[@"grep"];
        if (grep.length) lines = [lines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF CONTAINS[c] %@", grep]];
        return text([lines componentsJoinedByString:@"\n"]);
    }
    if ([path isEqualToString:@"/logclear"]) {
        [@"" writeToFile:FZLogFilePath() atomically:NO encoding:NSUTF8StringEncoding error:nil];
        return text(@"cleared\n");
    }
    if ([path isEqualToString:@"/defaults"]) {
        NSString *prefix = q[@"prefix"] ?: @"fz";
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        NSUserDefaults *store = [q[@"std"] isEqualToString:@"1"] ? NSUserDefaults.standardUserDefaults : [FZSettings defaults];
        [store.dictionaryRepresentation enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
            if (!prefix.length || [k hasPrefix:prefix]) out[k] = plistSafe(v);
        }];
        return json(out);
    }
    if ([path isEqualToString:@"/set"]) {
        NSString *key = q[@"k"], *value = q[@"v"], *kind = q[@"type"] ?: @"string";
        if (!key.length) return fail(400, @"k= v= type=bool|int|double|string|delete");
        NSUserDefaults *d = [q[@"std"] isEqualToString:@"1"] ? NSUserDefaults.standardUserDefaults : [FZSettings defaults];
        if ([kind isEqualToString:@"delete"]) [d removeObjectForKey:key];
        else if ([kind isEqualToString:@"bool"]) [d setBool:value.boolValue forKey:key];
        else if ([kind isEqualToString:@"int"]) [d setInteger:value.integerValue forKey:key];
        else if ([kind isEqualToString:@"double"]) [d setDouble:value.doubleValue forKey:key];
        else [d setObject:value ?: @"" forKey:key];
        return text([NSString stringWithFormat:@"%@ = %@\n", key, [d objectForKey:key]]);
    }
    if ([path isEqualToString:@"/nowplaying"]) {
        NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo ?: @{};
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [info enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { if (![v isKindOfClass:MPMediaItemArtwork.class]) out[[k description]] = plistSafe(v); }];
        out[@"_playbackState"] = @(MPNowPlayingInfoCenter.defaultCenter.playbackState);
        return json(out);
    }
    if ([path isEqualToString:@"/cmd"]) {
        MPRemoteCommandCenter *c = MPRemoteCommandCenter.sharedCommandCenter;
        NSDictionary *commands = @{ @"play": c.playCommand, @"pause": c.pauseCommand, @"toggle": c.togglePlayPauseCommand,
                                    @"next": c.nextTrackCommand, @"previous": c.previousTrackCommand };
        MPRemoteCommand *command = commands[q[@"name"] ?: @""];
        if (!command) return fail(400, @"name=play|pause|toggle|next|previous\n");
        return text([NSString stringWithFormat:@"%@ sent=%d\n", q[@"name"], FZRemoteSend(command)]);
    }
    if ([path isEqualToString:@"/queue"]) {
        NSDictionary *queue = FZRNaviMusQueue() ?: @{};
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [queue enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
            if ([v isKindOfClass:NSArray.class]) {
                NSMutableArray *titles = [NSMutableArray array];
                for (id song in v) [titles addObject:[song isKindOfClass:NSDictionary.class] ? ([song[@"title"] description] ?: @"?") : [song description]];
                out[k] = titles;
            } else out[k] = plistSafe(v);
        }];
        return json(out);
    }
    if ([path isEqualToString:@"/class"]) return text(describeClass(q[@"name"] ?: @""));
    if ([path isEqualToString:@"/classes"]) return text(listClasses(q[@"filter"]));
    if ([path isEqualToString:@"/notify"]) {
        // Post a notification on NSNotificationCenter (e.g. UIApplicationDidEnterBackgroundNotification) to test handlers.
        if (!q[@"name"].length) return fail(400, @"name=");
        [NSNotificationCenter.defaultCenter postNotificationName:q[@"name"] object:nil];
        return text(@"posted\n");
    }
    return fail(404, @"ping shot tree ax vcs hit tap drag press log logclear defaults set nowplaying cmd queue class classes notify\n");
}

static NSDictionary *parseQuery(NSString *query) {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange eq = [pair rangeOfString:@"="];
        NSString *k = eq.location == NSNotFound ? pair : [pair substringToIndex:eq.location];
        NSString *v = eq.location == NSNotFound ? @"" : [pair substringFromIndex:eq.location + 1];
        k = [k stringByReplacingOccurrencesOfString:@"+" withString:@" "].stringByRemovingPercentEncoding ?: k;
        v = [v stringByReplacingOccurrencesOfString:@"+" withString:@" "].stringByRemovingPercentEncoding ?: v;
        if (k.length) q[k] = v;
    }
    return q;
}

static void writeAll(int fd, const void *bytes, size_t length) {
    const uint8_t *p = bytes;
    while (length > 0) {
        ssize_t n = write(fd, p, length);
        if (n <= 0) return;
        p += n; length -= (size_t)n;
    }
}

static void serve(int fd) {
    NSMutableData *request = [NSMutableData data];
    char buffer[4096];
    while (request.length < 65536) {
        ssize_t n = read(fd, buffer, sizeof buffer);
        if (n <= 0) break;
        [request appendBytes:buffer length:(NSUInteger)n];
        if ([request rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0, request.length)].location != NSNotFound) break;
    }
    NSString *head = [[NSString alloc] initWithData:request encoding:NSUTF8StringEncoding] ?: @"";
    NSArray *parts = [[head componentsSeparatedByString:@"\r\n"].firstObject componentsSeparatedByString:@" "];
    NSString *target = parts.count > 1 ? parts[1] : @"/";
    NSRange qm = [target rangeOfString:@"?"];
    NSString *path = qm.location == NSNotFound ? target : [target substringToIndex:qm.location];
    NSDictionary *q = parseQuery(qm.location == NSNotFound ? @"" : [target substringFromIndex:qm.location + 1]);

    // Plain __block variables: a __block struct holding objects came back dangling after dispatch_sync (device crash).
    __block NSData *body = nil;
    __block NSString *type = @"text/plain; charset=utf-8";
    __block int status = 500;
    if (![q[@"t"] isEqualToString:sToken]) {
        body = [@"token\n" dataUsingEncoding:NSUTF8StringEncoding];
        status = 403;
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            @try {
                Reply r = handle(path, q);
                body = r.body; type = r.type ?: type; status = r.status;
            } @catch (NSException *e) {
                body = [[NSString stringWithFormat:@"%@: %@\n", e.name, e.reason] dataUsingEncoding:NSUTF8StringEncoding];
            }
        });
    }
    if (!body) body = [NSData data];
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %d X\r\nContent-Type: %@\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
                        status, type, (unsigned long)body.length];
    NSData *headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
    writeAll(fd, headerData.bytes, headerData.length);
    writeAll(fd, body.bytes, body.length);
    close(fd);
}

static void stopListening(void) {
    if (sAcceptSource) { dispatch_source_cancel(sAcceptSource); sAcceptSource = nil; }
    sListen = -1;
}

static void startListening(int attempt) {
    if (sAcceptSource) return;   // already listening
    int fd = socket(AF_INET6, SOCK_STREAM, 0);
    if (fd < 0) { FZLogError("remote: socket failed (%d)", errno); return; }
    int yes = 1, no = 0;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &no, sizeof no);
    struct sockaddr_in6 addr = { .sin6_len = sizeof addr, .sin6_family = AF_INET6, .sin6_port = htons(kPort), .sin6_addr = in6addr_any };
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(fd, 8) != 0) {
        int err = errno;
        close(fd);
        if (attempt < 25) {   // the old socket closes on its source's cancel handler, a moment later
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), sQueue, ^{ startListening(attempt + 1); });
        } else {
            FZLogError("remote: bind/listen on %d failed (%d)", kPort, err);
        }
        return;
    }
    sListen = fd;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, sQueue);
    dispatch_source_set_event_handler(source, ^{
        int client = accept(fd, NULL, NULL);
        if (client < 0) return;
        int nosig = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &nosig, sizeof nosig);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ serve(client); });
    });
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    dispatch_resume(source);
    sAcceptSource = source;
    FZLog("remote: listening on port %d", kPort);
}

#pragma mark - crash catcher

// Debug builds: a crash writes its address, its offset in each image and the backtrace to
// Documents/Frozio/crash.txt (Frozio's own functions are stripped; the offsets map onto the dylib with otool).
static int sCrashFD = -1;

static void writeFrame(const char *what, void *address) {
    Dl_info info;
    char line[512];
    if (dladdr(address, &info) && info.dli_fname) {
        const char *name = strrchr(info.dli_fname, '/');
        snprintf(line, sizeof line, "%s %p %s+0x%lx %s\n", what, address, name ? name + 1 : info.dli_fname,
                 (unsigned long)((uintptr_t)address - (uintptr_t)info.dli_fbase), info.dli_sname ?: "");
    } else {
        snprintf(line, sizeof line, "%s %p ?\n", what, address);
    }
    write(sCrashFD, line, strlen(line));
}

static void crashed(int sig, siginfo_t *info, void *context) {
    if (sCrashFD >= 0) {
        char head[128];
        snprintf(head, sizeof head, "signal %d at %p\n", sig, info ? info->si_addr : NULL);
        write(sCrashFD, head, strlen(head));
        ucontext_t *uc = context;
        if (uc && uc->uc_mcontext) {
            writeFrame("pc", (void *)uc->uc_mcontext->__ss.__pc);
            writeFrame("lr", (void *)uc->uc_mcontext->__ss.__lr);
        }
        void *frames[64];
        int n = backtrace(frames, 64);
        for (int i = 0; i < n; i++) writeFrame("bt", frames[i]);
        fsync(sCrashFD);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void installCrashCatcher(void) {
    NSString *path = [FZLogFilePath().stringByDeletingLastPathComponent stringByAppendingPathComponent:@"crash.txt"];
    sCrashFD = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    struct sigaction action = {0};
    action.sa_sigaction = crashed;
    action.sa_flags = SA_SIGINFO;
    for (int sig = SIGILL; sig <= SIGSYS; sig++) {
        if (sig == SIGKILL || sig == SIGSTOP || sig == SIGPIPE || sig == SIGALRM) continue;
        if (sig == SIGSEGV || sig == SIGBUS || sig == SIGABRT || sig == SIGILL || sig == SIGFPE || sig == SIGTRAP) sigaction(sig, &action, NULL);
    }
}

void FZInstallDebugRemote(void) {
    installCrashCatcher();
    sToken = [NSUserDefaults.standardUserDefaults stringForKey:@"FZRemoteToken"];
    if (sToken.length < 8) return; // only when launched with -FZRemoteToken <token>
    sQueue = dispatch_queue_create("com.frozio.remote", DISPATCH_QUEUE_SERIAL);
    dispatch_async(sQueue, ^{ startListening(0); });
    // iOS reclaims a suspended app's sockets: close on the way out, listen afresh when the app is back.
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) { dispatch_async(sQueue, ^{ stopListening(); }); }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) { dispatch_async(sQueue, ^{ startListening(0); }); }];
}
#endif
