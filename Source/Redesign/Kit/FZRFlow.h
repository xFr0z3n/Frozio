// Adapted from taurus/tweak/Sources/Redesigned/Kit/SGRFlow.h @ fe3211c (GPL-3.0, github.com/xFr0z3n/taurus). Renamed SG→FZ.
#import <UIKit/UIKit.h>

@interface FZRFlowLayer : CALayer
- (void)setColors:(NSArray<UIColor *> *)colors animated:(BOOL)animated;
// The colour under the discs, darker than the artwork's main one; nil before any colours are set.
@property (nonatomic, readonly) UIColor *baseColor;
// Drifting, or held still where it is. Off to begin with.
@property (nonatomic) BOOL moving;
@end
