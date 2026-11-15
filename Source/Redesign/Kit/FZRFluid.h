// Adapted from taurus/tweak/Sources/Redesigned/Kit/SGRFluid.h @ fe3211c (GPL-3.0, github.com/xFr0z3n/taurus). Renamed SG→FZ.
// Fluid artwork: the cover itself, blurred and slowly warped behind the player. Four copies of a
// blurred, saturated cover, each far larger than the screen, turn about different centers at different
// speeds, two each way; where they overlap the picture seems to flow. A shade over the bottom keeps the
// controls legible.
//
// Like FZRFlow.h it is all Core Animation: repeating rotations the render server plays, nothing drawn
// per frame by the app. Stopping holds every copy where it is, and starting again carries on from there.
//
// The Player page tunes it with five sliders (Redesigned/Player/PlayerSettings.m), stored as whole numbers under
// fz.redesign.fluid.<speed|warp|blur|saturation|brightness>. Every layer follows a change at once.
//
// Threading: main thread only; the blur runs off it.
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, FZRFluidSetting) {
    FZRFluidSpeed,        // percent of the turns' speed
    FZRFluidWarp,         // percent of how far apart the copies turn and how much the upper three show
    FZRFluidBlur,         // the blur's strength, 1.25 px of radius each on the 128 px cover
    FZRFluidSaturation,   // percent
    FZRFluidBrightness,   // percent, under the ceiling that keeps the player's text legible
    FZRFluidSettingCount,
};
typedef struct { NSInteger least, most, step, standard; } FZRFluidLimits;
FZRFluidLimits FZRFluidLimitsOf(FZRFluidSetting setting);
NSInteger FZRFluidValue(FZRFluidSetting setting);   // held to its limits
// Stores the value and posts FZRFluidSettingsDidChangeNotification on the main thread.
void FZRSetFluidValue(FZRFluidSetting setting, NSInteger value);
void FZRResetFluidSettings(void);   // all five back to their standard values, one notification
extern NSNotificationName const FZRFluidSettingsDidChangeNotification;

@interface FZRFluidLayer : CALayer
// The cover, blurred off the main thread and crossfaded in. The same image again is a no-op.
- (void)setArtwork:(UIImage *)image animated:(BOOL)animated;
// Turning, or held still where it is. Off to begin with.
@property (nonatomic) BOOL moving;
// The part of the layer on screen, in its own coordinates: the copies turn about points in it and the
// shade darkens its bottom, whatever the layer bleeds past it. The whole layer while empty.
@property (nonatomic) CGRect visibleRect;
@end
