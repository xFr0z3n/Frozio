// chroma.pw's Visualizer (the player's ⋯ → Artwork → Visualizer) and Lyrics shaders, rebuilt for Frozio in Metal:
// the same names and roles, Frozio's own shaders (chroma.pw's code is PolyForm Strict and isn't used). Each moves
// with the music (FZRAudioLevels) in the cover's colours:
// They draw behind the whole player, the cover staying on top (as chroma.pw's do), and lean with the phone:
// - Bars: an LED wall, each column lit from the middle by its part of the spectrum;
// - Nebula: smoke that thickens with the bass;
// - Halo: rings stepping out from the cover, quicker as the music gets louder and on every beat;
// - Poster: the cover across the screen in a few of its own colours, pushed by the beat, split by the highs;
// - Cut: the cover across the screen in strips that slide with their part of the spectrum.
// Shuffle Shaders moves on to another every 20 s, crossfading.
#pragma once
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, FZRVisualizerStyle) {
    FZRVisualizerBars = 0,
    FZRVisualizerNebula,
    FZRVisualizerHalo,
    FZRVisualizerPoster,
    FZRVisualizerCut,
    FZRVisualizerShuffle,   // a setting, not a shader: one after another
    // Backgrounds of the lyrics styles (FZRLyricsStyle), not in the Visualizer menu.
    FZRVisualizerNight = 10,
    FZRVisualizerInferno,
    FZRVisualizerHologram,
    FZRVisualizerChrome,
    FZRVisualizerBlueprint,
};

extern NSString *const FZRKeyVisualizerStyle;   // "fz.redesign.visualizer.style", FZRVisualizerStyle (Shuffle)
NSArray<NSString *> *FZRVisualizerStyleNames(void);   // "Bars", …, "Shuffle Shaders"

@interface FZRVisualizerView : UIView
@property (nonatomic) FZRVisualizerStyle style;
@property (nonatomic) CGFloat intensity;   // 0…1 how strongly the music moves it (default 1)
@property (nonatomic) BOOL paused;
@property (nonatomic) CGFloat dim;          // 0…1 multiplies the picture (default 1)
@property (nonatomic) CGRect coverRect;     // where the cover is, in 0…1 of the view (Halo's rings start there)
@property (nonatomic) BOOL tilts;           // leans with the phone (default YES)
@property (nonatomic, readonly) BOOL available;   // NO without Metal
- (void)setImage:(UIImage *)image;
@end
