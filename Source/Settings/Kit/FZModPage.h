// Adapted from taurus/tweak/Sources/Settings/SGModPage.h (GPL-3.0, github.com/xFr0z3n/taurus).
// A page of sections of rows, the shape of every feature's settings page.
#import "FZPage.h"

@interface FZModRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *key;
@property (nonatomic) BOOL defaultOn;
@property (nonatomic) BOOL flag;
@property (nonatomic) BOOL forceOff;
@property (nonatomic, copy) UIViewController *(^page)(void);
@property (nonatomic, copy) NSString *(^value)(void);
@property (nonatomic, copy) void (^action)(void);
@property (nonatomic, copy) NSString *warning;
@property (nonatomic, copy) void (^changed)(BOOL on);   // after the switch is stored; the page reloads
@property (nonatomic, strong) UIColor *color;   // title, subtitle and symbol, for a warning row
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, strong) UIImage *image;
// A switch row that changes the whole app draws FZGlowSwitch instead of a UISwitch.
@property (nonatomic) BOOL glows;
// An ⓘ button beside the row's switch, whose tap reads this out under the row's title.
@property (nonatomic, copy) NSString *info;
@property (nonatomic, copy) BOOL (^visible)(void);
// A choice row's: a line under each name in its list, in the same order, and what runs once one is stored.
@property (nonatomic, copy) NSArray<NSString *> *choiceNotes;
@property (nonatomic, copy) NSString *choiceFooter;   // under a choice row's list
@property (nonatomic, copy) void (^chosen)(NSInteger index);
@property (nonatomic) double minimum, maximum, step;
@property (nonatomic, copy) double (^number)(void);
@property (nonatomic, copy) void (^setNumber)(double value);
@property (nonatomic, copy) NSString *(^format)(double value);
@property (nonatomic, copy) double (^progress)(void);
@property (nonatomic, copy) NSNotificationName refreshOn;
// The key of a switch this row waits on: until it is on, the row is dimmed and cannot be used.
@property (nonatomic, copy) NSString *waitsOn;
@end

@interface FZModSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<FZModRow *> *rows;
@property (nonatomic, copy) NSString *footer;
@end

@interface FZModPage : FZPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray<FZModSection *> *)sections footer:(NSString *)footer;
// Re-reads every row's visible block so rows that come and go on their own appear or leave now.
- (void)refreshVisibility;
@end

// The intro of every page whose switches the hooks read at launch.
extern NSString *const FZRestartNote;

FZModRow *FZSwitchRow(NSString *title, NSString *subtitle, NSString *key);   // on until switched off
FZModRow *FZHideRow(NSString *title, NSString *subtitle, NSString *key);     // off until switched on
// A switch for something the mod adds rather than takes away: off until it is asked for.
FZModRow *FZOptionRow(NSString *title, NSString *subtitle, NSString *key);
// A switch whose work is not finished: turning it on says so first, and offers the repo.
FZModRow *FZUnstableRow(NSString *title, NSString *subtitle, NSString *key, NSString *warning);
FZModRow *FZFlagRow(NSString *title, NSString *key);   // forces one of Spotify's flags on
FZModRow *FZKillRow(NSString *title, NSString *key);   // forces a flag Spotify ships on off
FZModRow *FZStatRow(NSString *title, NSString *(^value)(void));
FZModRow *FZActionRow(NSString *title, NSString *subtitle, void (^action)(void));
// Red, with a warning symbol: something is wrong and tapping the row says what to do about it.
FZModRow *FZWarningRow(NSString *title, NSString *subtitle, void (^action)(void));
FZModRow *FZPageRow(NSString *title, UIViewController *(^page)(void));
FZModRow *FZChoiceRow(NSString *title, NSString *subtitle, NSString *key, NSArray<NSString *> *choices, NSInteger fallback);
// A title and a value that opens a menu of choices; nothing is stored here, `chosen` does that.
FZModRow *FZMenuRow(NSString *title, NSArray<NSString *> *choices, NSString *(^value)(void), void (^chosen)(NSInteger index));
FZModRow *FZSliderRow(NSString *title, NSString *subtitle, double minimum, double maximum, double step,
                      double (^get)(void), void (^set)(double value), NSString *(^format)(double value));
FZModRow *FZLinkRow(NSString *title, NSString *subtitle, NSString *url);
FZModRow *FZStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void));
FZModSection *FZSection(NSString *title, NSArray<FZModRow *> *rows);
FZModSection *FZNotedSection(NSString *title, NSArray<FZModRow *> *rows, NSString *footer);
// Gives a row its leading symbol, drawn on a tile unless the row has a colour of its own.
FZModRow *FZWithSymbol(FZModRow *row, NSString *symbol);
