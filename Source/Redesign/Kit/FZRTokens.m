// Adapted from taurus/tweak/Sources/Redesigned/Kit/SGRTokens.m @ fe3211c (GPL-3.0, github.com/xFr0z3n/taurus).
#import <CoreText/SFNTLayoutTypes.h>
#import <math.h>
#import "Settings/Kit/FZKitCore.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Redesign/Kit/FZRAccent.h"

const CGFloat FZRSideMargin = 16;
const CGFloat FZRGrid = 8;
const CGFloat FZRRadiusArtwork = 12;
const CGFloat FZRRadiusCard = 16;
const CGFloat FZRRadiusCover = 8;
const CGFloat FZRRadiusThumb = 6;
const CGFloat FZRGlassCircleSize = 44;
const CGFloat FZRActionHeight = 48;
const CGFloat FZRActionSpacing = 12;
const CGFloat FZRGlassSpacing = 16;
const NSTimeInterval FZRCrossfade = 0.35;

// A layout spring settles in about this long without overshooting; a press gives a little back.
static const NSTimeInterval kLayoutDuration = 0.45, kPressDuration = 0.32;
static const CGFloat kPressDamping = 0.62;
// A tap bringing something back answers a touch slower and with a little bounce; something leaving goes quickly.
static const NSTimeInterval kRespondDuration = 0.4, kExitDuration = 0.26;
static const CGFloat kRespondDamping = 0.78, kExitDamping = 1;

UIColor *FZRPrimary(void) {
    return UIColor.whiteColor;
}

UIColor *FZRSecondary(void) {
    return [UIColor colorWithWhite:1 alpha:FZRIncreaseContrast() ? 0.80 : 0.65];
}

UIColor *FZRTertiary(void) {
    return [UIColor colorWithWhite:1 alpha:FZRIncreaseContrast() ? 0.60 : 0.40];
}

// Read per call: the accent is stored as it is picked, and the colour row reads it the same way.
UIColor *FZRAccent(void) {
    return FZRAccentColor(); // never nil in Frozio: defaults to the redesign green #37F200
}

NSInteger FZRAccentRGB(void) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![FZRAccent() getRed:&r green:&g blue:&b alpha:&a]) return -1;
    return ((NSInteger)lround(r * 255) << 16) | ((NSInteger)lround(g * 255) << 8) | (NSInteger)lround(b * 255);
}

NSString *const FZRPlainCheckIdentifier = @"sg.plaincheck";

UIColor *FZRNeutralField(void) {
    return [UIColor colorWithRed:0x12 / 255.0 green:0x12 / 255.0 blue:0x12 / 255.0 alpha:1];
}

UIColor *FZRSolidGlassFill(void) {
    return [UIColor colorWithWhite:1 alpha:0.16];
}

UIColor *FZRHairline(void) {
    return [UIColor colorWithWhite:1 alpha:FZRIncreaseContrast() ? 0.20 : 0.12];
}

UIColor *FZRElevated(UIColor *field) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![field getRed:&r green:&g blue:&b alpha:&a]) return [UIColor colorWithWhite:1 alpha:0.08];
    // 12% towards white keeps a card on a black field clear of the greys FZRAmoled.x turns black.
    CGFloat lift = 0.12;
    return [UIColor colorWithRed:r + (1 - r) * lift green:g + (1 - g) * lift blue:b + (1 - b) * lift alpha:1];
}

UIFont *FZRFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (largest && UIContentSizeCategoryCompareToCategory(current, largest) == NSOrderedDescending) current = largest;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    CGFloat size = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
    return [UIFont systemFontOfSize:size weight:weight];
}

UIFont *FZRMonospacedDigitsFont(UIFont *font) {
    if (!font) return nil;
    NSArray *features = @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType), UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}];
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute: features}];
    return [UIFont fontWithDescriptor:descriptor size:font.pointSize];
}

BOOL FZRReduceMotion(void) {
    return UIAccessibilityIsReduceMotionEnabled();
}

BOOL FZRReduceTransparency(void) {
    return UIAccessibilityIsReduceTransparencyEnabled();
}

BOOL FZRIncreaseContrast(void) {
    return UIAccessibilityDarkerSystemColorsEnabled();
}

void FZRAnimate(FZRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (!animations) return;
    if (motion != FZRMotionFade && FZRReduceMotion()) {
        [UIView performWithoutAnimation:animations];
        if (completion) completion(YES);
        return;
    }
    UIViewAnimationOptions options = UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;
    switch (motion) {
        case FZRMotionLayout:
            [UIView animateWithDuration:kLayoutDuration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case FZRMotionPress:
            [UIView animateWithDuration:kPressDuration delay:0 usingSpringWithDamping:kPressDamping initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case FZRMotionFade:
            [UIView animateWithDuration:FZRCrossfade delay:0 options:options | UIViewAnimationOptionCurveEaseInOut animations:animations completion:completion];
            break;
        case FZRMotionRespond:
            [UIView animateWithDuration:kRespondDuration delay:0 usingSpringWithDamping:kRespondDamping initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case FZRMotionExit:
            [UIView animateWithDuration:kExitDuration delay:0 usingSpringWithDamping:kExitDamping initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
    }
}

void FZRAnimateLayout(UIView *host, void (^animations)(void), void (^completion)(BOOL finished)) {
    void (^move)(void) = ^{
        if (animations) animations();
        [host layoutIfNeeded];
    };
    if (FZRReduceMotion()) {
        [UIView performWithoutAnimation:move];
        if (completion) completion(YES);
        return;
    }
    UIViewAnimationOptions options = UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
        | UIViewAnimationOptionLayoutSubviews;
    [UIView animateWithDuration:kLayoutDuration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:move completion:completion];
}
