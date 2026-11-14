// Adapted from taurus/tweak/Sources/Redesigned/Album/AlbumHeader.x, AlbumRows.x and Kit/SGRHeaderInfo.m,
// SGRActionRow.m @ fe3211c (GPL-3.0). See FZRAlbumPage.h.
#import <objc/message.h>
#import "Redesign/Album/FZRAlbumPage.h"
#import "Redesign/Data/FZServer.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Redesign/Kit/FZRPalette.h"
#import "Redesign/Kit/FZGlass.h"
#import "Redesign/FZRNaviMusControls.h"
#import "Core/FZLog.h"

// AlbumHeader.x / SGRHeaderInfo.m values.
static const CGFloat kSide = 20, kPlayWidth = 148, kRowSpacing = 16, kRowAbove = 16;
static const CGFloat kDissolve = 0.46, kTopScrim = 140, kTopScrimAlpha = 0.28;
static const CGFloat kTitleRise = 56, kInfoBottom = 14, kCorner = 16;
static const CGFloat kHairline = 0.5;

#pragma mark - pieces

// A 44 pt glass circle with a symbol: the redesign's header and action-row buttons.
static UIControl *glassCircle(NSString *symbol, CGFloat side, NSString *label) {
    UIControl *button = [UIControl new];
    button.accessibilityLabel = label;
    button.isAccessibilityElement = YES;
    button.accessibilityTraits = UIAccessibilityTraitButton;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:FZGlassEffect()];
    glass.userInteractionEnabled = NO;
    glass.frame = CGRectMake(0, 0, side, side);
    FZShapeGlass(glass, side / 2, YES);
    glass.clipsToBounds = YES;
    [button addSubview:glass];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:side * 0.38 weight:UIImageSymbolWeightSemibold]]];
    glyph.tintColor = FZRPrimary();
    glyph.contentMode = UIViewContentModeCenter;
    glyph.frame = glass.frame;
    glyph.tag = 7;
    [button addSubview:glyph];
    button.frame = glass.frame;
    return button;
}

@interface FZRPlayCapsule : UIControl
@end

@implementation FZRPlayCapsule {
    UILabel *_title;
    UIImageView *_glyph;
}
- (instancetype)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.backgroundColor = UIColor.whiteColor;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Play";
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold]]];
    _glyph.tintColor = UIColor.blackColor;
    _title = [UILabel new];
    _title.text = @"Play";
    _title.textColor = UIColor.blackColor;
    _title.font = FZRFont(UIFontTextStyleTitle3, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge);
    [self addSubview:_glyph];
    [self addSubview:_title];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
    [_title sizeToFit];
    CGSize glyph = _glyph.image.size;
    CGFloat total = glyph.width + 8 + _title.bounds.size.width;
    CGFloat x = round((self.bounds.size.width - total) / 2);
    _glyph.frame = CGRectMake(x, round((self.bounds.size.height - glyph.height) / 2), glyph.width, glyph.height);
    _title.frame = CGRectMake(CGRectGetMaxX(_glyph.frame) + 8, round((self.bounds.size.height - _title.bounds.size.height) / 2),
                              _title.bounds.size.width, _title.bounds.size.height);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    FZRAnimate(FZRMotionPress, ^{ self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity; }, nil);
}
@end

#pragma mark - header

@interface FZRAlbumHeader : UIView
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic, readonly) UILabel *title, *artist, *meta;
@property (nonatomic, readonly) UIControl *shuffle, *download;
@property (nonatomic, readonly) FZRPlayCapsule *play;
@property (nonatomic, strong) UIColor *fieldColor;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation FZRAlbumHeader {
    CAGradientLayer *_scrim, *_dissolve;
}

static UILabel *centredLabel(UIFont *font, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _picture = [UIImageView new];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    [self addSubview:_picture];
    _scrim = [CAGradientLayer layer];
    _scrim.colors = @[(id)[UIColor colorWithWhite:0 alpha:kTopScrimAlpha].CGColor, (id)UIColor.clearColor.CGColor];
    [_picture.layer addSublayer:_scrim];
    _dissolve = [CAGradientLayer layer];
    [_picture.layer addSublayer:_dissolve];
    _title = centredLabel(FZRFont(UIFontTextStyleTitle1, UIFontWeightBold, UIContentSizeCategoryExtraLarge), FZRPrimary());
    _artist = centredLabel(FZRFont(UIFontTextStyleTitle3, UIFontWeightRegular, UIContentSizeCategoryExtraLarge), FZRSecondary());
    _artist.userInteractionEnabled = YES;
    _meta = centredLabel(FZRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge), FZRSecondary());
    for (UIView *v in @[_title, _artist, _meta]) [self addSubview:v];
    _shuffle = glassCircle(@"shuffle", FZRActionHeight, @"Shuffle");
    _download = glassCircle(@"arrow.down", FZRActionHeight, @"Download");
    _play = [FZRPlayCapsule new];
    for (UIView *v in @[_shuffle, _play, _download]) [self addSubview:v];
    self.fieldColor = FZRNeutralField();
    return self;
}

- (void)setFieldColor:(UIColor *)fieldColor {
    _fieldColor = fieldColor;
    _dissolve.colors = @[(id)[fieldColor colorWithAlphaComponent:0].CGColor, (id)fieldColor.CGColor];
}

- (CGFloat)textHeightForWidth:(CGFloat)width {
    CGFloat text = width - 2 * kSide, height = 0;
    for (UILabel *label in @[_title, _artist, _meta]) {
        if (!label.text.length) continue;
        height += ceil([label sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height) + 4;
    }
    return height + kRowAbove + FZRActionHeight;
}

// The picture is a square under the title; the title rises 56 pt over it (SGRHeaderInfoTitleRise).
- (CGFloat)heightForWidth:(CGFloat)width {
    return width + MAX(0, [self textHeightForWidth:width] - kTitleRise) + kInfoBottom;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, text = width - 2 * kSide;
    _picture.frame = CGRectMake(0, 0, width, width);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = CGRectMake(0, 0, width, MIN(kTopScrim, width));
    CGFloat fade = round(width * kDissolve);
    _dissolve.frame = CGRectMake(0, width - fade, width, fade);
    [CATransaction commit];

    CGFloat y = self.bounds.size.height - kInfoBottom - [self textHeightForWidth:width];
    for (UILabel *label in @[_title, _artist, _meta]) {
        label.hidden = !label.text.length;
        if (label.hidden) continue;
        CGFloat h = ceil([label sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
        label.frame = CGRectMake(kSide, y, text, h);
        y += h + 4;
    }
    y += kRowAbove - 4;
    CGFloat side = FZRActionHeight;
    CGFloat play = MIN(kPlayWidth, MAX(0, text - 2 * (side + kRowSpacing)));
    CGFloat x = round((width - play) / 2);
    _play.frame = CGRectMake(x, y, play, side);
    _shuffle.frame = CGRectMake(x - kRowSpacing - side, y, side, side);
    _download.frame = CGRectMake(x + play + kRowSpacing, y, side, side);
}
@end

#pragma mark - track row

@interface FZRTrackCell : UITableViewCell
@property (nonatomic, readonly) UILabel *name, *artists;
@property (nonatomic, readonly) UIImageView *explicitBadge, *more;
@end

@implementation FZRTrackCell {
    UIView *_hairline;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    UIView *pressed = [UIView new];
    pressed.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.selectedBackgroundView = pressed;
    _name = [UILabel new];
    _name.font = FZRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    _name.textColor = FZRPrimary();
    _artists = [UILabel new];
    _artists.font = FZRFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    _artists.textColor = FZRSecondary();
    _explicitBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"e.square.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightRegular]]];
    _explicitBadge.tintColor = FZRTertiary();
    _more = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]]];
    _more.tintColor = FZRPrimary();
    _more.contentMode = UIViewContentModeCenter;
    _hairline = [UIView new];
    _hairline.backgroundColor = FZRHairline();
    for (UIView *v in @[_name, _artists, _explicitBadge, _more, _hairline]) [self.contentView addSubview:v];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat right = b.size.width - FZRSideMargin;
    _more.frame = CGRectMake(right - 28, 0, 28, b.size.height);
    CGFloat textWidth = CGRectGetMinX(_more.frame) - 12 - FZRSideMargin;
    CGFloat nameH = ceil(_name.font.lineHeight), artistsH = ceil(_artists.font.lineHeight);
    CGFloat top = round((b.size.height - nameH - 2 - artistsH) / 2);
    _name.frame = CGRectMake(FZRSideMargin, top, textWidth, nameH);
    CGFloat x = FZRSideMargin;
    if (!_explicitBadge.hidden) {
        CGSize s = _explicitBadge.image.size;
        _explicitBadge.frame = CGRectMake(x, top + nameH + 2 + round((artistsH - s.height) / 2), s.width, s.height);
        x = CGRectGetMaxX(_explicitBadge.frame) + 6;
    }
    _artists.frame = CGRectMake(x, top + nameH + 2, MAX(0, FZRSideMargin + textWidth - x), artistsH);
    _hairline.frame = CGRectMake(FZRSideMargin, b.size.height - kHairline, b.size.width - 2 * FZRSideMargin, kHairline);
}
@end

#pragma mark - page

@interface FZRAlbumPage () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation FZRAlbumPage {
    NSString *_albumID;
    __weak UIViewController *_naviMusPage;
    UITableView *_table;
    FZRAlbumHeader *_header;
    UIControl *_back, *_more;
    NSDictionary *_album;
    NSArray<NSDictionary *> *_songs;
    UIColor *_field;
}

- (instancetype)initWithAlbumID:(NSString *)albumID naviMusPage:(UIViewController *)naviMusPage {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _albumID = [albumID copy];
    _naviMusPage = naviMusPage;
    _field = FZRNeutralField();
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = _field;
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _table.rowHeight = 64;
    _table.dataSource = self;
    _table.delegate = self;
    _table.showsVerticalScrollIndicator = NO;
    [_table registerClass:FZRTrackCell.class forCellReuseIdentifier:@"track"];
    [self.view addSubview:_table];

    _header = [[FZRAlbumHeader alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 400)];
    [_header.play addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    [_header.shuffle addTarget:self action:@selector(shuffle) forControlEvents:UIControlEventTouchUpInside];
    [_header.download addTarget:self action:@selector(download) forControlEvents:UIControlEventTouchUpInside];
    [_header.artist addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openArtist)]];
    _table.tableHeaderView = _header;

    _back = glassCircle(@"chevron.left", FZRGlassCircleSize, @"Back");
    _more = glassCircle(@"ellipsis", FZRGlassCircleSize, @"More");
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [_more addTarget:self action:@selector(showMore) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_back];
    [self.view addSubview:_more];

    [self load];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, top = self.view.safeAreaInsets.top;
    CGFloat height = [_header heightForWidth:width];
    if (fabs(_header.frame.size.height - height) > 0.5 || fabs(_header.frame.size.width - width) > 0.5) {
        _header.frame = CGRectMake(0, 0, width, height);
        _table.tableHeaderView = _header;
    }
    _table.contentInset = UIEdgeInsetsMake(0, 0, self.view.safeAreaInsets.bottom + 80, 0);
    CGFloat side = FZRGlassCircleSize;
    _back.frame = CGRectMake(kCorner, top, side, side);
    _more.frame = CGRectMake(width - kCorner - side, top, side, side);
}

// NaviMus's navigation bar stays where it is (its back gesture and SwiftUI path keep working); only its
// drawing gives way to the page's own glass buttons while the page is on top.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self showNaviMusBar:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self showNaviMusBar:YES];
}

- (void)showNaviMusBar:(BOOL)shown {
    UINavigationBar *bar = _naviMusPage.navigationController.navigationBar;
    if (!bar) return;
    id<UIViewControllerTransitionCoordinator> transition = self.transitionCoordinator;
    void (^apply)(void) = ^{ bar.alpha = shown ? 1 : 0; };
    if (transition) {
        [transition animateAlongsideTransition:^(id context) { apply(); } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            // A cancelled swipe back leaves this page on top.
            if (context.isCancelled) bar.alpha = shown ? 0 : 1;
        }];
    } else {
        apply();
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark data

- (void)load {
    __weak typeof(self) weakSelf = self;
    FZServerGet(@"getAlbum", @{@"id": _albumID}, ^(NSDictionary *response, NSError *error) {
        typeof(self) page = weakSelf;
        if (!page) return;
        NSDictionary *album = [response[@"album"] isKindOfClass:NSDictionary.class] ? response[@"album"] : nil;
        if (!album) {
            FZLogError("redesign album: getAlbum failed (%@)", error.localizedDescription ?: @"no album");
            [page showProblem:error.localizedDescription ?: @"The album couldn't be loaded."];
            return;
        }
        [page showAlbum:album];
    });
}

static NSString *string(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}

- (void)showAlbum:(NSDictionary *)album {
    _album = album;
    id songs = album[@"song"];
    _songs = [songs isKindOfClass:NSArray.class] ? songs : @[];
    _header.title.text = string(album[@"name"]);
    _header.artist.text = string(album[@"displayArtist"]) ?: string(album[@"artist"]);
    NSMutableArray *meta = [NSMutableArray array];
    NSString *genre = string(album[@"genre"]);
    if (genre.length) [meta addObject:genre];
    NSArray *types = [album[@"releaseTypes"] isKindOfClass:NSArray.class] ? album[@"releaseTypes"] : nil;
    NSString *type = [types.firstObject isKindOfClass:NSString.class] ? [types.firstObject capitalizedString] : @"Album";
    [meta addObject:type];
    NSString *year = string(album[@"year"]);
    if (year.length && ![year isEqualToString:@"0"]) [meta addObject:year];
    _header.meta.text = [meta componentsJoinedByString:@" · "];
    [_header setNeedsLayout];
    [self.view setNeedsLayout];
    [_table reloadData];

    NSString *cover = string(album[@"coverArt"]) ?: _albumID;
    CGFloat pixels = self.view.bounds.size.width * UIScreen.mainScreen.scale;
    __weak typeof(self) weakSelf = self;
    FZServerImage(FZServerCoverURL(cover, (NSInteger)MIN(pixels, 1200)), ^(UIImage *image) {
        typeof(self) page = weakSelf;
        if (!page || !image) return;
        [UIView transitionWithView:page->_header.picture duration:FZRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ page->_header.picture.image = image; } completion:nil];
        FZRPaletteRequest request = {0};
        [FZRPalette paletteForImage:image request:request completion:^(FZRPalette *palette) {
            if (!palette.fieldColor) return;
            [page setField:palette.fieldColor];
        }];
    });
}

- (void)setField:(UIColor *)field {
    _field = field;
    FZRAnimate(FZRMotionFade, ^{
        self.view.backgroundColor = field;
        self->_header.fieldColor = field;
    }, nil);
}

- (void)showProblem:(NSString *)message {
    _header.title.text = @"Couldn't load the album";
    _header.meta.text = message;
    [_header setNeedsLayout];
    [self.view setNeedsLayout];
}

#pragma mark actions

- (void)report:(NSString *)what ok:(BOOL)ok why:(NSString *)why {
    if (ok) return;
    FZLogError("redesign album: %@ failed: %@", what, why);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Couldn't %@", what]
                                                                   message:why preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)play {
    __weak typeof(self) weakSelf = self;
    FZRNaviMusPlay(@"Album", _albumID, ^(BOOL ok, NSString *why) { [weakSelf report:@"play the album" ok:ok why:why]; });
}

// NaviMus's own shuffle on its own album page, so its queue shuffles the way it does itself.
- (void)shuffle {
    if (!FZRActivateNaviMusControl(_naviMusPage, @[@"Shuffle"])) {
        [self report:@"shuffle" ok:NO why:@"NaviMus's shuffle button wasn't found on its album page."];
    }
}

- (void)download {
    if (!FZRActivateNaviMusControl(_naviMusPage, @[@"Download", @"Download Album", @"Downloaded", @"Remove Download"])) {
        [self report:@"download" ok:NO why:@"NaviMus's download button wasn't found on its album page."];
    }
}

- (void)showMore {
    if (!FZRActivateNaviMusControl(_naviMusPage, @[@"More", @"Options", @"ellipsis", @"Ellipsis"])) {
        [self report:@"open the menu" ok:NO why:@"NaviMus's ⋯ button wasn't found on its album page."];
    }
}

- (void)openArtist {
    NSString *artistID = string(_album[@"artistId"]);
    if (!artistID.length) return;
    __weak typeof(self) weakSelf = self;
    FZRNaviMusOpen(@"Artist", artistID, ^(BOOL ok, NSString *why) { [weakSelf report:@"open the artist" ok:ok why:why]; });
}

- (void)goBack {
    [_naviMusPage.navigationController popViewControllerAnimated:YES];
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return _songs.count;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    FZRTrackCell *cell = [table dequeueReusableCellWithIdentifier:@"track" forIndexPath:path];
    NSDictionary *song = _songs[(NSUInteger)path.row];
    cell.name.text = string(song[@"title"]);
    cell.artists.text = string(song[@"displayArtist"]) ?: string(song[@"artist"]);
    cell.explicitBadge.hidden = ![string(song[@"explicitStatus"]) isEqualToString:@"explicit"];
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSString *songID = string(_songs[(NSUInteger)path.row][@"id"]);
    if (!songID.length) return;
    __weak typeof(self) weakSelf = self;
    FZRNaviMusPlay(@"Song", songID, ^(BOOL ok, NSString *why) { [weakSelf report:@"play the song" ok:ok why:why]; });
}

- (void)scrollViewDidScroll:(UIScrollView *)scroll {
    // The picture stretches when pulled down, as the redesign's hero does.
    CGFloat pull = -scroll.contentOffset.y;
    CGFloat width = scroll.bounds.size.width;
    _header.picture.frame = pull > 0 ? CGRectMake(-pull / 2, -pull, width + pull, width + pull) : CGRectMake(0, 0, width, width);
}
@end
