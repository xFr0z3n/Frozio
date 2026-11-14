// Adapted from taurus/tweak/Sources/Shared/ArtistBlock/ArtistBlockSettings.m @ fe3211c (GPL-3.0).
// Renamed SG→FZ; artists are names (NaviMus reports no IDs), and a name can also be typed in.
#import "ArtistBlock/FZArtistBlock.h"
#import "Settings/Kit/FZPage.h"
#import "Settings/Kit/FZPageStyle.h"
#import "Settings/Kit/FZKitCore.h"

typedef NS_ENUM(NSInteger, FZArtistSection) {
    FZArtistSectionSwitch,
    FZArtistSectionMode,
    FZArtistSectionAdd,
    FZArtistSectionList,
    FZArtistSectionCount,
};

@interface FZArtistBlockSettingsPage : FZPage
@end

@implementation FZArtistBlockSettingsPage {
    NSArray<NSString *> *_blocked;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Blocked Artists";
    _blocked = FZBlockedArtists();
    return self;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    FZInsetForBars(self.tableView);
}

- (void)reload {
    _blocked = FZBlockedArtists();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return FZArtistSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == FZArtistSectionMode) return 2;
    if (section == FZArtistSectionAdd) return 2;
    if (section == FZArtistSectionList) return MAX((NSInteger)_blocked.count, 1);
    return 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    if (section == FZArtistSectionMode) return FZSectionHeader(table, @"Skip when the artist is");
    if (section == FZArtistSectionList) return FZSectionHeader(table, @"Blocked");
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == FZArtistSectionMode || section == FZArtistSectionList ? FZSectionHeaderHeight : FZSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return section == FZArtistSectionSwitch ? FZSectionFooter(table, [self switchFooter]) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return section == FZArtistSectionSwitch ? FZSectionFooterHeight(table, [self switchFooter]) : CGFLOAT_MIN;
}

- (NSString *)switchFooter {
    return @"A song by a blocked artist is skipped as it starts playing, the way Next on the lock screen skips. "
           @"Artists are matched by name, as NaviMus shows them.";
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = FZDequeueCell(table, @"artist");
    switch (path.section) {
        case FZArtistSectionSwitch: {
            FZFillCell(cell, @"Skip blocked artists", nil, nil, nil);
            UISwitch *toggle = [UISwitch new];
            toggle.onTintColor = FZGreen();
            toggle.on = FZHidden(FZKeyArtistBlock);
            [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            break;
        }
        case FZArtistSectionMode: {
            BOOL featured = path.row == 1;
            FZFillCell(cell, featured ? @"Main or featured" : @"The main artist",
                       featured ? @"Any name in the credit" : @"The first name in the credit", nil, nil);
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            if (featured == FZHidden(FZKeyArtistBlockFeatured)) {
                UIImageView *tick = FZSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
                tick.tintColor = FZAccentMark();
                cell.accessoryView = tick;
            }
            break;
        }
        case FZArtistSectionAdd:
            if (path.row == 0) FZFillCell(cell, @"Block from what's playing…", nil, nil, @"person.crop.circle.badge.xmark");
            else FZFillCell(cell, @"Block by name…", nil, nil, @"character.cursor.ibeam");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        default:
            if (!_blocked.count) {
                FZFillCell(cell, @"No one yet", nil, FZGrey(), nil);
                break;
            }
            FZFillCell(cell, _blocked[(NSUInteger)path.row], nil, nil, nil);
            break;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == FZArtistSectionList && _blocked.count > 0;
}

- (NSString *)tableView:(UITableView *)table titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)path {
    return @"Unblock";
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    FZUnblockArtist(_blocked[(NSUInteger)path.row]);
    [self reload];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == FZArtistSectionMode) {
        FZSetEnabled(FZKeyArtistBlockFeatured, path.row == 1);
        [self reload];
    } else if (path.section == FZArtistSectionAdd) {
        if (path.row == 0) [self pickFromPlaying:[table cellForRowAtIndexPath:path]];
        else [self askForName];
    }
}

- (void)pickFromPlaying:(UIView *)source {
    NSString *credit = FZPlayingArtistCredit();
    if (!credit) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nothing playing"
                                                                      message:@"Play a song by the artist first, then come back here."
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    // The whole credit first when it names more than one artist, then each name in it.
    NSArray<NSString *> *names = FZArtistsInCredit(credit);
    NSMutableArray<NSString *> *choices = [NSMutableArray array];
    if (names.count > 1) [choices addObject:credit];
    [choices addObjectsFromArray:names];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Block"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [choices enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
        BOOL featured = names.count > 1 && index > 1;
        NSString *title = featured ? [NSString stringWithFormat:@"%@ (featured)", name] : name;
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            FZBlockArtist(name);
            [self reload];
        }];
        action.enabled = !FZArtistBlocked(name);
        [sheet addAction:action];
    }];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = source;
    sheet.popoverPresentationController.sourceRect = source.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)askForName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Block an artist"
                                                                  message:@"The name as NaviMus shows it."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Artist";
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Block" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        FZBlockArtist(weakAlert.textFields.firstObject.text);
        [self reload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggled:(UISwitch *)toggle {
    FZSetEnabled(FZKeyArtistBlock, toggle.on);
}

@end

UIViewController *FZArtistBlockPage(void) {
    return [FZArtistBlockSettingsPage new];
}
