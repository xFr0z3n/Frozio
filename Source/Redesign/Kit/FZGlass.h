// Adapted from taurus/tweak/Sources/Core/SGGlass.h @ fe3211c (GPL-3.0, github.com/xFr0z3n/taurus).
// Glass panes: one UIVisualEffectView per host, kept behind the host's own content.
#import <UIKit/UIKit.h>

// UIGlassEffect made the only way that resolves its material, or a dark chrome blur before iOS 26.
UIVisualEffect *FZGlassEffect(void);
UIVisualEffectView *FZGlassFor(UIView *host, const void *key);
// Several panes on one host, addressed by index; panes past `count` are hidden by FZHideGlassFrom.
UIVisualEffectView *FZGlassAt(UIView *host, NSUInteger index);
void FZHideGlassFrom(UIView *host, NSUInteger count);
// Glass takes its shape from cornerConfiguration on iOS 26; layer.cornerRadius is the fallback.
void FZShapeGlass(UIView *glass, CGFloat radius, BOOL capsule);

