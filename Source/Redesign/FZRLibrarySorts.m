// See FZRLibrarySorts.h.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Redesign/FZRLibrarySorts.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

NSString *const FZKeyLibrarySorts = @"fz.library.sorts";
static NSString *const kAlbumType = @"albumType";                  // NaviMus's @AppStorage key (1.6.1 strings)
static NSString *const kYearNewestFirst = @"fz.library.albums.yearNewestFirst";

static IMP fz_origChildren, fz_origRequestInit, fz_origSetURL;
static char kExtendedKey;

// AlbumListType's cases in declaration order (work/dumps/swift_dump_demangled.txt:3783), for an Int raw value.
static NSArray<NSString *> *listTypes(void) {
    return @[@"random", @"newest", @"starred", @"frequent", @"recent", @"alphabeticalByName", @"alphabeticalByArtist", @"byYear", @"byGenre"];
}

// NaviMus's stored sort as a case name, whatever its raw type turns out to be.
static NSString *storedType(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kAlbumType];
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) {
        NSInteger index = [value integerValue];
        return index >= 0 && index < (NSInteger)listTypes().count ? listTypes()[(NSUInteger)index] : nil;
    }
    return nil;
}

static void storeType(NSString *type) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id current = [defaults objectForKey:kAlbumType];
    // Kept in the raw type NaviMus already stores (a String unless it says otherwise).
    id value = [current isKindOfClass:NSNumber.class] ? @([listTypes() indexOfObject:type]) : type;
    [defaults setObject:value forKey:kAlbumType];
    FZLog("library: albums sorted by %@ (stored %@, was %@)", type, value, current);
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
        storeType(@"byYear");
    }];
    UIAction *oldest = [UIAction actionWithTitle:@"Year (oldest first)" image:nil identifier:nil handler:^(UIAction *a) {
        FZSetEnabled(kYearNewestFirst, NO);
        storeType(@"byYear");
    }];
    UIAction *favourites = [UIAction actionWithTitle:@"Favourites" image:nil identifier:nil handler:^(UIAction *a) { storeType(@"starred"); }];
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
    FZLog("library: sorts %@ (menu=%d request=%d set=%d, stored albumType %@)", menu ? @"installed" : @"NOT installed", menu, init, set,
          [NSUserDefaults.standardUserDefaults objectForKey:kAlbumType]);
}
