// See FZRLibrarySorts.h.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Redesign/FZRLibrarySorts.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

NSString *const FZKeyLibrarySorts = @"fz.library.sorts";
static NSString *const kYearNewestFirst = @"fz.library.albums.yearNewestFirst";
static NSString *const kLearnedKey = @"fz.library.albums.storageKey";   // NaviMus's own key, once seen

static IMP fz_origChildren, fz_origRequestInit, fz_origSetURL, fz_origSetObject;
static char kExtendedKey;

// AlbumListType's cases in declaration order (work/dumps/swift_dump_demangled.txt:3783), for an Int raw value.
static NSArray<NSString *> *listTypes(void) {
    return @[@"random", @"newest", @"starred", @"frequent", @"recent", @"alphabeticalByName", @"alphabeticalByArtist", @"byYear", @"byGenre"];
}

static BOOL isListType(id value) {
    return [value isKindOfClass:NSString.class] && [listTypes() containsObject:value];
}

// The key NaviMus's @AppStorage keeps the album sort under. It isn't "albumType" (device log, build 41: nothing
// there), and Swift keeps short key literals inside its code, so Frozio learns it: the standard defaults key whose
// value NaviMus sets to one of AlbumListType's cases (fz_setObject), or, at launch, the one key holding one.
static NSString *albumKey(void) {
    return [NSUserDefaults.standardUserDefaults stringForKey:kLearnedKey];
}

static void learnKey(NSString *key, NSString *how) {
    if (!key.length || [key hasPrefix:@"fz."] || [key isEqualToString:[NSUserDefaults.standardUserDefaults stringForKey:kLearnedKey]]) return;
    [NSUserDefaults.standardUserDefaults setObject:key forKey:kLearnedKey];
    FZLog("library: NaviMus keeps its album sort under \"%@\" (%@)", key, how);
}

static void learnAtLaunch(void) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    [NSUserDefaults.standardUserDefaults.dictionaryRepresentation enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (isListType(value) && ![key hasPrefix:@"fz."]) [keys addObject:key];
    }];
    FZLog("library: standard defaults keys holding an album list type: %@", keys);
    if (keys.count == 1) { learnKey(keys.firstObject, @"found at launch"); return; }
    // A key learned before that holds nothing now is NaviMus's no longer: forget it until NaviMus sets its own again.
    NSString *learned = albumKey();
    if (learned && ![NSUserDefaults.standardUserDefaults objectForKey:learned]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kLearnedKey];
        FZLog("library: forgot the album sort key %@ (nothing stored there)", learned);
    }
}

// NaviMus's stored sort as a case name, whatever its raw type turns out to be.
static NSString *storedType(void) {
    NSString *key = albumKey();
    if (!key) return nil;
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) {
        NSInteger index = [value integerValue];
        return index >= 0 && index < (NSInteger)listTypes().count ? listTypes()[(NSUInteger)index] : nil;
    }
    return nil;
}

static BOOL storeType(NSString *type) {
    NSString *key = albumKey();
    if (!key) {
        FZLogError("library: NaviMus's album sort key isn't known yet; pick any of NaviMus's own sorts once first");
        return NO;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id current = [defaults objectForKey:key];
    id value = [current isKindOfClass:NSNumber.class] ? @([listTypes() indexOfObject:type]) : type;
    if ([current isEqual:value]) {
        // Already byYear (newest ↔ oldest first): the same value is no change to NaviMus, which then never reloads
        // (device log, build 42). Cleared first, then set again, it reloads with the new year range.
        [defaults removeObjectForKey:key];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
        });
        FZLog("library: albums sorted by %@ again (%@, the other direction)", type, key);
        return YES;
    }
    [defaults setObject:value forKey:key];
    FZLog("library: albums sorted by %@ (%@ = %@, was %@)", type, key, value, current);
    return YES;
}

static void tellKeyUnknown(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) window = w;
    }
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"One more step"
        message:@"Pick any of NaviMus's own sorts once (Name, for example). Frozio then knows where NaviMus keeps the sort, and Year and Favourites work from then on."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

// NaviMus's writes: @AppStorage sets the album sort through -setObject:forKey: on the standard defaults.
static void fz_setObject(NSUserDefaults *self, SEL _cmd, id value, NSString *key) {
    ((void (*)(id, SEL, id, NSString *))fz_origSetObject)(self, _cmd, value, key);
    if (self == NSUserDefaults.standardUserDefaults && isListType(value)) learnKey(key, @"seen being set");
}

static BOOL isAlbumSortMenu(NSArray<UIMenuElement *> *children) {
    NSMutableSet *titles = [NSMutableSet set];
    for (UIMenuElement *child in children) if ([child isKindOfClass:UIAction.class] && child.title) [titles addObject:child.title];
    return [titles containsObject:@"Name"] && [titles containsObject:@"Recently Added"] && [titles containsObject:@"Frequently Played"]
        && [titles containsObject:@"Random"] && ![titles containsObject:@"Year (newest first)"];
}

static NSArray<UIMenuElement *> *extraAlbumSorts(void) {
    NSString *current = storedType();
    BOOL newestFirst = FZFlag(kYearNewestFirst, YES);
    UIAction *newest = [UIAction actionWithTitle:@"Year (newest first)" image:nil identifier:nil handler:^(UIAction *a) {
        FZSetEnabled(kYearNewestFirst, YES);
        if (!storeType(@"byYear")) tellKeyUnknown();
    }];
    UIAction *oldest = [UIAction actionWithTitle:@"Year (oldest first)" image:nil identifier:nil handler:^(UIAction *a) {
        FZSetEnabled(kYearNewestFirst, NO);
        if (!storeType(@"byYear")) tellKeyUnknown();
    }];
    UIAction *favourites = [UIAction actionWithTitle:@"Favourites" image:nil identifier:nil handler:^(UIAction *a) { if (!storeType(@"starred")) tellKeyUnknown(); }];
    BOOL byYear = [current isEqualToString:@"byYear"];
    newest.state = byYear && newestFirst ? UIMenuElementStateOn : UIMenuElementStateOff;
    oldest.state = byYear && !newestFirst ? UIMenuElementStateOn : UIMenuElementStateOff;
    favourites.state = [current isEqualToString:@"starred"] ? UIMenuElementStateOn : UIMenuElementStateOff;
    return @[newest, oldest, favourites];
}

// SwiftUI builds its menus' items however it likes; UIKit reads them through -children, where the extra sorts join.
static NSArray *fz_children(UIMenu *self, SEL _cmd) {
    NSArray *children = ((NSArray *(*)(id, SEL))fz_origChildren)(self, _cmd);
    if (!FZEnabled(FZKeyLibrarySorts) || !isAlbumSortMenu(children)) return children;
    NSArray *extended = objc_getAssociatedObject(self, &kExtendedKey);
    if (!extended) {
        extended = [children arrayByAddingObjectsFromArray:extraAlbumSorts()];
        objc_setAssociatedObject(self, &kExtendedKey, extended, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        FZLog("library: Year and Favourites added to NaviMus's album sort menu");
    }
    return extended;
}

#pragma mark - the request

// getAlbumList2?type=byYear without fromYear/toYear: the range goes in, newest or oldest first.
static NSURL *fixedURL(NSURL *url) {
    if (!url || (![url.path hasSuffix:@"getAlbumList2"] && ![url.path hasSuffix:@"getAlbumList2.view"])) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    BOOL byYear = NO, ranged = NO;
    for (NSURLQueryItem *item in parts.queryItems) {
        if ([item.name isEqualToString:@"type"] && [item.value isEqualToString:@"byYear"]) byYear = YES;
        if ([item.name isEqualToString:@"fromYear"] || [item.name isEqualToString:@"toYear"]) ranged = YES;
    }
    if (!byYear || ranged) return nil;
    BOOL newestFirst = FZFlag(kYearNewestFirst, YES);
    NSMutableArray *items = [NSMutableArray arrayWithArray:parts.queryItems ?: @[]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"fromYear" value:newestFirst ? @"9999" : @"0"]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"toYear" value:newestFirst ? @"0" : @"9999"]];
    parts.queryItems = items;
    return parts.URL;
}

static id fz_requestInit(NSURLRequest *self, SEL _cmd, NSURL *url, NSURLRequestCachePolicy policy, NSTimeInterval timeout) {
    NSURL *fixed = fixedURL(url);
    if (fixed) FZLog("library: year range added to NaviMus's album list request");
    return ((id (*)(id, SEL, NSURL *, NSURLRequestCachePolicy, NSTimeInterval))fz_origRequestInit)(self, _cmd, fixed ?: url, policy, timeout);
}

static void fz_setURL(NSMutableURLRequest *self, SEL _cmd, NSURL *url) {
    NSURL *fixed = fixedURL(url);
    if (fixed) FZLog("library: year range added to NaviMus's album list request (set)");
    ((void (*)(id, SEL, NSURL *))fz_origSetURL)(self, _cmd, fixed ?: url);
}

void FZInstallLibrarySorts(void) {
    BOOL menu = FZHookInstanceMethod(UIMenu.class, @selector(children), "@@:", (IMP)fz_children, &fz_origChildren, "library.sorts.menu");
    BOOL init = FZHookInstanceMethod(NSURLRequest.class, @selector(initWithURL:cachePolicy:timeoutInterval:), "@@:@Qd",
                                     (IMP)fz_requestInit, &fz_origRequestInit, "library.sorts.request");
    BOOL set = FZHookInstanceMethod(NSMutableURLRequest.class, @selector(setURL:), "v@:@", (IMP)fz_setURL, &fz_origSetURL, "library.sorts.setURL");
    BOOL learn = FZHookInstanceMethod(NSUserDefaults.class, @selector(setObject:forKey:), "v@:@@", (IMP)fz_setObject, &fz_origSetObject, "library.sorts.learn");
    learnAtLaunch();
    FZLog("library: sorts %@ (menu=%d request=%d set=%d learn=%d, key %@ = %@)", menu ? @"installed" : @"NOT installed", menu, init, set, learn,
          albumKey(), albumKey() ? [NSUserDefaults.standardUserDefaults objectForKey:albumKey()] : nil);
}
