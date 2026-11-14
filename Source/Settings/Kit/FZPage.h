// Adapted from taurus/tweak/Sources/Settings/SGPage.h (GPL-3.0, github.com/xFr0z3n/taurus).
// The base of every Frozio settings page.
#import <UIKit/UIKit.h>

@interface FZPage : UITableViewController
@end

// Prepares page presentation; called once at load.
void FZRegisterPages(void);
// Pushes inside Frozio's own navigation controller, presents a new one otherwise.
void FZShowPage(UIViewController *owner, UIViewController *page);
