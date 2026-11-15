// Adapted from taurus/tweak/Sources/Redesigned/Kit/SGRActionRow.m @ fe3211c (GPL-3.0, github.com/xFr0z3n/taurus).
#pragma once
#import <UIKit/UIKit.h>

// A redesign button: a glyph, on a 44/48 pt glass circle when `circled` (FZRGlassInside's shape).
@interface FZRRoundButton : UIControl
- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)size weight:(UIImageSymbolWeight)weight label:(NSString *)label;
@property (nonatomic) BOOL circled;
@property (nonatomic, readonly) UIImageView *glyph;
// A new glyph at the size and weight it was made with.
- (void)setSymbol:(NSString *)symbol;
// A menu the button opens on a tap (a UIButton laid over it carries it; UIControl has no menu of its own).
@property (nonatomic, copy) UIMenu *menu;
@end
