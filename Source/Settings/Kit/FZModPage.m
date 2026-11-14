// Adapted from taurus/tweak/Sources/Settings/SGModPage.m (GPL-3.0, github.com/xFr0z3n/taurus).
#import <CoreText/SFNTLayoutTypes.h>
#import "FZModPage.h"
#import "FZPageStyle.h"
#import "FZGlowSwitch.h"
#import "Settings/Kit/FZKitCore.h"

NSString *const FZRestartNote = @"Changes apply after you restart Frozio.";

@implementation FZModRow
@end

@implementation FZModSection
@end

FZModRow *FZSwitchRow(NSString *title, NSString *subtitle, NSString *key) {
    FZModRow *row = [FZModRow new];
    row.title = title;
    row.subtitle = subtitle;
    row.key = key;
    row.defaultOn = YES;
    return row;
}

FZModRow *FZHideRow(NSString *title, NSString *subtitle, NSString *key) {
    FZModRow *row = FZSwitchRow(title, subtitle, key);
    row.defaultOn = NO;
    return row;
}

// A switch for something the mod adds rather than takes away: off until it is asked for.
FZModRow *FZOptionRow(NSString *title, NSString *subtitle, NSString *key) {
    FZModRow *row = FZSwitchRow(title, subtitle, key);
    row.defaultOn = NO;
    return row;
}

FZModRow *FZUnstableRow(NSString *title, NSString *subtitle, NSString *key, NSString *warning) {
    FZModRow *row = FZSwitchRow(title, subtitle, key);
    row.warning = warning;
    return row;
}

FZModRow *FZFlagRow(NSString *title, NSString *key) {
    FZModRow *row = FZHideRow(title, nil, key);
    row.flag = YES;
    return row;
}

// A flag Spotify ships on: the switch forces it off.
FZModRow *FZKillRow(NSString *title, NSString *key) {
    FZModRow *row = FZFlagRow(title, key);
    row.forceOff = YES;
    return row;
}

FZModRow *FZStatRow(NSString *title, NSString *(^value)(void)) {
    FZModRow *row = [FZModRow new];
    row.title = title;
    row.value = value;
    return row;
}

FZModRow *FZActionRow(NSString *title, NSString *subtitle, void (^action)(void)) {
    FZModRow *row = [FZModRow new];
    row.title = title;
    row.subtitle = subtitle;
    row.action = action;
    return row;
}

FZModRow *FZWarningRow(NSString *title, NSString *subtitle, void (^action)(void)) {
    FZModRow *row = FZActionRow(title, subtitle, action);
    row.color = FZRed();
    row.symbol = @"exclamationmark.triangle.fill";
    return row;
}

// No subtitle: a list of pages reads as a list, not as a wall of explanations.
FZModRow *FZPageRow(NSString *title, UIViewController *(^page)(void)) {
    FZModRow *row = [FZModRow new];
    row.title = title;
    row.page = page;
    return row;
}

@interface FZChoicePage : FZPage
- (instancetype)initWithTitle:(NSString *)title key:(NSString *)key choices:(NSArray<NSString *> *)choices notes:(NSArray<NSString *> *)notes
                       footer:(NSString *)footer fallback:(NSInteger)fallback chosen:(void (^)(NSInteger index))chosen;
@end

@implementation FZChoicePage {
    NSString *_key;
    NSArray<NSString *> *_choices, *_notes;
    NSInteger _fallback;
    void (^_chosen)(NSInteger index);
    UIView *_footer;
}

- (instancetype)initWithTitle:(NSString *)title key:(NSString *)key choices:(NSArray<NSString *> *)choices notes:(NSArray<NSString *> *)notes
                       footer:(NSString *)footer fallback:(NSInteger)fallback chosen:(void (^)(NSInteger index))chosen {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = title;
    _key = key;
    _choices = choices;
    _notes = notes;
    _fallback = fallback;
    _chosen = chosen;
    _footer = footer ? FZNote(footer) : nil;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (_footer) FZFitNote(self.tableView, _footer, 16, 24);
}


- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    FZInsetForBars(self.tableView);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_choices.count;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = FZDequeueCell(table, @"choice");
    NSUInteger index = (NSUInteger)path.row;
    FZFillCell(cell, _choices[index], index < _notes.count ? _notes[index] : nil, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (path.row == FZInt(_key, _fallback)) {
        UIImageView *tick = FZSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = FZGreen();
        cell.accessoryView = tick;
    }
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:NO];
    FZSetInt(_key, path.row);
    if (_chosen) _chosen(path.row);
    [table reloadData];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

FZModRow *FZChoiceRow(NSString *title, NSString *subtitle, NSString *key, NSArray<NSString *> *choices, NSInteger fallback) {
    FZModRow *row = [FZModRow new];
    row.title = title;
    row.subtitle = subtitle;
    row.value = ^NSString *{
        NSInteger index = FZInt(key, fallback);
        return index >= 0 && index < (NSInteger)choices.count ? choices[(NSUInteger)index] : choices.firstObject;
    };
    __weak FZModRow *weakRow = row;
    row.page = ^UIViewController *{
        return [[FZChoicePage alloc] initWithTitle:title key:key choices:choices notes:weakRow.choiceNotes footer:weakRow.choiceFooter fallback:fallback chosen:weakRow.chosen];
    };
    return row;
}

FZModRow *FZMenuRow(NSString *title, NSArray<NSString *> *choices, NSString *(^value)(void), void (^chosen)(NSInteger index)) {
    FZModRow *row = [FZModRow new];
    row.title = title;
    row.value = value;
    row.action = ^{
        NSString *shown = value ? value() : nil;
        UIAlertController *menu = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [choices enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
            NSString *label = [name isEqualToString:shown] ? [@"✓  " stringByAppendingString:name] : name;
            [menu addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if (chosen) chosen((NSInteger)index);
            }]];
        }];
        [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *host = FZTopController();
        UIPopoverPresentationController *popover = menu.popoverPresentationController;
        if (popover) {
            popover.sourceView = host.view;
            popover.sourceRect = (CGRect){CGPointMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds)), CGSizeZero};
        }
        [host presentViewController:menu animated:YES completion:nil];
    };
    return row;
}

FZModRow *FZSliderRow(NSString *title, NSString *subtitle, double minimum, double maximum, double step,
                      double (^get)(void), void (^set)(double value), NSString *(^format)(double value)) {
    FZModRow *row = [FZModRow new];
    row.title = title;
    row.subtitle = subtitle;
    row.minimum = minimum;
    row.maximum = maximum;
    row.step = step;
    row.number = get;
    row.setNumber = set;
    row.format = format;
    return row;
}

FZModRow *FZLinkRow(NSString *title, NSString *subtitle, NSString *url) {
    return FZActionRow(title, subtitle, ^{ FZOpenURL(url); });
}

FZModRow *FZStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) {
    FZModRow *row = [FZModRow new];
    row.title = title;
    row.subtitle = subtitle;
    row.value = value;
    row.action = action;
    return row;
}

FZModSection *FZSection(NSString *title, NSArray<FZModRow *> *rows) {
    FZModSection *s = [FZModSection new];
    s.title = title;
    s.rows = rows;
    return s;
}

FZModSection *FZNotedSection(NSString *title, NSArray<FZModRow *> *rows, NSString *footer) {
    FZModSection *s = FZSection(title, rows);
    s.footer = footer;
    return s;
}

FZModRow *FZWithSymbol(FZModRow *row, NSString *symbol) {
    row.symbol = symbol;
    return row;
}

static UIView *valueAndChevron(NSString *text) {
    UILabel *label = [UILabel new];
    label.font = FZTitleFont();
    label.textColor = FZGrey();
    label.text = text;
    [label sizeToFit];
    UIImageView *chevron = FZSymbolView(@"chevron.right", 13, UIImageSymbolWeightSemibold, 16);
    CGFloat height = MAX(label.bounds.size.height, chevron.bounds.size.height);
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, label.bounds.size.width + 6 + chevron.bounds.size.width, height)];
    label.center = CGPointMake(label.bounds.size.width / 2, height / 2);
    chevron.center = CGPointMake(box.bounds.size.width - chevron.bounds.size.width / 2, height / 2);
    [box addSubview:label];
    [box addSubview:chevron];
    return box;
}

static BOOL flagRowOn(FZModRow *row) {
    id value = FZFlagOverride(row.key);
    return value && [value boolValue] != row.forceOff;
}

static BOOL flagRowLocked(FZModRow *row) {
    return row.flag && FZLockedFlagValue(row.key, NULL) != nil;
}

static BOOL lockedRowOn(FZModRow *row) {
    id value = FZLockedFlagValue(row.key, NULL);
    return value ? [value boolValue] != row.forceOff : YES;
}

#pragma mark - the slider row

// On the row's step, counted from its minimum, without the float noise of getting there.
static double snapped(FZModRow *row, double value) {
    if (row.step > 0) value = row.minimum + round(round((value - row.minimum) / row.step) * row.step * 1e6) / 1e6;
    return MAX(row.minimum, MIN(row.maximum, value));
}

// Figures that do not shift sideways as they change, in whatever face the titles are in.
static UIFont *tabular(UIFont *font) {
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{
        UIFontDescriptorFeatureSettingsAttribute: @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
                                                     UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}],
    }];
    return [UIFont fontWithDescriptor:descriptor size:font.pointSize];
}

// A step at a time for VoiceOver, or a twentieth of the range where the steps are too fine to swipe through.
@interface FZModSlider : UISlider
@property (nonatomic) float spokenStep;
@end

@implementation FZModSlider

- (void)accessibilityIncrement {
    self.value += self.spokenStep;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)accessibilityDecrement {
    self.value -= self.spokenStep;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

@interface FZModSliderCell : UITableViewCell
+ (CGFloat)heightFor:(FZModRow *)row;
- (void)showRow:(FZModRow *)row;
@end

@implementation FZModSliderCell {
    FZModRow *_row;
    UILabel *_title, *_subtitle, *_value;
    FZModSlider *_slider;
    double _shown;
    BOOL _detents;   // few enough steps that the thumb jumps between them as it is dragged
}

static const CGFloat kSliderTop = 12, kSliderLine = 18, kSliderSubtitle = 14, kSliderGap = 6, kSliderHeight = 28, kSliderBottom = 10;

+ (CGFloat)heightFor:(FZModRow *)row {
    return kSliderTop + kSliderLine + (row.subtitle ? kSliderSubtitle : 0) + kSliderGap + kSliderHeight + kSliderBottom;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _title = [UILabel new];
    _title.textColor = UIColor.whiteColor;
    _title.isAccessibilityElement = NO;
    _subtitle = [UILabel new];
    _subtitle.textColor = FZGrey();
    _subtitle.isAccessibilityElement = NO;
    _value = [UILabel new];
    _value.textColor = FZGrey();
    _value.textAlignment = NSTextAlignmentRight;
    _value.isAccessibilityElement = NO;
    _slider = [FZModSlider new];
    _slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.16];
    [_slider addTarget:self action:@selector(moved) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(released) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    for (UIView *view in @[_title, _subtitle, _value, _slider]) [self.contentView addSubview:view];
    return self;
}

- (void)showRow:(FZModRow *)row {
    _row = row;
    NSInteger count = row.step > 0 ? (NSInteger)lround((row.maximum - row.minimum) / row.step) : 0;
    _detents = count > 0 && count <= 24;
    _title.font = FZTitleFont();
    _subtitle.font = FZSubtitleFont();
    _value.font = tabular(FZTitleFont());
    _title.text = row.title;
    _subtitle.text = row.subtitle;
    _subtitle.hidden = !row.subtitle;
    _slider.minimumTrackTintColor = FZGreen();
    _slider.minimumValue = (float)row.minimum;
    _slider.maximumValue = (float)row.maximum;
    _slider.spokenStep = (float)(count > 0 && count <= 40 ? row.step : snapped(row, row.minimum + (row.maximum - row.minimum) / 20) - row.minimum);
    _shown = snapped(row, row.number());
    _slider.value = (float)_shown;
    _slider.accessibilityLabel = row.title;
    _slider.accessibilityHint = row.subtitle;
    [self showValue];
}

- (void)showValue {
    _value.text = _row.format ? _row.format(_shown) : [NSString stringWithFormat:@"%g", _shown];
    _slider.accessibilityValue = _value.text;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width, side = 16, y = kSliderTop;
    [_value sizeToFit];
    CGFloat valueWidth = MAX(_value.bounds.size.width, 44);
    _value.frame = CGRectMake(width - side - valueWidth, y, valueWidth, kSliderLine);
    _title.frame = CGRectMake(side, y, CGRectGetMinX(_value.frame) - side - 8, kSliderLine);
    y += kSliderLine;
    if (_row.subtitle) {
        _subtitle.frame = CGRectMake(side, y, width - 2 * side, kSliderSubtitle);
        y += kSliderSubtitle;
    }
    _slider.frame = CGRectMake(side, y + kSliderGap, width - 2 * side, kSliderHeight);
}

- (void)moved {
    double value = snapped(_row, _slider.value);
    if (_detents) _slider.value = (float)value;
    if (value == _shown) return;
    _shown = value;
    if (_row.setNumber) _row.setNumber(value);
    [self showValue];
}

- (void)released {
    [_slider setValue:(float)_shown animated:YES];
}

@end

#pragma mark - the progress bar

static const NSInteger kProgressTag = 0x5347;

static void showProgress(UITableViewCell *cell, FZModRow *row, BOOL animated) {
    UIProgressView *bar = (UIProgressView *)[cell viewWithTag:kProgressTag];
    double progress = row.progress ? row.progress() : -1;
    if (progress < 0) {
        [bar removeFromSuperview];
        return;
    }
    if (!bar) {
        bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        bar.tag = kProgressTag;
        bar.progressTintColor = FZGreen();
        bar.trackTintColor = [UIColor colorWithWhite:1 alpha:0.12];
        bar.userInteractionEnabled = NO;
        bar.isAccessibilityElement = NO;   // the row's value says the same
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:bar];
        [NSLayoutConstraint activateConstraints:@[
            [bar.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:16],
            [bar.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-16],
            [bar.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-5],
        ]];
        animated = NO;
    }
    [bar setProgress:(float)MIN(1, progress) animated:animated];
}

#pragma mark - the page

@implementation FZModPage {
    NSArray<FZModSection *> *_sections;
    NSArray<NSArray<FZModRow *> *> *_shown;   // each section's rows that show now (FZModRow.visible)
    UIView *_intro;
    UIView *_footer;
    NSTimer *_ticker;
    BOOL _live;
    NSSet<NSNotificationName> *_refreshOn;
}

- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray<FZModSection *> *)sections footer:(NSString *)footer {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = title;
    _sections = sections;
    _shown = [self rowsToShow];
    _intro = intro ? FZNote(intro) : nil;
    _footer = footer ? FZNote(footer) : nil;
    NSMutableSet<NSNotificationName> *refreshOn = [NSMutableSet set];
    for (FZModSection *s in sections) for (FZModRow *row in s.rows) {
        _live |= row.value && !row.page;
        if (row.refreshOn) [refreshOn addObject:row.refreshOn];
    }
    _refreshOn = refreshOn;
    return self;
}

- (NSArray<NSArray<FZModRow *> *> *)rowsToShow {
    NSMutableArray<NSArray<FZModRow *> *> *shown = [NSMutableArray arrayWithCapacity:_sections.count];
    for (FZModSection *s in _sections) {
        NSMutableArray<FZModRow *> *rows = [NSMutableArray arrayWithCapacity:s.rows.count];
        for (FZModRow *row in s.rows) if (!row.visible || row.visible()) [rows addObject:row];
        [shown addObject:rows];
    }
    return shown;
}

- (BOOL)showRowsThen:(void (^)(void))done {
    NSArray<NSArray<FZModRow *> *> *next = [self rowsToShow];
    if ([next isEqualToArray:_shown]) return NO;
    NSMutableArray<NSIndexPath *> *gone = [NSMutableArray array], *coming = [NSMutableArray array];
    [_sections enumerateObjectsUsingBlock:^(FZModSection *s, NSUInteger section, BOOL *stop) {
        NSArray<FZModRow *> *before = self->_shown[section], *after = next[section];
        [before enumerateObjectsUsingBlock:^(FZModRow *row, NSUInteger i, BOOL *stop) {
            if (![after containsObject:row]) [gone addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:(NSInteger)section]];
        }];
        [after enumerateObjectsUsingBlock:^(FZModRow *row, NSUInteger i, BOOL *stop) {
            if (![before containsObject:row]) [coming addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:(NSInteger)section]];
        }];
    }];
    UITableView *table = self.tableView;
    [table performBatchUpdates:^{
        self->_shown = next;
        [table deleteRowsAtIndexPaths:gone withRowAnimation:UITableViewRowAnimationFade];
        [table insertRowsAtIndexPaths:coming withRowAnimation:UITableViewRowAnimationFade];
    } completion:^(BOOL finished) {
        if (coming.count) {
            CGRect rows = CGRectNull;
            for (NSIndexPath *path in coming) rows = CGRectUnion(rows, [table rectForRowAtIndexPath:path]);
            CGFloat room = table.bounds.size.height - table.adjustedContentInset.top - table.adjustedContentInset.bottom;
            rows.size.height = MIN(rows.size.height, room);
            [table scrollRectToVisible:rows animated:YES];
        }
        if (done) done();
    }];
    return YES;
}

- (NSIndexPath *)pathOf:(UIView *)control {
    UIView *view = control;
    while (view && ![view isKindOfClass:UITableViewCell.class]) view = view.superview;
    return view ? [self.tableView indexPathForCell:(UITableViewCell *)view] : nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableHeaderView = _intro;
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (_intro) FZFitNote(self.tableView, _intro, 24, 0);
    if (_footer) FZFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    FZInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _shown = [self rowsToShow];
    [self.tableView reloadData];
    for (NSNotificationName name in _refreshOn) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:name object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(readValues) name:name object:nil];
    }
    if (!_live) return;
    [_ticker invalidate];
    _ticker = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(readValues) userInfo:nil repeats:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_ticker invalidate];
    _ticker = nil;
    for (NSNotificationName name in _refreshOn) [NSNotificationCenter.defaultCenter removeObserver:self name:name object:nil];
}

// Rows that come and go on their own (a download finishing brings its Remove row) follow here too.
- (void)readValues {
    [self showRowsThen:nil];
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        NSIndexPath *path = [self.tableView indexPathForCell:cell];
        if (!path) continue;   // on its way out
        FZModRow *row = [self rowAt:path];
        if (row.progress) showProgress(cell, row, YES);
        UILabel *label = (UILabel *)cell.accessoryView;
        if (!row.value || row.page || ![label isKindOfClass:UILabel.class]) continue;
        label.text = row.value();
        [label sizeToFit];
        [cell setNeedsLayout];
    }
}

- (void)refreshVisibility {
    _shown = [self rowsToShow];
    [self.tableView reloadData];
}

- (FZModRow *)rowAt:(NSIndexPath *)path {
    return _shown[(NSUInteger)path.section][(NSUInteger)path.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_shown[(NSUInteger)section].count;
}

// A slider row is laid out by hand; every other row sizes itself.
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    FZModRow *row = [self rowAt:path];
    return row.number ? [FZModSliderCell heightFor:row] : UITableViewAutomaticDimension;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = _sections[(NSUInteger)section].title;
    return title ? FZSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return _sections[(NSUInteger)section].title ? FZSectionHeaderHeight : FZSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    NSString *footer = _sections[(NSUInteger)section].footer;
    return footer ? FZSectionFooter(table, footer) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    NSString *footer = _sections[(NSUInteger)section].footer;
    return footer ? FZSectionFooterHeight(table, footer) : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    FZModRow *row = [self rowAt:path];
    // A row waiting on a switch that is off is dimmed and cannot be used until it is on.
    BOOL waiting = row.waitsOn && !FZFlag(row.waitsOn, NO);
    if (row.number) {
        FZModSliderCell *cell = [table dequeueReusableCellWithIdentifier:@"slider"] ?: [[FZModSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"slider"];
        cell.backgroundColor = FZCardBackground();
        [cell showRow:row];
        cell.userInteractionEnabled = !waiting;
        cell.alpha = waiting ? 0.4 : 1.0;
        return cell;
    }
    UITableViewCell *cell = FZDequeueCell(table, @"row");
    FZFillCell(cell, row.title, row.subtitle, row.color, row.symbol);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    if (row.color) content.secondaryTextProperties.color = row.color;
    BOOL tile = row.symbol && !row.color;
    if (row.image) {
        content.image = [row.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        content.imageProperties.tintColor = row.color ?: UIColor.whiteColor;
        content.imageToTextPadding = 14;
    } else if (tile) {
        content.image = FZTileImage(row.symbol);
    }
    cell.contentConfiguration = content;
    BOOL leading = row.symbol || row.image;
    cell.separatorInset = UIEdgeInsetsMake(0, leading ? (tile ? 58 : 48) : 16, 0, 0);
    showProgress(cell, row, NO);

    if (row.key) {
        BOOL locked = flagRowLocked(row);
        // A lock that beats an override shows over one; the others give way to it.
        BOOL beats = NO;
        if (locked) FZLockedFlagValue(row.key, &beats);
        BOOL showsLock = locked && (beats || !FZFlagOverride(row.key));
        BOOL on = row.flag ? (showsLock ? lockedRowOn(row) : flagRowOn(row)) : FZFlag(row.key, row.defaultOn);
        UIControl *toggle;
        if (row.glows) {
            FZGlowSwitch *glow = [FZGlowSwitch new];
            glow.on = on;
            glow.accessibilityLabel = row.title;
            toggle = glow;
        } else {
            UISwitch *plain = [UISwitch new];
            plain.onTintColor = FZGreen();
            plain.on = on;
            toggle = plain;
        }
        toggle.enabled = !locked;
        // A disabled switch would swallow the tap; letting it through is what gets the row asked.
        toggle.userInteractionEnabled = !locked;
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = row.info ? [self infoButtonBeside:toggle] : toggle;
        cell.selectionStyle = locked ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    } else if (row.page) {
        cell.accessoryView = row.value ? valueAndChevron(row.value()) : FZSymbolView(@"chevron.right", 13, UIImageSymbolWeightSemibold, 16);
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (row.value) {
        UILabel *label = [UILabel new];
        label.font = FZTitleFont();
        label.textColor = FZGrey();
        label.text = row.value();
        [label sizeToFit];
        cell.accessoryView = label;
        cell.selectionStyle = row.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    } else if (row.action) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    if (waiting) {
        cell.userInteractionEnabled = NO;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.alpha = 0.4;
    }
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    FZModRow *row = [self rowAt:path];
    if (flagRowLocked(row)) {
        [table deselectRowAtIndexPath:path animated:YES];
        [self explainLock];
        return;
    }
    if (row.page) [self.navigationController pushViewController:row.page() animated:YES];
    if (!row.action) return;
    row.action();
    [table deselectRowAtIndexPath:path animated:YES];
    [self readValues];
}

// The ⓘ to the left of the switch, the grey of a subtitle, 30pt across so it is easy to hit next to it.
- (UIView *)infoButtonBeside:(UIControl *)toggle {
    UIButton *info = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    [info setImage:[UIImage systemImageNamed:@"info.circle" withConfiguration:symbol] forState:UIControlStateNormal];
    info.tintColor = FZGrey();
    info.accessibilityLabel = @"About this switch";
    [info addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
    [toggle sizeToFit];
    CGFloat side = 30, gap = 8, height = MAX(side, toggle.bounds.size.height);
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side + gap + toggle.bounds.size.width, height)];
    info.frame = CGRectMake(0, (height - side) / 2, side, side);
    toggle.frame = CGRectMake(side + gap, (height - toggle.bounds.size.height) / 2, toggle.bounds.size.width, toggle.bounds.size.height);
    [box addSubview:info];
    [box addSubview:toggle];
    return box;
}

- (void)infoTapped:(UIButton *)button {
    NSIndexPath *path = [self pathOf:button];
    if (!path) return;
    FZModRow *row = [self rowAt:path];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:row.title message:row.info preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// A UISwitch or an FZGlowSwitch, both answering isOn.
- (void)toggled:(UIControl *)toggle {
    BOOL on = [(UISwitch *)toggle isOn];
    NSIndexPath *path = [self pathOf:toggle];
    if (!path) return;
    FZModRow *row = [self rowAt:path];
    if (row.flag) FZSetFlagOverride(row.key, on ? @(!row.forceOff) : nil);
    else FZSetEnabled(row.key, on);
    if (row.changed) row.changed(on);
    NSTimeInterval wait = [toggle isKindOfClass:FZGlowSwitch.class] ? 0.45 : 0;
    void (^reload)(void) = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self.tableView reloadData]; });
    };
    BOOL moved = [self showRowsThen:row.changed ? reload : nil];
    if (row.changed && !moved) reload();
    if (on && row.warning) [self warn:row];
}

// A locked row will not move, and nothing on it says why.
- (void)explainLock {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Overridden by another setting"
                         message:@"Another switch is forcing this flag, so the row shows what it forces instead of taking a value of its own."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)warn:(FZModRow *)row {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[row.title stringByAppendingString:@" is unstable"]
                                                                  message:row.warning
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open GitHub" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        FZOpenURL(FZRepoURL);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
