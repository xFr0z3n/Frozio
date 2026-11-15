// Adapted from taurus/tweak/Sources/Redesigned/Player/PlayerHeader.x and Kit/SGRGlass.m @ fe3211c (GPL-3.0): the
// round glass behind top bar buttons (44 pt, size.glassCircle). See FZRBarButtons.h.
#import <objc/message.h>
#import <objc/runtime.h>
#import "Redesign/FZRBarButtons.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Kit/FZRGlass.h"
#import "Redesign/FZRNaviMusControls.h"
#import "Redesign/Album/FZRAlbumPage.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZLog.h"

NSString *const FZRKeyCircleOthers = @"fz.redesign.circle.others";
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

// Where the button's glyph is: its image views (the back chevron), else the small views SwiftUI draws the glyph in
// (⋯ and NaviMus's other items: their glyph isn't always at the middle of the item, build 42), else the middle.
static CGPoint glyphCentre(UIView *item) {
    CGRect images = CGRectNull, leaves = CGRectNull;
    CGSize limit = item.bounds.size;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:item.subviews];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view.hidden || view.alpha < 0.01 || [view isKindOfClass:UIVisualEffectView.class]) continue;   // Frozio's glass
        if ([NSStringFromClass(view.class) rangeOfString:@"MaskView"].location != NSNotFound) continue;
        CGRect frame = [view convertRect:view.bounds toView:item];
        if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image && view.bounds.size.width >= 6) {
            images = CGRectUnion(images, frame);
        } else if (!view.subviews.count && frame.size.width >= 4 && frame.size.height >= 4
                   && frame.size.width < limit.width - 1 && frame.size.height < limit.height - 1) {
            leaves = CGRectUnion(leaves, frame);
        }
        [queue addObjectsFromArray:view.subviews];
    }
    CGRect box = !CGRectIsNull(images) ? images : leaves;
    if (CGRectIsNull(box)) return CGPointMake(CGRectGetMidX(item.bounds), CGRectGetMidY(item.bounds));
    return CGPointMake(round(CGRectGetMidX(box) * 2) / 2, round(CGRectGetMidY(box) * 2) / 2);
}

static BOOL isFrozioBar(UINavigationBar *bar) {
    id delegate = bar.delegate;
    UIViewController *top = [delegate isKindOfClass:UINavigationController.class] ? ((UINavigationController *)delegate).topViewController : nil;
    return [NSStringFromClass(top.class) hasPrefix:@"FZ"];
}

// The button's role, for its own circle switch: back, ⋯, Frozio's own entry (left alone), or any other.
typedef NS_ENUM(NSInteger, FZRBarRole) { FZRBarRoleOther, FZRBarRoleBack, FZRBarRoleMore, FZRBarRoleFrozio };

static NSString *labelOf(UIView *item) {
    if (item.accessibilityLabel.length) return item.accessibilityLabel;
    for (id element in FZRAccessibilityElementsIn(item)) {
        NSString *label = [element accessibilityLabel];
        if (label.length) return label;
    }
    return nil;
}

static BOOL holdsFrozioEntry(UIView *view) {
    if ([view.accessibilityIdentifier isEqualToString:@"fz.settings.entry"]) return YES;
    for (UIView *sub in view.subviews) if (holdsFrozioEntry(sub)) return YES;
    return NO;
}

static FZRBarRole roleOf(UIView *item, BOOL firstLeading, UINavigationBar *bar) {
    if (holdsFrozioEntry(item)) return FZRBarRoleFrozio;
    NSString *label = labelOf(item);
    if ([label isEqualToString:@"Frozio settings"]) return FZRBarRoleFrozio;
    if ([label isEqualToString:@"More"] || [label isEqualToString:@"More Options"] || [label isEqualToString:@"ellipsis"]) return FZRBarRoleMore;
    BOOL hasBack = bar.backItem != nil && !bar.topItem.hidesBackButton;
    if (firstLeading && hasBack && [NSStringFromClass(item.class) isEqualToString:@"_UIButtonBarButton"]) return FZRBarRoleBack;
    if ([label isEqualToString:@"Back"]) return FZRBarRoleBack;
    return FZRBarRoleOther;
}

static BOOL circleFor(FZRBarRole role) {
    switch (role) {
        case FZRBarRoleBack: return FZEnabled(FZRKeyCircleBack);
        case FZRBarRoleMore: return FZEnabled(FZRKeyCircleMore);
        case FZRBarRoleOther: return FZEnabled(FZRKeyCircleOthers);
        case FZRBarRoleFrozio: return NO;
    }
    return NO;
}

// Where the item's glyph is in the bar without Frozio's own move, so a layout pass never has to undo it first (doing
// so on every pass made the buttons jump while a list scrolled).
static CGFloat baseX(UIView *item, UINavigationBar *bar) {
    return [item convertPoint:glyphCentre(item) toView:bar].x - item.transform.tx;
}

void FZRStyleBarButtons(UINavigationBar *bar) {
    if (!FZRRedesignActive() || !bar.window || isFrozioBar(bar)) return;
    BOOL glass = !systemGlass();
    BOOL white = FZEnabled(FZRKeyBarWhite);
    UINavigationItemBackButtonDisplayMode mode = FZEnabled(FZRKeyBarBareBack) ? UINavigationItemBackButtonDisplayModeMinimal
                                                                             : UINavigationItemBackButtonDisplayModeDefault;
    if (bar.topItem && bar.topItem.backButtonDisplayMode != mode) bar.topItem.backButtonDisplayMode = mode;

    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *sub in bar.subviews) collectItems(sub, 0, items);
    id filter = white ? whiteFilter() : nil;
    CGFloat width = bar.bounds.size.width;
    NSMutableArray<UIView *> *leading = [NSMutableArray array], *trailing = [NSMutableArray array];
    for (UIView *item in items) [(baseX(item, bar) < width / 2 ? leading : trailing) addObject:item];
    [leading sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { return [@(baseX(a, bar)) compare:@(baseX(b, bar))]; }];
    [trailing sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { return [@(baseX(b, bar)) compare:@(baseX(a, bar))]; }];

    for (NSArray<UIView *> *group in @[leading, trailing]) {
        BOOL lead = group == leading;
        // chroma.pw's spacing (16 pt from the bar's sides, 8 pt apart) once any button of the side has a circle.
        BOOL anyCircle = NO;
        NSMutableArray<NSNumber *> *roles = [NSMutableArray array];
        for (NSUInteger i = 0; i < group.count; i++) {
            FZRBarRole role = roleOf(group[i], lead && i == 0, bar);
            [roles addObject:@(role)];
            anyCircle = anyCircle || (glass && circleFor(role));
        }
        CGFloat edge = lead ? 16 : width - 16;
        for (NSUInteger i = 0; i < group.count; i++) {
            UIView *item = group[i];
            FZRBarRole role = (FZRBarRole)roles[i].integerValue;
            BOOL circled = glass && circleFor(role);
            CGFloat side = MAX(kCircle, item.bounds.size.width > 60 ? item.bounds.size.width + 12 : kCircle);
            UIView *shape = objc_getAssociatedObject(item, &kCircleKey);
            if (role == FZRBarRoleBack) {
                // Back's circle goes inside the chevron's own view, behind the chevron: a circle beside it in the
                // back button blanked the chevron once the bar had its blur, and one outside the button outlived it
                // (harness). This way it moves, fades and goes with the chevron.
                UIView *chevron = nil;
                for (UIView *sub in item.subviews) if ([NSStringFromClass(sub.class) isEqualToString:@"_UIModernBarButton"]) chevron = sub;
                if (shape && shape.superview != chevron) { [shape removeFromSuperview]; objc_setAssociatedObject(item, &kCircleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); shape = nil; }
                UIView *inner = chevron ? objc_getAssociatedObject(chevron, &kCircleKey) : nil;
                if (circled && chevron) {
                    inner = FZRGlassCapsuleInside(chevron, &kCircleKey, CGSizeMake(side, kCircle), NO);
                    inner.layer.borderWidth = 1;
                    inner.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
                    inner.layer.cornerRadius = kCircle / 2;
                    inner.hidden = NO;
                    chevron.clipsToBounds = NO;
                } else {
                    inner.hidden = YES;
                }
            } else if (circled) {
                shape = FZRGlassCapsuleInside(item, &kCircleKey, CGSizeMake(side, kCircle), NO);
                shape.layer.borderWidth = 1;   // chroma.pw on iOS 17: a faint ring around the material
                shape.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
                shape.layer.cornerRadius = kCircle / 2;
                CGPoint centre = glyphCentre(item);
                if (!CGPointEqualToPoint(shape.center, centre)) shape.center = centre;
                shape.hidden = NO;
                item.clipsToBounds = NO;
            } else if (shape) {
                shape.hidden = YES;
            }
            CGFloat tx = 0;
            if (anyCircle) {
                CGFloat target = lead ? edge + side / 2 : edge - side / 2;
                tx = round(target - baseX(item, bar));
                edge += lead ? side + 8 : -(side + 8);
            }
            if (fabs(item.transform.tx - tx) > 0.5 || item.transform.ty != 0) item.transform = CGAffineTransformMakeTranslation(tx, 0);
            // White: every layer of the button but the glass; Frozio's own button keeps its look.
            NSArray *filters = filter && role != FZRBarRoleFrozio ? @[filter] : nil;
            // Back: its circle sits inside the chevron's view, so the chevron's own images take the white instead.
            NSMutableArray<UIView *> *targets = [NSMutableArray arrayWithArray:item.subviews];
            UIView *backCircle = nil;
            if (role == FZRBarRoleBack) {
                for (UIView *sub in item.subviews) {
                    if (![NSStringFromClass(sub.class) isEqualToString:@"_UIModernBarButton"]) continue;
                    backCircle = objc_getAssociatedObject(sub, &kCircleKey);
                    [targets removeObject:sub];
                    if (objc_getAssociatedObject(sub, &kWhitenedKey)) { sub.layer.filters = nil; objc_setAssociatedObject(sub, &kWhitenedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
                    for (UIView *inner in sub.subviews) if (inner != backCircle) [targets addObject:inner];
                }
            }
            for (UIView *sub in targets) {
                // Not the glass, and not UIKit's back-button mask: it masks the chevron while the bar changes, and a
                // filtered mask left the chevron blank (harness).
                if (sub == shape || [NSStringFromClass(sub.class) rangeOfString:@"MaskView"].location != NSNotFound) {
                    if (objc_getAssociatedObject(sub, &kWhitenedKey)) { sub.layer.filters = nil; objc_setAssociatedObject(sub, &kWhitenedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
                    continue;
                }
                if (filters ? sub.layer.filters.count == 0 : objc_getAssociatedObject(sub, &kWhitenedKey) != nil) {
                    sub.layer.filters = filters;
                    objc_setAssociatedObject(sub, &kWhitenedKey, filters ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
    }
}
