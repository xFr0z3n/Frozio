// How the player's lyrics look: chroma.pw's Lyrics → styles. Default is Frozio's (taurus's) look. Poster, Neon,
// Highlighter, Subtitles and Novel take the values chroma.pw ships for its built-in styles (font, weight, case, colours,
// alignment, anchor, glow, dim, blur); its own code isn't used. Inferno, Hologram, Chrome and Blueprint are Frozio's,
// after the looks of chroma.pw's Workshop styles (those are downloaded from chroma.pw with its Plus and aren't
// included), each with a shader behind the lines (FZRVisualizer's backgrounds) moving with the music.
#pragma once
#import <UIKit/UIKit.h>

extern NSString *const FZRKeyLyricsStyle;   // "fz.redesign.lyrics.style", a style's key ("default")

@interface FZRLyricsStyle : NSObject
@property (nonatomic, readonly, copy) NSString *key, *name;
@property (nonatomic, readonly) UIFontDescriptorSystemDesign design;
@property (nonatomic, readonly) UIFontWeight weight;
@property (nonatomic, readonly) BOOL italic, condensed, uppercase;
@property (nonatomic, readonly) CGFloat tracking;            // em
@property (nonatomic, readonly, copy) NSArray<UIColor *> *sung;   // one colour, or a gradient down each line; nil = accent
@property (nonatomic, readonly) UIColor *unsung;
@property (nonatomic, readonly) BOOL outline;                // the other lines as outlines
@property (nonatomic, readonly) UIColor *glow;               // nil = none
@property (nonatomic, readonly) CGFloat glowRadius;
@property (nonatomic, readonly) NSTextAlignment alignment;
@property (nonatomic, readonly) CGFloat anchor;              // where the sung line sits, 0…1 of the lyrics' height
@property (nonatomic, readonly) CGFloat dim;                 // the other lines' opacity
@property (nonatomic, readonly) CGFloat blur;                // × the default blur per line
@property (nonatomic, readonly) UIColor *mark;               // a marker behind the sung line (Highlighter, Subtitles)
@property (nonatomic, readonly) BOOL pill;                   // the marker is a rounded pill rather than a highlight
@property (nonatomic, readonly) BOOL scanlines;              // Hologram's lines through the text
@property (nonatomic, readonly) NSInteger background;        // FZRVisualizerStyle behind the lyrics, -1 = none
+ (NSArray<FZRLyricsStyle *> *)all;
+ (FZRLyricsStyle *)current;
- (UIFont *)fontOfSize:(CGFloat)size;
/// The sung line's text colour: plain, or a gradient image as a pattern for a line `lineHeight` tall.
- (UIColor *)sungColorForLineHeight:(CGFloat)lineHeight;
@end
