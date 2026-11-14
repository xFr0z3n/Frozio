// Adapted from taurus/tweak/Sources/Core/SGViewTree.h (GPL-3.0, github.com/xFr0z3n/taurus).
// Walking and reading view trees.
#import <UIKit/UIKit.h>

void FZForEachView(UIView *view, void (^fn)(UIView *));
CGRect FZFrameIn(UIView *view, UIView *target);
// Whether `view` sits under `root`, stopping at a visual effect view on the way up.
BOOL FZIsInside(UIView *view, UIView *root);
UIStackView *FZRowIn(UIView *host);
// Whether any view under `root` has `marker` in its class name.
BOOL FZHasClass(UIView *root, NSString *marker);

// Artwork, glyphs, text and thin lines (progress bar) keep their colour, everything else goes clear.
BOOL FZKeepsColor(UIView *view);
void FZStripBackgrounds(UIView *view);
BOOL FZIsVisibleColor(CGColorRef color);
BOOL FZIsLightColor(CGColorRef color);
BOOL FZIsBaseSurface(CGColorRef color);
// A painted, card-sized view: the now playing bar's card, for one.
BOOL FZLooksLikeCard(UIView *view, CGColorRef color);
