// FZRLightAccentText: NaviMus draws a selected filter (Search's "Albums", …) as a pill in the accent with white text,
// so with a white or very light accent the label vanishes (the user's screenshot, build 60: an empty white pill). In
// NaviMus's horizontal chip rows the labels then draw in difference blend: white on the light pill comes out dark,
// on the black background they stay as they were. Nothing changes with a darker accent.
#import <UIKit/UIKit.h>
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Kit/FZRTokens.h"

static IMP fz_origLayout;

static BOOL accentIsLight(void) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![FZRAccent() getRed:&r green:&g blue:&b alpha:&a]) return NO;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.75;
}

static void markLabels(UIView *view, BOOL on, NSInteger depth) {
    if (depth > 4) return;
    for (UIView *sub in view.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"DrawingView"]) {
            id want = on ? @"differenceBlendMode" : nil;
            if (sub.layer.compositingFilter != want && ![sub.layer.compositingFilter isEqual:want]) sub.layer.compositingFilter = want;
        }
        markLabels(sub, on, depth + 1);
    }
}

static void fz_layout(UIScrollView *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origLayout)(self, _cmd);
    // A row of chips: short, scrolling sideways.
    if (self.bounds.size.height > 56 || self.contentSize.width <= self.bounds.size.width + 1) return;
    markLabels(self, accentIsLight(), 0);
}

void FZRInstallLightAccentText(void) {
    if (!FZRRedesignActive()) return;
    BOOL ok = FZHookInstanceMethodNamed(@"SwiftUI.HostingScrollView", @"layoutSubviews", "v@:", (IMP)fz_layout, &fz_origLayout, "redesign.lightAccentChips");
    FZLog("light accent chips: %@", ok ? @"installed" : @"NOT installed");
}
