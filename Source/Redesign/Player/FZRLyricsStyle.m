// See FZRLyricsStyle.h.
#import "Redesign/Player/FZRLyricsStyle.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Prefs/FZSettings.h"

NSString *const FZRKeyLyricsStyle = @"fz.redesign.lyrics.style";


@interface FZRLyricsStyle ()
@property (nonatomic, readwrite, copy) NSString *key, *name;
@property (nonatomic, readwrite) UIFontDescriptorSystemDesign design;
@property (nonatomic, readwrite) UIFontWeight weight;
@property (nonatomic, readwrite) BOOL italic, condensed, uppercase, outline, pill, scanlines;
@property (nonatomic, readwrite) CGFloat tracking, glowRadius, anchor, dim, blur;
@property (nonatomic, readwrite, copy) NSArray<UIColor *> *sung;
@property (nonatomic, readwrite) UIColor *unsung, *glow, *mark;
@property (nonatomic, readwrite) NSTextAlignment alignment;
@property (nonatomic, readwrite) NSInteger background;
@end

@implementation FZRLyricsStyle

static FZRLyricsStyle *make(NSString *key, NSString *name, void (^set)(FZRLyricsStyle *s)) {
    FZRLyricsStyle *s = [FZRLyricsStyle new];
    s.key = key;
    s.name = name;
    s.design = UIFontDescriptorSystemDesignDefault;
    s.weight = UIFontWeightBold;
    s.unsung = UIColor.whiteColor;
    s.alignment = NSTextAlignmentLeft;
    s.anchor = 0.28;
    s.dim = 0.3;
    s.blur = 1;
    s.background = -1;
    set(s);
    return s;
}

+ (NSArray<FZRLyricsStyle *> *)all {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all = @[
            // As the lyrics were before the styles: every line white, the sung one at full strength.
            make(@"default", @"Default", ^(FZRLyricsStyle *s) { s.sung = @[UIColor.whiteColor]; }),
            // The sung line in the accent colour.
            make(@"accent", @"Accent", ^(FZRLyricsStyle *s) { s.sung = nil; }),
        ];
    });
    return all;
}

+ (FZRLyricsStyle *)current {
    NSString *key = [[FZSettings defaults] stringForKey:FZRKeyLyricsStyle] ?: @"default";
    for (FZRLyricsStyle *style in self.all) if ([style.key isEqualToString:key]) return style;
    return self.all.firstObject;
}

- (UIFont *)fontOfSize:(CGFloat)size {
    UIFont *font = [UIFont systemFontOfSize:size weight:_weight];
    if (_condensed) {
        if (@available(iOS 16.0, *)) font = [UIFont systemFontOfSize:size weight:_weight width:UIFontWidthCondensed];
    }
    UIFontDescriptor *descriptor = font.fontDescriptor;
    if (![_design isEqualToString:UIFontDescriptorSystemDesignDefault]) descriptor = [descriptor fontDescriptorWithDesign:_design] ?: descriptor;
    if (_italic) descriptor = [descriptor fontDescriptorWithSymbolicTraits:descriptor.symbolicTraits | UIFontDescriptorTraitItalic] ?: descriptor;
    return [UIFont fontWithDescriptor:descriptor size:size];
}

- (UIColor *)sungColorForLineHeight:(CGFloat)lineHeight {
    NSArray<UIColor *> *colors = _sung ?: @[FZRAccent()];
    if (colors.count == 1 && !_scanlines) return colors.firstObject;
    CGFloat height = MAX(4, ceil(lineHeight));
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, height)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        NSMutableArray *cg = [NSMutableArray array];
        for (UIColor *c in colors) [cg addObject:(id)c.CGColor];
        if (cg.count == 1) [cg addObject:cg.firstObject];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)cg, NULL);
        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointMake(0, height * 0.15), CGPointMake(0, height * 0.85),
                                    kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        if (self->_scanlines) {
            CGContextSetBlendMode(context.CGContext, kCGBlendModeClear);
            for (CGFloat y = 1; y < height; y += 3) CGContextFillRect(context.CGContext, CGRectMake(0, y, 1, 1));
        }
    }];
    return [UIColor colorWithPatternImage:image];
}
@end
