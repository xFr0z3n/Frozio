// Adapted from taurus/tweak/Sources/Settings/SGPageStyle.h (GPL-3.0, github.com/xFr0z3n/taurus).
#import <UIKit/UIKit.h>

UIColor *FZGrey(void);
UIColor *FZGreen(void);
// The redesign accent (fz.redesign.accent, default #37F200), for a tick or a stroke.
UIColor *FZAccentMark(void);
// A foreground that reads on FZAccentMark, black or white by its brightness.
UIColor *FZOnAccent(void);
UIColor *FZRed(void);
UIColor *FZPageBackground(void);
UIColor *FZCardBackground(void);
UIFont *FZTitleFont(void);
UIFont *FZSubtitleFont(void);
// Takes 13pt/11pt label fonts off a host list, once, so the pages match it (unused in Frozio so far).
void FZAdoptFonts(UIView *list, UIView *exclude);

UIImageView *FZSymbolView(NSString *name, CGFloat size, UIImageSymbolWeight weight, CGFloat box);
// A symbol on a rounded grey square, the leading icon of a row that opens a page.
UIImage *FZTileImage(NSString *symbol);
// A grey note in a wrapper view, for a table header or footer; FZFitNote sizes it to its text.
UIView *FZNote(NSString *text);
void FZFitNote(UITableView *table, UIView *wrapper, CGFloat top, CGFloat bottom);
// The now playing bar and the tab bar float over the content, so a page insets itself under them.
void FZInsetForBars(UITableView *table);

extern const CGFloat FZSectionHeaderHeight;
extern const CGFloat FZSectionGap;   // above a section with no header, so its card does not touch the one before
void FZFillCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIColor *color, NSString *symbolName);
UIView *FZSectionHeader(UITableView *table, NSString *title);
UIView *FZSectionFooter(UITableView *table, NSString *text);
CGFloat FZSectionFooterHeight(UITableView *table, NSString *text);
UITableViewCell *FZDequeueCell(UITableView *table, NSString *identifier);

void FZOpenURL(NSString *url);
extern NSString *const FZRepoURL;
extern NSString *const FZAccentKey;   // "fz.redesign.accent", 0xRRGGBB
// The controller on top of the key window, through whatever is presented over it.
UIViewController *FZTopController(void);

void FZPresentDark(UIViewController *vc);
