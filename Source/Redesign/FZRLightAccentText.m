// FZRLightAccentText: NaviMus fills its prominent pills with the accent and draws their label and icon in white: the
// selected Search filter ("Albums"), the artist page's Play. With a white or very light accent they vanish (the user's
// screenshots, builds 60/61: empty white pills). While the accent is light, whatever sits inside such a pill (a
// sibling of a capsule-shaped SwiftUI shape, within its frame) draws in difference blend: white on the light pill
// comes out dark. Nothing changes with a darker accent, and nothing outside a pill is touched.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Kit/FZRTokens.h"

static IMP fz_origLayout;
static char kMarkedKey, kLastScanKey;

static BOOL accentIsLight(void) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![FZRAccent() getRed:&r green:&g blue:&b alpha:&a]) return NO;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.75;
}

static BOOL isShape(UIView *view) { return [NSStringFromClass(view.class) containsString:@"ShapeHitTestingView"]; }
static BOOL isContent(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"DrawingView"] || [name containsString:@"ShapeHitTestingView"] || [name containsString:@"GraphicsView"];
}

static BOOL isPill(UIView *view) {
    CGSize size = view.bounds.size;
    return isShape(view) && size.height >= 28 && size.height <= 64 && size.width >= size.height * 1.5 && !view.hidden && view.alpha > 0.5;
}

static void setMarked(UIView *view, BOOL on) {
    BOOL marked = objc_getAssociatedObject(view, &kMarkedKey) != nil;
    if (on == marked) return;
    view.layer.compositingFilter = on ? @"differenceBlendMode" : nil;
    objc_setAssociatedObject(view, &kMarkedKey, on ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void scan(UIView *view, BOOL light, NSInteger depth, NSUInteger *budget) {
    if (depth > 40 || *budget == 0) return;
    NSArray<UIView *> *subs = view.subviews;
    NSMutableArray<UIView *> *pills = nil;
    if (light) {
        for (UIView *sub in subs) if (isPill(sub)) { if (!pills) pills = [NSMutableArray array]; [pills addObject:sub]; }
    }
    for (UIView *sub in subs) {
        (*budget)--;
        BOOL inside = NO;
        if (pills && !isPill(sub) && isContent(sub)) {
            for (UIView *pill in pills) {
                if (CGRectContainsRect(CGRectInset(pill.frame, -1, -1), sub.frame)) { inside = YES; break; }
            }
        }
        setMarked(sub, inside);
        scan(sub, light, depth + 1, budget);
    }
}

static void fz_layout(UIScrollView *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origLayout)(self, _cmd);
    // At most a few times a second per list: lists lay out on every frame while scrolling.
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *last = objc_getAssociatedObject(self, &kLastScanKey);
    if (last && now - last.doubleValue < 0.25) return;
    objc_setAssociatedObject(self, &kLastScanKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSUInteger budget = 4000;
    scan(self, accentIsLight(), 0, &budget);
    // SwiftUI may draw the pill a moment after the layout: once more shortly after.
    __weak UIScrollView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIScrollView *list = weakSelf;
        if (!list) return;
        NSUInteger more = 4000;
        scan(list, accentIsLight(), 0, &more);
    });
}

void FZRInstallLightAccentText(void) {
    if (!FZRRedesignActive()) return;
    BOOL ok = FZHookInstanceMethodNamed(@"SwiftUI.HostingScrollView", @"layoutSubviews", "v@:", (IMP)fz_layout, &fz_origLayout, "redesign.lightAccentPills");
    FZLog("light accent pills: %@", ok ? @"installed" : @"NOT installed");
}
