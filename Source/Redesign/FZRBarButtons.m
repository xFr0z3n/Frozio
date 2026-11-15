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
    // A UIKit button that isn't back (Search's account picture, device log build 47): its image view moves about
    // while UIKit lays it out, and following it made the circle and the button jump; its middle is steady.
    if ([NSStringFromClass(item.class) isEqualToString:@"_UIButtonBarButton"]) {
        BOOL chevron = NO;
        for (UIView *sub in item.subviews) chevron = chevron || [NSStringFromClass(sub.class) isEqualToString:@"_UIModernBarButton"];
        if (!chevron) return CGPointMake(CGRectGetMidX(item.bounds), CGRectGetMidY(item.bounds));
    }
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

// A button showing a picture rather than a glyph (Search's account: a UIImageView on device, a SwiftUI image view in
// the harness): it keeps its colours.
static BOOL holdsPicture(UIView *item) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:item.subviews];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view.hidden || [view isKindOfClass:UIVisualEffectView.class]) continue;
        if ([view isKindOfClass:UIImageView.class]) {
            UIImage *image = ((UIImageView *)view).image;
            if (image && !image.isSymbolImage && image.renderingMode != UIImageRenderingModeAlwaysTemplate && view.bounds.size.width >= 20) return YES;
        } else if ([NSStringFromClass(view.class) hasSuffix:@"_UIGraphicsView"] && view.bounds.size.width >= 20 && view.bounds.size.height >= 20) {
            return YES;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return NO;
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

static void styleBar(UINavigationBar *bar);

void FZRStyleBarButtons(UINavigationBar *bar) {
    static BOOL styling;
    if (styling || !FZRRedesignActive() || !bar.window || isFrozioBar(bar)) return;
    styling = YES;
    @try { styleBar(bar); } @finally { styling = NO; }
}

static void styleBar(UINavigationBar *bar) {
    BOOL glass = !systemGlass();
    BOOL white = FZEnabled(FZRKeyBarWhite);
    UINavigationItemBackButtonDisplayMode mode = FZEnabled(FZRKeyBarBareBack) ? UINavigationItemBackButtonDisplayModeMinimal
                                                                             : UINavigationItemBackButtonDisplayModeDefault;
    // Set on the page and on the one before it (UIKit reads the back button's look from either, by iOS version):
    // NaviMus's back showed the previous page's name in a capsule on device (build 45).
    for (UINavigationItem *navItem in @[bar.topItem ?: NSNull.null, bar.backItem ?: NSNull.null]) {
        if ([navItem isKindOfClass:UINavigationItem.class] && navItem.backButtonDisplayMode != mode) navItem.backButtonDisplayMode = mode;
    }

    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *sub in bar.subviews) collectItems(sub, 0, items);
    // A wide item is a page's title (NaviMus's artist page puts the artist's name there, hidden until the list
    // scrolls): no glass and no move, or an empty capsule sat in the middle of the bar (device, build 46).
    for (UIView *item in [items copy]) {
        if (item.bounds.size.width <= 100) continue;
        [items removeObject:item];
        UIView *shape = objc_getAssociatedObject(item, &kCircleKey);
        shape.hidden = YES;
        if (!CGAffineTransformIsIdentity(item.transform)) item.transform = CGAffineTransformIdentity;
    }
    id filter = white ? whiteFilter() : nil;
    CGFloat width = bar.bounds.size.width;
    NSMutableArray<UIView *> *leading = [NSMutableArray array], *trailing = [NSMutableArray array];
    for (UIView *item in items) [(baseX(item, bar) < width / 2 ? leading : trailing) addObject:item];
    [leading sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { return [@(baseX(a, bar)) compare:@(baseX(b, bar))]; }];
    [trailing sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { return [@(baseX(b, bar)) compare:@(baseX(a, bar))]; }];

#ifdef FROZIO_DEBUG
    // Once per page: what the bar's buttons are, for the next device log (Search's account button, build 43).
    static NSString *lastTitle;
    NSString *pageKey = [NSString stringWithFormat:@"%@#%lu", bar.topItem.title ?: @"-", (unsigned long)items.count];
    if (![pageKey isEqualToString:lastTitle]) {
        lastTitle = pageKey;
        NSMutableArray *names = [NSMutableArray array];
        for (UIView *item in items) {
            NSMutableArray *leafs = [NSMutableArray array];
            NSMutableArray<UIView *> *walk = [NSMutableArray arrayWithArray:item.subviews];
            while (walk.count && leafs.count < 8) {
                UIView *v = walk.firstObject; [walk removeObjectAtIndex:0];
                if (!v.subviews.count) [leafs addObject:[NSString stringWithFormat:@"%@%@", [NSStringFromClass(v.class) substringFromIndex:MAX(0, (NSInteger)NSStringFromClass(v.class).length - 24)],
                                                         NSStringFromCGRect(v.frame)]];
                [walk addObjectsFromArray:v.subviews];
            }
            [names addObject:[NSString stringWithFormat:@"%@ \"%@\" %@ [%@]", NSStringFromClass(item.class), labelOf(item), NSStringFromCGRect(item.frame), [leafs componentsJoinedByString:@", "]]];
        }
        FZLog("bar buttons: page %@ search=%d: %@", bar.topItem.title, bar.topItem.searchController != nil, [names componentsJoinedByString:@" | "]);
    }
#endif
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
        // On a page with a search field, the circles sit a little higher so they stay clear of it once the large
        // title has collapsed (the user's screenshot, build 43: they rested on the field).
        // Only once the large title has collapsed: above it, the buttons have the bar's whole top row (lifted there,
        // they were cut off at the top, device build 44).
        BOOL largeTitle = NO;
        for (UIView *sub in bar.subviews) {
            if ([NSStringFromClass(sub.class) containsString:@"LargeTitleView"] && !sub.hidden && sub.alpha > 0.5 && sub.bounds.size.height > 20) largeTitle = YES;
        }
        CGFloat lift = bar.topItem.searchController && !largeTitle ? -4 : 0;
        for (NSUInteger i = 0; i < group.count; i++) {
            UIView *item = group[i];
            FZRBarRole role = (FZRBarRole)roles[i].integerValue;
            BOOL circled = glass && circleFor(role);
            // Back is always a circle round its chevron; a word ("Edit") gets a capsule.
            CGFloat side = role == FZRBarRoleBack ? kCircle : MAX(kCircle, item.bounds.size.width > 60 ? item.bounds.size.width + 12 : kCircle);
            if (role == FZRBarRoleBack) {
                BOOL bare = mode == UINavigationItemBackButtonDisplayModeMinimal;
                NSMutableArray<UIView *> *walk = [NSMutableArray arrayWithArray:item.subviews];
                while (walk.count) {
                    UIView *v = walk.firstObject; [walk removeObjectAtIndex:0];
                    if ([v isKindOfClass:UILabel.class] || [NSStringFromClass(v.class) containsString:@"ButtonLabel"]) { if (v.hidden != bare) v.hidden = bare; continue; }
                    [walk addObjectsFromArray:v.subviews];
                }
            }
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
            CGFloat ty = anyCircle ? lift : 0;
            // Lifted, the circle reaches past the bar's content area, which clipped its top (device, build 44): the
            // views between the button and the bar draw outside their bounds.
            if (ty != 0) for (UIView *v = item.superview; v && v != bar.superview; v = v.superview) if (v.clipsToBounds) v.clipsToBounds = NO;
            if (fabs(item.transform.tx - tx) > 0.5 || fabs(item.transform.ty - ty) > 0.5) item.transform = CGAffineTransformMakeTranslation(tx, ty);
            // White: every layer of the button but the glass; Frozio's own button keeps its look.
            NSArray *filters = filter && role != FZRBarRoleFrozio && !holdsPicture(item) ? @[filter] : nil;
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
                // Nor a picture (an account's photo or initials): only glyphs turn white.
                BOOL picture = [sub isKindOfClass:UIImageView.class] && ((UIImageView *)sub).image && !((UIImageView *)sub).image.isSymbolImage
                    && ((UIImageView *)sub).image.renderingMode != UIImageRenderingModeAlwaysTemplate;
                if (sub == shape || picture || [NSStringFromClass(sub.class) rangeOfString:@"MaskView"].location != NSNotFound) {
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
