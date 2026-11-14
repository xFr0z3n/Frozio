// Adapted from taurus/tweak/Sources/Redesigned/Kit/SGRTokens.h @ fe3211c (GPL-3.0, github.com/xFr0z3n/taurus).
#import <UIKit/UIKit.h>

extern const CGFloat FZRSideMargin;      // 16, the page's side margin
extern const CGFloat FZRGrid;            // 8, every gap is a multiple of it
extern const CGFloat FZRRadiusArtwork;   // 12, the player's cover
extern const CGFloat FZRRadiusCard;      // 16, a content card
extern const CGFloat FZRRadiusCover;     // 8, a release cover in a list
extern const CGFloat FZRRadiusThumb;     // 6, a row's thumbnail up to 64pt
extern const CGFloat FZRGlassCircleSize; // 44, a round glass behind a top bar button
extern const CGFloat FZRActionHeight;    // 48, a button of the action row under a hero
extern const CGFloat FZRActionSpacing;   // 12, between the buttons of an action row
extern const CGFloat FZRGlassSpacing;    // 16, how near two glass shapes merge in one container
extern const NSTimeInterval FZRCrossfade;   // 0.35, a new image or field colour fading in

UIColor *FZRPrimary(void);      // white
UIColor *FZRSecondary(void);    // white 65%, 80% with Increase Contrast
UIColor *FZRTertiary(void);     // white 40%, 60% with Increase Contrast
UIColor *FZRAccent(void);       // fz.redesign.accent, default #37F200
NSInteger FZRAccentRGB(void);   // that colour as 0xRRGGBB, for following the cover (PlayerCoverAccent.x)
// The view FZRPlainCheck.x marks the stand-in checkmark with, for the player to tint it too.
extern NSString *const FZRPlainCheckIdentifier;
UIColor *FZRNeutralField(void); // #121212, the field before a colour arrives; FZRAmoled.x turns it black
// Where glass cannot be (Reduce Transparency), the shape it would have had: white 16% over the field.
UIColor *FZRSolidGlassFill(void);
// A content surface on the field (a card), a step lighter than the field it sits on.
UIColor *FZRElevated(UIColor *field);
UIColor *FZRHairline(void);

UIFont *FZRFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest);
// The same font with digits of one width, so a time or a count does not twitch as it changes.
UIFont *FZRMonospacedDigitsFont(UIFont *font);

BOOL FZRReduceMotion(void);
BOOL FZRReduceTransparency(void);
BOOL FZRIncreaseContrast(void);

typedef NS_ENUM(NSInteger, FZRMotion) {
    FZRMotionLayout,   // a spring with no overshoot, for anything moving or resizing
    FZRMotionPress,    // a spring with a little bounce, for press feedback
    FZRMotionFade,     // an ease in and out over FZRCrossfade, kept under Reduce Motion
    FZRMotionRespond,  // a spring with a touch of bounce, for a tap bringing something back
    FZRMotionExit,     // a quick ease out, for something leaving the screen
};
void FZRAnimate(FZRMotion motion, void (^animations)(void), void (^completion)(BOOL finished));
// A layout spring: runs `animations`, then lays `host` out within it. Under Reduce Motion both are instant.
void FZRAnimateLayout(UIView *host, void (^animations)(void), void (^completion)(BOOL finished));
