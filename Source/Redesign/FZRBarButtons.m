// Adapted from taurus/tweak/Sources/Redesigned/Player/PlayerHeader.x and Kit/SGRGlass.m @ fe3211c (GPL-3.0): the
// round glass behind top bar buttons (44 pt, size.glassCircle). See FZRBarButtons.h.
#import <objc/message.h>
#import <objc/runtime.h>
#import "Redesign/FZRBarButtons.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Kit/FZRGlass.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZLog.h"

NSString *const FZRKeyBarCircles = @"fz.redesign.bar.circles";
NSString *const FZRKeyBarWhite = @"fz.redesign.bar.white";
NSString *const FZRKeyBarBareBack = @"fz.redesign.bar.bareBack";

static char kCircleKey, kWhitenedKey;
static const CGFloat kCircle = 44;

// A colour matrix that turns whatever a layer draws white and keeps its alpha: NaviMus's SwiftUI bar items draw in
// NaviMus's own tint, which UIKit's tintColor can't reach. CAFilter is QuartzCore's, looked up at run time.
typedef struct { float m[20]; } FZColorMatrix;

static id whiteFilter(void) {
    static id filter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"CAFilter");
        SEL make = NSSelectorFromString(@"filterWithType:");
        if (![cls respondsToSelector:make]) { FZLogError("bar buttons: no CAFilter here; buttons keep NaviMus's tint"); return; }
        filter = ((id (*)(id, SEL, NSString *))objc_msgSend)(cls, make, @"colorMatrix");
        FZColorMatrix white = {{0, 0, 0, 0, 1,   0, 0, 0, 0, 1,   0, 0, 0, 0, 1,   0, 0, 0, 1, 0}};
        @try {
            [filter setValue:[NSValue valueWithBytes:&white objCType:"{CAColorMatrix=ffffffffffffffffffff}"] forKey:@"inputColorMatrix"];
        } @catch (NSException *e) {
            FZLogError("bar buttons: the colour matrix was refused (%@)", e.name);
            filter = nil;
        }
    });
    return filter;
}

static BOOL systemGlass(void) {
#ifdef FROZIO_HARNESS
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessMaterialBars"]) return NO;
#endif
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

static BOOL isItem(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name isEqualToString:@"_UIButtonBarButton"] || [name isEqualToString:@"_UITAMICAdaptorView"];
}

static void collectItems(UIView *view, NSUInteger depth, NSMutableArray<UIView *> *items) {
    if (depth > 6 || view.hidden) return;
    if (isItem(view) && view.bounds.size.width > 4) { [items addObject:view]; return; }
    for (UIView *sub in view.subviews) collectItems(sub, depth + 1, items);
}

// Where the button's glyph is: the centre of its image views (the back chevron), else of the button.
static CGPoint glyphCentre(UIView *item) {
    CGRect box = CGRectNull;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:item.subviews];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view.hidden || view.alpha < 0.01) continue;
        if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image && view.bounds.size.width >= 6) {
            box = CGRectUnion(box, [view convertRect:view.bounds toView:item]);
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return CGRectIsNull(box) ? CGPointMake(CGRectGetMidX(item.bounds), CGRectGetMidY(item.bounds)) : CGPointMake(CGRectGetMidX(box), CGRectGetMidY(box));
}

static BOOL isFrozioBar(UINavigationBar *bar) {
    id delegate = bar.delegate;
    UIViewController *top = [delegate isKindOfClass:UINavigationController.class] ? ((UINavigationController *)delegate).topViewController : nil;
    return [NSStringFromClass(top.class) hasPrefix:@"FZ"];
}

void FZRStyleBarButtons(UINavigationBar *bar) {
    if (!FZRRedesignActive() || !bar.window || isFrozioBar(bar)) return;
    BOOL circles = FZEnabled(FZRKeyBarCircles) && !systemGlass();
    BOOL white = FZEnabled(FZRKeyBarWhite);
    UINavigationItemBackButtonDisplayMode mode = FZEnabled(FZRKeyBarBareBack) ? UINavigationItemBackButtonDisplayModeMinimal
                                                                             : UINavigationItemBackButtonDisplayModeDefault;
    if (bar.topItem && bar.topItem.backButtonDisplayMode != mode) bar.topItem.backButtonDisplayMode = mode;

    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *sub in bar.subviews) collectItems(sub, 0, items);
    id filter = white ? whiteFilter() : nil;
    // With circles, the buttons sit as chroma.pw's: 16 pt from the bar's sides, 8 pt apart (UIKit packs them tight
    // and puts back's chevron 8 pt in, where its circle would leave the screen).
    NSMutableArray<UIView *> *leading = [NSMutableArray array], *trailing = [NSMutableArray array];
    CGFloat width = bar.bounds.size.width;
    for (UIView *item in items) {
        item.transform = CGAffineTransformIdentity;
        CGPoint centre = [item convertPoint:glyphCentre(item) toView:bar];
        [(centre.x < width / 2 ? leading : trailing) addObject:item];
    }
    NSComparator byX = ^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = [a convertPoint:glyphCentre(a) toView:bar].x, bx = [b convertPoint:glyphCentre(b) toView:bar].x;
        return ax < bx ? NSOrderedAscending : ax > bx ? NSOrderedDescending : NSOrderedSame;
    };
    [leading sortUsingComparator:byX];
    [trailing sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { return byX(b, a); }];
    for (UIView *item in items) {
        UIView *glass = objc_getAssociatedObject(item, &kCircleKey);
        if (circles) {
            // A circle for a glyph, a capsule for a word ("Edit").
            CGFloat side = MAX(kCircle, item.bounds.size.width > 60 ? item.bounds.size.width + 12 : kCircle);
            glass = FZRGlassCapsuleInside(item, &kCircleKey, CGSizeMake(side, kCircle), NO);
            glass.layer.borderWidth = 1;   // chroma.pw on iOS 17: a faint ring around the material
            glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
            glass.layer.cornerRadius = kCircle / 2;
            CGPoint centre = glyphCentre(item);
            if (!CGPointEqualToPoint(glass.center, centre)) glass.center = centre;
            item.clipsToBounds = NO;
            NSUInteger index = [leading indexOfObject:item];
            BOOL lead = index != NSNotFound;
            if (!lead) index = [trailing indexOfObject:item];
            CGFloat half = side / 2;
            CGFloat target = lead ? 16 + half + index * (kCircle + 8) : width - 16 - half - index * (kCircle + 8);
            CGFloat now = [item convertPoint:centre toView:bar].x;
            if (fabs(target - now) > 0.5) item.transform = CGAffineTransformMakeTranslation(round(target - now), 0);
        } else if (glass) {
            glass.hidden = YES;
        }
        // White: every layer of the button but the glass.
        NSArray *filters = filter ? @[filter] : nil;
        for (UIView *sub in item.subviews) {
            if (sub == glass) continue;
            if (filters ? sub.layer.filters.count == 0 : objc_getAssociatedObject(sub, &kWhitenedKey) != nil) {
                sub.layer.filters = filters;
                objc_setAssociatedObject(sub, &kWhitenedKey, filters ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}
