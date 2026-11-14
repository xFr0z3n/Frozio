// Adapted from taurus/tweak/Sources/Settings/SGPage.m (GPL-3.0, github.com/xFr0z3n/taurus).
#import "FZPage.h"
#import "FZPageStyle.h"
#import "Settings/Kit/FZKitCore.h"


@implementation FZPage

// Inset grouped cards on the redesign's black, a hairline between the rows of a card.
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = FZPageBackground();
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    self.tableView.sectionHeaderTopPadding = 0;
}


@end

void FZRegisterPages(void) {
    // Frozio: NaviMus's navigation stacks belong to SwiftUI (SwiftUI.UIKitNavigationController, see the
    // screen census), and pushing a foreign controller onto them would desync SwiftUI's path. Frozio's
    // pages therefore open in their own presented navigation controller and push only inside it.
}

void FZShowPage(UIViewController *owner, UIViewController *page) {
    if ([owner isKindOfClass:FZPage.class] && owner.navigationController) {
        [owner.navigationController pushViewController:page animated:YES];
        return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [owner presentViewController:nav animated:YES completion:nil];
}
