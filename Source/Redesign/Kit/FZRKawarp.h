// Fluid artwork: the cover blurred and slowly warped, as chroma.pw's player background. A Metal port of Kawarp
// (github.com/better-lyrics/kawarp @ f4a4b29, MIT, Copyright (c) 2026 Better Lyrics), the library chroma.pw credits
// for it: the cover drawn at 128 × 128, its dark areas tinted (0.157, 0.157, 0.235) at 15 %, Kawase blur passes
// (offset i + 0.5), then every frame a two-octave simplex domain warp weighted to the centre and an output pass with
// a light vignette, saturation and grain. A new cover crossfades in over 1 s on a cosine ease. Kawarp's defaults:
// warp 1.0, 8 blur passes, saturation 1.5, grain 0.008, speed 1.0. Brightness is chroma.pw's addition.
#pragma once
#import <UIKit/UIKit.h>

@interface FZRKawarpView : UIView
@property (nonatomic) CGFloat speed;        // 0…16, eased toward as Kawarp does (default 1)
@property (nonatomic) CGFloat warp;         // 0…1 (default 1)
@property (nonatomic) NSInteger blurPasses; // 0…40 (default 8)
@property (nonatomic) CGFloat saturation;   // 0…3 (default 1.5)
@property (nonatomic) CGFloat grain;        // 0…0.1 (default 0.008)
@property (nonatomic) CGFloat brightness;   // 0…2 (default 1)
@property (nonatomic) BOOL paused;          // holds the motion (Reduce Motion, off screen)
/// NO when Metal isn't available; the owner then shows something else.
@property (nonatomic, readonly) BOOL available;
- (void)setImage:(UIImage *)image animated:(BOOL)animated;
@end

/// chroma.pw's Fluid artwork settings (Frozio settings → Appearance → Redesigned pages → Fluid artwork), applied to
/// a view; the presets it offers.
extern NSString *const FZRKeyFluidSpeed, *const FZRKeyFluidWarp, *const FZRKeyFluidGrain, *const FZRKeyFluidBlur,
                      *const FZRKeyFluidSaturation, *const FZRKeyFluidBrightness;
extern NSNotificationName const FZRFluidLookDidChangeNotification;
void FZRApplyFluidLook(FZRKawarpView *view);
UIViewController *FZRFluidOptionsPage(void);
