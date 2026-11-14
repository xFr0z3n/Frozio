// Accent storage and picker adapted from taurus/tweak/Sources/Redesigned/Kit/SGRAccent.x @ fe3211c
// (GPL-3.0). The UIColor/CALayer green-swapping hooks are not ported (Spotify-specific).
#import "Redesign/Kit/FZRAccent.h"
#import "Settings/Kit/FZKitCore.h"
#import "Settings/Kit/FZPageStyle.h"
#import <math.h>

NSNotificationName const FZRAccentDidChangeNotification = @"FZRAccentDidChange";
static const NSInteger kDefaultAccent = 0x37F200;

static NSInteger FZChosenAccent(void) {
    NSInteger rgb = FZInt(FZAccentKey, kDefaultAccent);
    return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : kDefaultAccent;
}

UIColor *FZRAccentColor(void) {
    NSInteger rgb = FZChosenAccent();
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

NSString *FZRAccentLabel(void) {
    NSInteger rgb = FZChosenAccent();
    return rgb == kDefaultAccent ? @"Redesign green" : [NSString stringWithFormat:@"#%06lX", (long)rgb];
}

static void FZStoreAccent(NSInteger rgb) {
    FZSetInt(FZAccentKey, rgb);
    FZLogNS(@"accent: now #%06lX", (long)rgb);
    [NSNotificationCenter.defaultCenter postNotificationName:FZRAccentDidChangeNotification object:nil];
}

@interface FZRAccentPicker : NSObject <UIColorPickerViewControllerDelegate>
@end

@implementation FZRAccentPicker
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![picker.selectedColor getRed:&r green:&g blue:&b alpha:&a]) return;
    NSInteger rgb = ((NSInteger)lround(MIN(1, MAX(0, r)) * 255) << 16)
                  | ((NSInteger)lround(MIN(1, MAX(0, g)) * 255) << 8)
                  | (NSInteger)lround(MIN(1, MAX(0, b)) * 255);
    FZStoreAccent(rgb);
}
@end

void FZRPickAccent(void) {
    static FZRAccentPicker *delegate;
    if (!delegate) delegate = [FZRAccentPicker new];
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.supportsAlpha = NO;
    picker.selectedColor = FZRAccentColor();
    picker.delegate = delegate;
    picker.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [FZTopController() presentViewController:picker animated:YES completion:nil];
}

void FZRResetAccent(void) {
    FZStoreAccent(kDefaultAccent);
}
