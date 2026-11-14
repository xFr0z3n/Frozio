// Adapted from taurus/tweak/Sources/Redesigned/Kit/SGRGlass.h @ fe3211c (GPL-3.0, github.com/xFr0z3n/taurus).
#import <UIKit/UIKit.h>

UIView *FZRGlassInside(UIView *control, const void *key, CGFloat side);

UIView *FZRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent);

// Shows or hides a shape's material without touching an alpha over it: a glass shape's effect is set or
// cleared, so it fades as the system's glass does; under Reduce Transparency (a solid fill) it fades by
// alpha. Call inside an FZRAnimate block.
void FZRShowGlass(UIView *shape, BOOL shown);
