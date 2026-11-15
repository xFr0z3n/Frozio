// A NaviMus bug, fixed (the user's report, build 43: in Library, albums and songs show the wrong covers, the same cover
// on several, changing as the list scrolls). NaviMus 1.6.1's grids reuse a cell's UIHostingController for the next
// album (Arpeggi.HostingCollectionViewCell<V>.hostingController, its rootView swapped), and its CoverArtView loads the
// cover into @State once, when it appears: a reused cell keeps the previous album's cover. When such a cell is about
// to be reused, Frozio takes its hosting controller away, so NaviMus makes a new one with a fresh CoverArtView.
// Reproduced and checked in the harness with the same shapes.
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

NSString *const FZKeyCoverReuseFix = @"fz.fix.coverReuse";
static IMP fz_origPrepareForReuse, fz_origTablePrepareForReuse, fz_origCollectionSetConfiguration, fz_origTableSetConfiguration;

// NaviMus's table lists (its UITableViewDiffableDataSources) host their rows with UIHostingConfiguration, which also
// keeps a row's SwiftUI state for the next song: the configuration is cleared first, so NaviMus sets a fresh one.
// SwiftUI's own list cells are left alone.
static BOOL isSwiftUIConfiguration(id configuration);

// Each kind of reused cell once in the debug log (with its content configuration), to find the one behind the wrong
// covers in NaviMus's lists.
static void logCell(UIView *cell) {
#ifdef FROZIO_DEBUG
    static NSMutableSet *seen;
    if (!seen) seen = [NSMutableSet set];
    id configuration = [cell respondsToSelector:@selector(contentConfiguration)] ? [(id)cell contentConfiguration] : nil;
    NSString *key = [NSString stringWithFormat:@"%@ / %@", NSStringFromClass(cell.class), configuration ? NSStringFromClass([configuration class]) : @"-"];
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    NSMutableArray *ivars = [NSMutableArray array];
    unsigned count = 0;
    Ivar *list = class_copyIvarList(cell.class, &count);
    for (unsigned i = 0; i < count; i++) [ivars addObject:@(ivar_getName(list[i]))];
    free(list);
    FZLog("covers: reused %@ ivars %@ in %@", key, ivars, NSStringFromClass(cell.superview.class));
#endif
}

static void clearHostingConfiguration(UIView *cell) {
    logCell(cell);
    NSString *name = NSStringFromClass(cell.class);
    if ([name hasPrefix:@"SwiftUI."] || [name hasPrefix:@"_TtC7SwiftUI"] || [name hasPrefix:@"_TtGC7SwiftUI"]) return;
    id configuration = [cell respondsToSelector:@selector(contentConfiguration)] ? [(id)cell contentConfiguration] : nil;
    if (!isSwiftUIConfiguration(configuration)) return;
    [(id)cell setContentConfiguration:nil];
}

static void fz_prepareForReuse(UICollectionViewCell *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origPrepareForReuse)(self, _cmd);
    if (!FZEnabled(FZKeyCoverReuseFix)) return;
    clearHostingConfiguration(self);
    if (![NSStringFromClass(self.class) containsString:@"HostingCollectionViewCell"]) return;
    Ivar ivar = class_getInstanceVariable(self.class, "hostingController");
    if (!ivar) {
        static BOOL warned;
        if (!warned) { warned = YES; FZLogError("covers: %@ has no hostingController ivar; left as it is", NSStringFromClass(self.class)); }
        return;
    }
    id controller = object_getIvar(self, ivar);
    if (![controller isKindOfClass:UIViewController.class]) return;
    UIViewController *hosting = controller;
    [hosting willMoveToParentViewController:nil];
    [hosting.view removeFromSuperview];
    [hosting removeFromParentViewController];
    object_setIvarWithStrongDefault(self, ivar, nil);
#ifdef FROZIO_DEBUG
    static NSUInteger count;
    if (++count == 1 || count % 200 == 0) FZLog("covers: %lu reused cells given a fresh cover view (%@)", (unsigned long)count, NSStringFromClass(self.class));
#endif
}

// The case behind the user's screenshots (device log, build 45: NaviMus's lists are plain cells with UIHostingConfiguration,
// seen from Objective-C as UIKit._UICustomContentConfiguration): when its sort or data changes, NaviMus fills a visible
// cell again in place with another album's configuration, and SwiftUI keeps the cell's CoverArtView state, so the
// album shows the cover of the one that was there before (harness: "album 39" showing cover #0 after a re-sort).
// A SwiftUI configuration set on a cell already showing one is set after a nil, so SwiftUI builds the cover anew.
static BOOL isSwiftUIConfiguration(id configuration) {
    NSString *name = configuration ? NSStringFromClass([configuration class]) : nil;
    return [name containsString:@"CustomContentConfiguration"] || [name containsString:@"HostingConfiguration"];
}

static BOOL isNaviMusCell(UIView *cell) {
    NSString *name = NSStringFromClass(cell.class);
    return ![name hasPrefix:@"SwiftUI."] && ![name hasPrefix:@"_TtC7SwiftUI"] && ![name hasPrefix:@"_TtGC7SwiftUI"] && ![name hasPrefix:@"FZ"];
}

static BOOL resetFirst(UIView *cell, id configuration) {
    if (!FZEnabled(FZKeyCoverReuseFix) || !isNaviMusCell(cell) || !isSwiftUIConfiguration(configuration)) return NO;
    return isSwiftUIConfiguration([(id)cell contentConfiguration]);
}

static void fz_collectionSetConfiguration(UICollectionViewCell *self, SEL _cmd, id configuration) {
    if (resetFirst(self, configuration)) ((void (*)(id, SEL, id))fz_origCollectionSetConfiguration)(self, _cmd, nil);
    ((void (*)(id, SEL, id))fz_origCollectionSetConfiguration)(self, _cmd, configuration);
}

static void fz_tableSetConfiguration(UITableViewCell *self, SEL _cmd, id configuration) {
    if (resetFirst(self, configuration)) ((void (*)(id, SEL, id))fz_origTableSetConfiguration)(self, _cmd, nil);
    ((void (*)(id, SEL, id))fz_origTableSetConfiguration)(self, _cmd, configuration);
}

static void fz_tablePrepareForReuse(UITableViewCell *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origTablePrepareForReuse)(self, _cmd);
    if (FZEnabled(FZKeyCoverReuseFix)) clearHostingConfiguration(self);
}

void FZInstallCoverReuseFix(void) {
    FZHookInstanceMethod(UITableViewCell.class, @selector(prepareForReuse), "v@:", (IMP)fz_tablePrepareForReuse,
                         &fz_origTablePrepareForReuse, "covers.tablePrepareForReuse");
    FZHookInstanceMethod(UICollectionViewCell.class, @selector(setContentConfiguration:), "v@:@", (IMP)fz_collectionSetConfiguration,
                         &fz_origCollectionSetConfiguration, "covers.collectionConfiguration");
    FZHookInstanceMethod(UITableViewCell.class, @selector(setContentConfiguration:), "v@:@", (IMP)fz_tableSetConfiguration,
                         &fz_origTableSetConfiguration, "covers.tableConfiguration");
    BOOL hooked = FZHookInstanceMethod(UICollectionViewCell.class, @selector(prepareForReuse), "v@:", (IMP)fz_prepareForReuse,
                                       &fz_origPrepareForReuse, "covers.prepareForReuse");
    FZLog("covers: reuse fix %@", hooked ? @"installed" : @"NOT installed");
}
