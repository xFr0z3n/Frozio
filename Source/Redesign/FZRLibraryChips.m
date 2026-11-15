// The round chips heading NaviMus's library sections ("#", "A", "2017", …) in the redesign's glass, the same as the
// bar buttons' (the user's request, build 43). In a section header SwiftUI draws the chip's fill as a layer of its own
// (round, with a background colour; harness): it's hidden and a glass circle of the same frame goes behind the
// header's content, under the chip's text. The debug log lists the first header's views once, so a
// device where SwiftUI draws the chip otherwise shows up there.
#import <objc/runtime.h>
#import "Redesign/FZRAppLook.h"
#import "Redesign/FZRBarButtons.h"
#import "Redesign/Kit/FZRGlass.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

static IMP fz_origCollectionHeader, fz_origTableHeader, fz_origApply;
static char kChipGlassKey, kChipHolderKey, kHeaderKindKey, kChipShapeKey;

static void logOnce(UIView *header) {
#ifdef FROZIO_DEBUG
    static NSMutableSet *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *kind = [NSStringFromClass(header.class) stringByAppendingFormat:@" %.0f", header.bounds.size.height];
    if ([logged containsObject:kind]) return;
    [logged addObject:kind];
    NSMutableArray *lines = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:header];
    while (queue.count && lines.count < 30) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *name = NSStringFromClass(view.class);
        [lines addObject:[NSString stringWithFormat:@"%@ %@", [name substringToIndex:MIN(60, name.length)], NSStringFromCGRect(view.frame)]];
        [queue addObjectsFromArray:view.subviews];
    }
    FZLog("chips: first %@: %@", kind, [lines componentsJoinedByString:@" | "]);
    __weak UIView *weakHeader = header;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    UIView *header = weakHeader;
    if (!header) return;
    NSMutableArray *layers = [NSMutableArray array];
    NSMutableArray<CALayer *> *walk = [NSMutableArray arrayWithObject:header.layer];
    while (walk.count && layers.count < 40) {
        CALayer *layer = walk.firstObject;
        [walk removeObjectAtIndex:0];
        [layers addObject:[NSString stringWithFormat:@"%@ %@ r%.1f bg%@ contents%d", NSStringFromClass(layer.class), NSStringFromCGRect([layer convertRect:layer.bounds toLayer:header.layer]),
                           layer.cornerRadius, layer.backgroundColor ? @"Y" : @"N", layer.contents != nil]];
        [walk addObjectsFromArray:layer.sublayers ?: @[]];
    }
    FZLog("chips: layers %@", [layers componentsJoinedByString:@" | "]);
    });
#endif
}

// The chip's fill as SwiftUI draws it in a header (harness): a layer of its own, near square, 28–72 pt, its corner
// radius half its side, with a background colour; the chip's text is another layer.
static BOOL isChipLayer(CALayer *layer) {
    CGSize size = layer.bounds.size;
    return layer.backgroundColor && CGColorGetAlpha(layer.backgroundColor) > 0.05
        && size.width >= 28 && size.width <= 72 && fabs(size.width - size.height) <= 6
        && fabs(layer.cornerRadius - size.width / 2) <= 3;
}

static void styleChips(UIView *header) {
    if (!FZRRedesignActive() || !header.window) return;
    logOnce(header);
    BOOL glass = FZEnabled(FZRKeyCircleOthers);
    NSMutableArray<CALayer *> *fills = [NSMutableArray array];
    NSMutableArray<CALayer *> *walk = [NSMutableArray arrayWithArray:header.layer.sublayers ?: @[]];
    while (walk.count && fills.count < 4) {
        CALayer *layer = walk.firstObject;
        [walk removeObjectAtIndex:0];
        if ([layer.delegate isKindOfClass:UIView.class] && objc_getAssociatedObject(layer.delegate, &kChipGlassKey)) continue;   // Frozio's
        if (isChipLayer(layer) || objc_getAssociatedObject(layer, &kChipHolderKey)) { [fills addObject:layer]; continue; }
        [walk addObjectsFromArray:layer.sublayers ?: @[]];
    }
    NSMutableArray<UIView *> *holders = objc_getAssociatedObject(header, &kChipHolderKey) ?: [NSMutableArray array];
    objc_setAssociatedObject(header, &kChipHolderKey, holders, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSUInteger i = 0; i < MAX(fills.count, holders.count); i++) {
        if (i >= fills.count) { holders[i].hidden = YES; continue; }
        CALayer *fill = fills[i];
        objc_setAssociatedObject(fill, &kChipHolderKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        fill.opacity = glass ? 0 : 1;   // SwiftUI's grey fill
        [CATransaction commit];
        if (i >= holders.count) {
            UIView *holder = [UIView new];
            holder.userInteractionEnabled = NO;
            objc_setAssociatedObject(holder, &kChipGlassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [holders addObject:holder];
        }
        UIView *holder = holders[i];
        holder.hidden = !glass;
        if (!glass) continue;
        // Behind everything of the header but its background, so the chip's text stays on top.
        UIView *above = nil;
        for (UIView *sub in header.subviews) {
            if (sub == holder || ![NSStringFromClass(sub.class) containsString:@"BackgroundView"]) continue;
            above = sub;
        }
        if (holder.superview != header) {
            if (above) [header insertSubview:holder aboveSubview:above]; else [header insertSubview:holder atIndex:0];
        }
        CGRect frame = [fill convertRect:fill.bounds toLayer:header.layer];
        if (!CGRectEqualToRect(holder.frame, frame)) holder.frame = frame;
        CGFloat side = MIN(frame.size.width, frame.size.height);
        UIView *shape = FZRGlassInside(holder, &kChipShapeKey, side);
        shape.layer.borderWidth = 1;   // as the bar buttons' circles before iOS 26
        shape.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        shape.layer.cornerRadius = side / 2;
    }
}

// SwiftUI's list headers are cell classes used as supplementary views (harness), so a header is told by the kind UIKit
// lays it out as, never by its class: rows (whose covers can be square shapes too) are left alone.
static void fz_apply(UICollectionReusableView *self, SEL _cmd, UICollectionViewLayoutAttributes *attributes) {
    ((void (*)(id, SEL, id))fz_origApply)(self, _cmd, attributes);
    BOOL header = attributes.representedElementCategory == UICollectionElementCategorySupplementaryView
        && [attributes.representedElementKind.lowercaseString containsString:@"header"];
    objc_setAssociatedObject(self, &kHeaderKindKey, header ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// SwiftUI draws a header's content after the header's own layout pass: the chips are styled then and again a moment
// later, when the fill layer exists (and if SwiftUI made it anew).
static void styleSoon(UIView *header) {
    styleChips(header);
    __weak UIView *weak = header;
    for (NSNumber *delay in @[@0.05, @0.3]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) styleChips(weak);
        });
    }
}

static void fz_collectionHeaderLayout(UICollectionReusableView *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origCollectionHeader)(self, _cmd);
    if (objc_getAssociatedObject(self, &kHeaderKindKey)) styleSoon(self);
}

static void fz_tableHeaderLayout(UITableViewHeaderFooterView *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origTableHeader)(self, _cmd);
    styleSoon(self);
}

void FZRInstallLibraryChips(void) {
    if (!FZRRedesignActive()) return;
    BOOL collection = FZHookInstanceMethod(UICollectionReusableView.class, @selector(layoutSubviews), "v@:", (IMP)fz_collectionHeaderLayout,
                                           &fz_origCollectionHeader, "chips.collection");
    BOOL apply = FZHookInstanceMethod(UICollectionReusableView.class, @selector(applyLayoutAttributes:), "v@:@", (IMP)fz_apply,
                                      &fz_origApply, "chips.attributes");
    (void)apply;
    BOOL table = FZHookInstanceMethod(UITableViewHeaderFooterView.class, @selector(layoutSubviews), "v@:", (IMP)fz_tableHeaderLayout,
                                      &fz_origTableHeader, "chips.table");
    FZLog("chips: %d/%d", collection, table);
}
