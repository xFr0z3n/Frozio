// Adapted from taurus/tweak/Sources/Redesigned/Kit/SGRActionRow.m and SGRGlass.m @ fe3211c (GPL-3.0). See FZRRoundButton.h.
#import "Redesign/Kit/FZRRoundButton.h"
#import "Redesign/Kit/FZRGlass.h"
#import "Redesign/Kit/FZRTokens.h"
@implementation FZRRoundButton {
    UIView *_glass;
    BOOL _hasGlass;
    UIImageSymbolConfiguration *_configuration;
    UIButton *_menuButton;
}
static char kRoundGlassKey;

- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)size weight:(UIImageSymbolWeight)weight label:(NSString *)label {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = label;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _configuration = [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    _glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:_configuration]];
    _glyph.tintColor = FZRPrimary();
    _glyph.contentMode = UIViewContentModeCenter;
    [self addSubview:_glyph];
    _circled = YES;
    return self;
}
- (void)setSymbol:(NSString *)symbol {
    _glyph.image = [UIImage systemImageNamed:symbol withConfiguration:_configuration];
}
- (void)setMenu:(UIMenu *)menu {
    _menu = [menu copy];
    if (!_menuButton) {
        _menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _menuButton.showsMenuAsPrimaryAction = YES;
        _menuButton.isAccessibilityElement = NO;
        [self addSubview:_menuButton];
    }
    _menuButton.menu = menu;
    _menuButton.hidden = menu == nil;
    [self setNeedsLayout];
}
- (void)setCircled:(BOOL)circled {
    _circled = circled;
    _glass.hidden = !circled;
    [self setNeedsLayout];
}
// The redesign's control glass, made the way taurus makes it (SGRGlassInside): iOS 26's Liquid Glass (interactive,
// like the system's glass buttons), the thin dark material before it, a solid fill under Reduce Transparency.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    if (_circled && side > 0) {
        _glass = FZRGlassInside(self, &kRoundGlassKey, side);
        _glass.hidden = NO;
        if (!_hasGlass && [_glass isKindOfClass:UIVisualEffectView.class]) {
            _hasGlass = YES;
            UIVisualEffect *effect = ((UIVisualEffectView *)_glass).effect;
            if ([effect respondsToSelector:NSSelectorFromString(@"setInteractive:")]) {
                [effect setValue:@YES forKey:@"interactive"];
                ((UIVisualEffectView *)_glass).effect = effect;
            }
            BOOL liquid = NO;
            if (@available(iOS 26.0, *)) liquid = YES;
            if (!liquid) {
                // chroma.pw on iOS 17: a faint lighter ring around the material (measured (58, 47, 44) on (24, 10, 8)).
                _glass.layer.borderWidth = 1;
                _glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
                _glass.layer.cornerRadius = side / 2;
            }
        }
    } else if (_glass) {
        _glass.hidden = YES;
    }
    _glyph.frame = self.bounds;
    [self bringSubviewToFront:_glyph];
    if (_menuButton) {
        _menuButton.frame = self.bounds;
        [self bringSubviewToFront:_menuButton];
    }
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    FZRAnimate(FZRMotionPress, ^{ self.glyph.alpha = highlighted ? 0.6 : 1; }, nil);
}
@end

