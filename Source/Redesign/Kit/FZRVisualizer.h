// chroma.pw's Visualizer (the player's ⋯ → Artwork → Visualizer) and Lyrics shaders, rebuilt for Frozio in Metal:
// the same names and roles, Frozio's own shaders (chroma.pw's code is PolyForm Strict and isn't used). Each moves
// with the music (FZRAudioLevels) in the cover's colours:
// - Bars: a mirrored spectrum, 28 bars, glowing;
// - Nebula: drifting clouds (domain-warped noise) that brighten with the music;
// - Halo: the cover in a circle, ringed by the spectrum, the ring breathing with the bass;
// - Poster: the cover posterised into its own colours, pushed by the beat, its colours split by the highs;
// - Cut: the cover in strips that slide with their part of the spectrum.
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
};

extern NSString *const FZRKeyVisualizerStyle;   // "fz.redesign.visualizer.style", FZRVisualizerStyle (Shuffle)
NSArray<NSString *> *FZRVisualizerStyleNames(void);   // "Bars", …, "Shuffle Shaders"

@interface FZRVisualizerView : UIView
@property (nonatomic) FZRVisualizerStyle style;
@property (nonatomic) CGFloat intensity;   // 0…1 how strongly the music moves it (default 1)
@property (nonatomic) BOOL paused;
@property (nonatomic, readonly) BOOL available;   // NO without Metal
- (void)setImage:(UIImage *)image;
@end
