// See FZRLyricsStyle.h.
#import "Redesign/Player/FZRLyricsStyle.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Prefs/FZSettings.h"

NSString *const FZRKeyLyricsStyle = @"fz.redesign.lyrics.style";

static UIColor *hex(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1];
}

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
            make(@"default", @"Default", ^(FZRLyricsStyle *s) {}),
            // chroma.pw's built-in styles, by their values.
            make(@"poster", @"Poster", ^(FZRLyricsStyle *s) {
                s.weight = UIFontWeightBlack; s.uppercase = YES; s.tracking = -0.01;
                s.sung = nil; s.outline = YES; s.alignment = NSTextAlignmentCenter; s.anchor = 0.4; s.dim = 0.45; s.blur = 0;
            }),
            make(@"neon", @"Neon", ^(FZRLyricsStyle *s) {
                s.design = UIFontDescriptorSystemDesignRounded; s.weight = UIFontWeightBold;
                s.sung = @[hex(0x7DF9FF), hex(0xFF5CF0)]; s.unsung = hex(0x7DF9FF);
                s.glow = hex(0xFF5CF0); s.glowRadius = 14; s.dim = 0.25; s.blur = 1.2; s.background = 10;
            }),
            make(@"highlighter", @"Highlighter", ^(FZRLyricsStyle *s) {
                s.weight = UIFontWeightHeavy; s.sung = @[hex(0x141414)]; s.mark = hex(0xFFE14D);
                s.anchor = 0.32; s.dim = 0.4; s.blur = 0.6;
            }),
            make(@"subtitles", @"Subtitles", ^(FZRLyricsStyle *s) {
                s.weight = UIFontWeightSemibold; s.sung = @[UIColor.whiteColor];
                s.mark = [UIColor colorWithWhite:0 alpha:0.72]; s.pill = YES;
                s.alignment = NSTextAlignmentCenter; s.anchor = 0.72; s.dim = 0.45; s.blur = 0;
            }),
            make(@"novel", @"Novel", ^(FZRLyricsStyle *s) {
                s.design = UIFontDescriptorSystemDesignSerif; s.weight = UIFontWeightSemibold; s.italic = YES;
                s.sung = @[hex(0xF6EBDD)]; s.unsung = hex(0xF6EBDD); s.glow = hex(0xFFC98A); s.glowRadius = 10;
                s.alignment = NSTextAlignmentCenter; s.anchor = 0.36; s.blur = 1.6;
            }),
            // Frozio's own, after the looks of the Workshop's.
            make(@"inferno", @"Inferno", ^(FZRLyricsStyle *s) {
                s.weight = UIFontWeightBlack; s.condensed = YES; s.uppercase = YES;
                s.sung = @[hex(0xFFE27A), hex(0xFF9A1F), hex(0xE2370F)]; s.unsung = hex(0xB0542A);
                s.glow = hex(0xFF6A00); s.glowRadius = 12; s.alignment = NSTextAlignmentCenter; s.anchor = 0.3; s.background = 11;
            }),
            make(@"hologram", @"Hologram", ^(FZRLyricsStyle *s) {
                s.design = UIFontDescriptorSystemDesignMonospaced; s.weight = UIFontWeightBold; s.uppercase = YES;
                s.sung = @[hex(0x9FF3FF), hex(0x3FC8F0)]; s.unsung = hex(0x3FA8D0); s.scanlines = YES;
                s.glow = hex(0x3FD8FF); s.glowRadius = 8; s.alignment = NSTextAlignmentCenter; s.anchor = 0.3; s.background = 12;
            }),
            make(@"chrome", @"Chrome", ^(FZRLyricsStyle *s) {
                s.weight = UIFontWeightBlack; s.condensed = YES; s.uppercase = YES; s.italic = YES;
                s.sung = @[hex(0xFFFFFF), hex(0xBFC7D6), hex(0x4A4F63), hex(0xE9D7FF)]; s.unsung = hex(0x9A86B8);
                s.glow = hex(0xFF4FD8); s.glowRadius = 6; s.alignment = NSTextAlignmentCenter; s.anchor = 0.3; s.background = 13;
            }),
            make(@"blueprint", @"Blueprint", ^(FZRLyricsStyle *s) {
                s.design = UIFontDescriptorSystemDesignMonospaced; s.weight = UIFontWeightHeavy; s.uppercase = YES;
                s.sung = @[UIColor.whiteColor]; s.unsung = [UIColor colorWithWhite:1 alpha:0.9]; s.outline = YES;
                s.anchor = 0.3; s.dim = 0.5; s.blur = 0.3; s.background = 14;
            }),
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
