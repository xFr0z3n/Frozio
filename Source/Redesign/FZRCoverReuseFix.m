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
static IMP fz_origPrepareForReuse, fz_origTablePrepareForReuse;

// NaviMus's table lists (its UITableViewDiffableDataSources) host their rows with UIHostingConfiguration, which also
// keeps a row's SwiftUI state for the next song: the configuration is cleared first, so NaviMus sets a fresh one.
// SwiftUI's own list cells are left alone.
static void clearHostingConfiguration(UIView *cell) {
    NSString *name = NSStringFromClass(cell.class);
    if ([name hasPrefix:@"SwiftUI."] || [name hasPrefix:@"_TtC7SwiftUI"] || [name hasPrefix:@"_TtGC7SwiftUI"]) return;
    id configuration = [cell respondsToSelector:@selector(contentConfiguration)] ? [(id)cell contentConfiguration] : nil;
    if (!configuration || ![NSStringFromClass([configuration class]) containsString:@"HostingConfiguration"]) return;
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

static void fz_tablePrepareForReuse(UITableViewCell *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origTablePrepareForReuse)(self, _cmd);
    if (FZEnabled(FZKeyCoverReuseFix)) clearHostingConfiguration(self);
}

void FZInstallCoverReuseFix(void) {
    FZHookInstanceMethod(UITableViewCell.class, @selector(prepareForReuse), "v@:", (IMP)fz_tablePrepareForReuse,
                         &fz_origTablePrepareForReuse, "covers.tablePrepareForReuse");
    BOOL hooked = FZHookInstanceMethod(UICollectionViewCell.class, @selector(prepareForReuse), "v@:", (IMP)fz_prepareForReuse,
                                       &fz_origPrepareForReuse, "covers.prepareForReuse");
    FZLog("covers: reuse fix %@", hooked ? @"installed" : @"NOT installed");
}
