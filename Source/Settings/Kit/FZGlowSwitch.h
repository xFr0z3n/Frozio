// Adapted from taurus/tweak/Sources/Settings/SGGlowSwitch.h (GPL-3.0, github.com/xFr0z3n/taurus).
#import <UIKit/UIKit.h>

@interface FZGlowSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

NSArray<UIColor *> *FZGlowRainbowColors(void);
