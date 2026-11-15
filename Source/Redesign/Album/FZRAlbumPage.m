// Adapted from taurus/tweak/Sources/Redesigned/Album/AlbumHeader.x, AlbumField.x, AlbumRows.x and Kit/SGRHeaderInfo.m,
// SGRActionRow.m @ fe3211c (GPL-3.0). See FZRAlbumPage.h.
#import <MediaPlayer/MediaPlayer.h>
#import "Redesign/Album/FZRAlbumPage.h"
#import "Redesign/Data/FZServer.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Redesign/Kit/FZRField.h"
#import "Redesign/Kit/FZGlass.h"
#import "Redesign/FZRNaviMusControls.h"
#import "Settings/Kit/FZModPage.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZRemote.h"
#import "Core/FZLog.h"

NSString *const FZRKeyCircleBack = @"fz.redesign.circle.back";
NSString *const FZRKeyCircleMore = @"fz.redesign.circle.more";
NSString *const FZRKeyCircleActions = @"fz.redesign.circle.actions";
NSString *const FZRKeyAlbumShuffle = @"fz.redesign.album.shuffle";
NSString *const FZRKeyAlbumDownload = @"fz.redesign.album.download";
NSString *const FZRKeyAlbumMeta = @"fz.redesign.album.meta";

// SGRHeaderInfo.m / AlbumHeader.x / AlbumField.x / SGRActionRow.m values.
static const CGFloat kSide = 20, kPlayWidth = 148, kRowSpacing = 16, kRowAbove = 16, kInfoBottom = 14;
static const CGFloat kTitleRise = 56, kDissolve = 0.46, kTopScrim = 140, kTopScrimAlpha = 0.28;
static const CGFloat kCorner = 16, kCapsuleLead = 4, kGlyphSide = 44, kCapsuleTrail = 20;
static const UIEdgeInsets kBleed = {600, 0, 600, 0};
// The hero's height over the page's width: the cover fills the top down to 56 pt under the title's top
// (measured on chroma.pw's album page at 390 pt: 472 pt).
static const CGFloat kHeroAspect = 1.21;
static const CGFloat kHairline = 0.5;

#pragma mark - pieces

// A redesign button: a glyph, on a 44/48 pt glass circle when `circled` (FZRGlassInside's shape).
@interface FZRRoundButton : UIControl
- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)size weight:(UIImageSymbolWeight)weight label:(NSString *)label;
@property (nonatomic) BOOL circled;
@property (nonatomic, readonly) UIImageView *glyph;
@end

@implementation FZRRoundButton {
    UIVisualEffectView *_glass;
}
- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)size weight:(UIImageSymbolWeight)weight label:(NSString *)label {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = label;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _glass = [[UIVisualEffectView alloc] initWithEffect:FZGlassEffect()];
    _glass.userInteractionEnabled = NO;
    _glass.clipsToBounds = YES;
    [self addSubview:_glass];
    _glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:weight]]];
    _glyph.tintColor = FZRPrimary();
    _glyph.contentMode = UIViewContentModeCenter;
    [self addSubview:_glyph];
    _circled = YES;
    return self;
}
- (void)setCircled:(BOOL)circled {
    _circled = circled;
    _glass.hidden = !circled;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _glass.frame = self.bounds;
    FZShapeGlass(_glass, self.bounds.size.height / 2, YES);
    _glyph.frame = self.bounds;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    FZRAnimate(FZRMotionPress, ^{ self.alpha = highlighted ? 0.6 : 1; }, nil);
}
@end

// SGRPlayCapsule: white, the glyph in a 44 pt box 4 pt in, the word 20 pt from the end, both in the field's
// colour; Subheadline semibold up to Large.
@interface FZRPlayCapsule : UIControl
@property (nonatomic, copy) UIColor *contentColor;
@property (nonatomic) BOOL playing;
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
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeCenter;
    _title = [UILabel new];
    _title.font = FZRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    [self addSubview:_glyph];
    [self addSubview:_title];
    _contentColor = UIColor.blackColor;
    self.playing = NO;
    return self;
}
- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    _glyph.image = [UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold]];
    _title.text = playing ? @"Pause" : @"Play";
    self.accessibilityLabel = _title.text;
    [self setNeedsLayout];
}
- (void)setContentColor:(UIColor *)contentColor {
    _contentColor = [contentColor copy];
    _glyph.tintColor = contentColor;
    _title.textColor = contentColor;
}
- (CGFloat)naturalWidth {
    return kCapsuleLead + kGlyphSide + ceil([_title sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width) + kCapsuleTrail;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    self.layer.cornerRadius = b.size.height / 2;
    CGFloat lead = kCapsuleLead + MAX(0, round((b.size.width - [self naturalWidth]) / 2));
    _glyph.frame = CGRectMake(lead, round((b.size.height - kGlyphSide) / 2), kGlyphSide, kGlyphSide);
    CGSize text = [_title sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    _title.frame = CGRectMake(CGRectGetMaxX(_glyph.frame), round((b.size.height - text.height) / 2),
                              MAX(0, b.size.width - kCapsuleTrail - CGRectGetMaxX(_glyph.frame)), text.height);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    FZRAnimate(FZRMotionPress, ^{ self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity; }, nil);
}
@end

// Three bars in the accent beside the playing row's title, moving while the sound plays.
@interface FZRPlayingBars : UIView
@property (nonatomic) BOOL moving;
@end

@implementation FZRPlayingBars {
    NSArray<CALayer *> *_bars;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NSMutableArray *bars = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        CALayer *bar = [CALayer layer];
        bar.anchorPoint = CGPointMake(0.5, 1);
        bar.cornerRadius = 1;
        [self.layer addSublayer:bar];
        [bars addObject:bar];
    }
    _bars = bars;
    return self;
}
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(14, 13); }
- (void)tintColorDidChange {
    [super tintColorDidChange];
    for (CALayer *bar in _bars) bar.backgroundColor = self.tintColor.CGColor;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = 3, gap = 2.5, h = self.bounds.size.height;
    static const CGFloat rest[3] = {0.55, 1.0, 0.4};
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _bars.count; i++) {
        _bars[i].bounds = CGRectMake(0, 0, w, h);
        _bars[i].position = CGPointMake(w / 2 + i * (w + gap), h);
        _bars[i].backgroundColor = self.tintColor.CGColor;
        if (!_moving) _bars[i].transform = CATransform3DMakeScale(1, rest[i], 1);
    }
    [CATransaction commit];
}
- (void)setMoving:(BOOL)moving {
    if (_moving == moving && (moving == ([_bars.firstObject animationForKey:@"bounce"] != nil))) return;
    _moving = moving;
    static const CGFloat periods[3] = {0.47, 0.39, 0.53};
    for (NSUInteger i = 0; i < _bars.count; i++) {
        [_bars[i] removeAnimationForKey:@"bounce"];
        if (!moving || FZRReduceMotion()) continue;
        CAKeyframeAnimation *bounce = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.y"];
        bounce.values = @[@0.3, @1.0, @0.5, @0.85, @0.3];
        bounce.duration = periods[i] * 4;
        bounce.repeatCount = HUGE_VALF;
        bounce.calculationMode = kCAAnimationCubic;
        [_bars[i] addAnimation:bounce forKey:@"bounce"];
    }
    [self setNeedsLayout];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && _moving) { _moving = NO; self.moving = YES; }   // animations are dropped off-window
}
@end

#pragma mark - header

@interface FZRAlbumHeader : UIView
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic, readonly) UILabel *title, *artist, *meta;
@property (nonatomic, readonly) FZRRoundButton *shuffle, *download;
@property (nonatomic, readonly) FZRPlayCapsule *play;
@property (nonatomic, strong) UIColor *fieldColor;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation FZRAlbumHeader {
    CAGradientLayer *_scrim, *_dissolve;
}

static UILabel *infoLabel(UIFont *font, UIColor *color, NSInteger lines) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = lines;
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
    _title = infoLabel(FZRFont(UIFontTextStyleTitle2, UIFontWeightBold, UIContentSizeCategoryExtraLarge), FZRPrimary(), 2);
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    _artist = infoLabel(FZRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge), FZRSecondary(), 1);
    _artist.userInteractionEnabled = YES;
    _artist.accessibilityTraits = UIAccessibilityTraitButton;
    _meta = infoLabel(FZRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraLarge), FZRTertiary(), 1);
    for (UIView *v in @[_title, _artist, _meta]) [self addSubview:v];
    _shuffle = [[FZRRoundButton alloc] initWithSymbol:@"shuffle" pointSize:19 weight:UIImageSymbolWeightSemibold label:@"Shuffle"];
    _download = [[FZRRoundButton alloc] initWithSymbol:@"arrow.down" pointSize:19 weight:UIImageSymbolWeightSemibold label:@"Download"];
    _play = [FZRPlayCapsule new];
    for (UIView *v in @[_shuffle, _play, _download]) [self addSubview:v];
    self.fieldColor = FZRNeutralField();
    return self;
}

- (void)setFieldColor:(UIColor *)fieldColor {
    _fieldColor = fieldColor;
    _dissolve.colors = @[(id)[fieldColor colorWithAlphaComponent:0].CGColor, (id)fieldColor.CGColor];
    _play.contentColor = fieldColor;
}

- (NSArray<UILabel *> *)shownLabels {
    NSMutableArray *shown = [NSMutableArray array];
    for (UILabel *label in @[_title, _artist, _meta]) if (label.text.length && !label.hidden) [shown addObject:label];
    return shown;
}

- (CGFloat)gapAfter:(UILabel *)label {
    return label == _artist ? 4 : 2;
}

- (CGFloat)infoHeightForWidth:(CGFloat)width {
    CGFloat text = width - 2 * kSide, height = 0;
    UILabel *previous = nil;
    for (UILabel *label in [self shownLabels]) {
        if (previous) height += [self gapAfter:previous];
        height += ceil([label sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
        previous = label;
    }
    if (previous) height += kRowAbove;
    return height + FZRActionHeight;
}

- (CGFloat)heroHeightForWidth:(CGFloat)width {
    return round(width * kHeroAspect);
}

// The title's top sits 56 pt above the hero's bottom (SGRHeaderInfoTitleRise).
- (CGFloat)heightForWidth:(CGFloat)width {
    return [self heroHeightForWidth:width] - kTitleRise + [self infoHeightForWidth:width] + kInfoBottom;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, text = width - 2 * kSide;
    CGFloat hero = [self heroHeightForWidth:width];
    if (!_picture.layer.animationKeys.count && CGRectGetMinY(_picture.frame) >= 0) _picture.frame = CGRectMake(0, 0, width, hero);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = CGRectMake(0, 0, _picture.bounds.size.width, MIN(kTopScrim, hero));
    CGFloat fade = round(_picture.bounds.size.height * kDissolve);
    _dissolve.frame = CGRectMake(0, _picture.bounds.size.height - fade, _picture.bounds.size.width, fade);
    [CATransaction commit];

    CGFloat y = hero - kTitleRise;
    UILabel *previous = nil;
    for (UILabel *label in @[_title, _artist, _meta]) {
        if (![[self shownLabels] containsObject:label]) { label.frame = CGRectZero; continue; }
        if (previous) y += [self gapAfter:previous];
        CGFloat h = ceil([label sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
        label.frame = CGRectMake(kSide, y, text, h);
        y += h;
        previous = label;
    }
    if (previous) y += kRowAbove;
    CGFloat side = FZRActionHeight;
    BOOL shuffle = !_shuffle.hidden, download = !_download.hidden;
    CGFloat play = MIN(MAX(kPlayWidth, [_play naturalWidth]), MAX(0, text - 2 * (side + kRowSpacing)));
    CGFloat x = round((width - play) / 2);
    _play.frame = CGRectMake(x, y, play, side);
    if (shuffle) _shuffle.frame = CGRectMake(x - kRowSpacing - side, y, side, side);
    if (download) _download.frame = CGRectMake(x + play + kRowSpacing, y, side, side);
}

// Pulled down, the cover stretches from its top, as the redesign's hero does.
- (void)stretchBy:(CGFloat)pull {
    CGFloat width = self.bounds.size.width, hero = [self heroHeightForWidth:width];
    _picture.frame = pull > 0 ? CGRectMake(-pull / 2, -pull, width + pull, hero + pull) : CGRectMake(0, 0, width, hero);
    [self setNeedsLayout];
}
@end

#pragma mark - track row

@interface FZRTrackCell : UITableViewCell
@property (nonatomic, readonly) UILabel *name, *artists;
@property (nonatomic, readonly) UIImageView *explicitBadge;
@property (nonatomic, readonly) UIButton *more;
@property (nonatomic, readonly) FZRPlayingBars *bars;
- (void)showPlaying:(BOOL)current moving:(BOOL)moving;
@end

@implementation FZRTrackCell {
    UIView *_hairline;
    BOOL _current;
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
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightRegular]]];
    _explicitBadge.tintColor = FZRSecondary();
    _more = [UIButton buttonWithType:UIButtonTypeSystem];
    [_more setImage:[UIImage systemImageNamed:@"ellipsis"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    _more.tintColor = FZRPrimary();
    _more.accessibilityLabel = @"More";
    _bars = [[FZRPlayingBars alloc] initWithFrame:CGRectZero];
    _bars.hidden = YES;
    _hairline = [UIView new];
    _hairline.backgroundColor = FZRHairline();
    for (UIView *v in @[_bars, _name, _artists, _explicitBadge, _more, _hairline]) [self.contentView addSubview:v];
    return self;
}
- (void)tintColorDidChange {
    [super tintColorDidChange];
    if (_current) _name.textColor = FZRAccent();
}
- (void)showPlaying:(BOOL)current moving:(BOOL)moving {
    _current = current;
    _name.textColor = current ? FZRAccent() : FZRPrimary();
    _bars.tintColor = FZRAccent();
    _bars.hidden = !current;
    _bars.moving = current && moving;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat right = b.size.width - FZRSideMargin;
    _more.frame = CGRectMake(right - 36, 0, 44, b.size.height);
    CGFloat textRight = CGRectGetMinX(_more.frame) - 8;
    CGFloat nameH = ceil(_name.font.lineHeight), artistsH = ceil(_artists.font.lineHeight);
    CGFloat top = round((b.size.height - nameH - 2 - artistsH) / 2);
    CGFloat x = FZRSideMargin;
    if (!_bars.hidden) {
        CGSize s = [_bars sizeThatFits:CGSizeZero];
        _bars.frame = CGRectMake(x, top + round((nameH - s.height) / 2), s.width, s.height);
        x = CGRectGetMaxX(_bars.frame) + 6;
    }
    _name.frame = CGRectMake(x, top, MAX(0, textRight - x), nameH);
    x = FZRSideMargin;
    if (!_explicitBadge.hidden) {
        CGSize s = _explicitBadge.image.size;
        _explicitBadge.frame = CGRectMake(x, top + nameH + 2 + round((artistsH - s.height) / 2), s.width, s.height);
        x = CGRectGetMaxX(_explicitBadge.frame) + 6;
    }
    _artists.frame = CGRectMake(x, top + nameH + 2, MAX(0, textRight - x), artistsH);
    _hairline.frame = CGRectMake(FZRSideMargin, b.size.height - kHairline, b.size.width - 2 * FZRSideMargin, kHairline);
}
@end

#pragma mark - page

@interface FZRAlbumPage () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation FZRAlbumPage {
    NSString *_albumID;
    __weak UIViewController *_naviMusPage;
    FZRArtworkField *_field;
    UITableView *_table;
    FZRAlbumHeader *_header;
    FZRRoundButton *_back, *_more;
    NSDictionary *_album;
    NSArray<NSDictionary *> *_songs;
    NSSet<NSString *> *_songIDs;
    id _nowPlayingObserver;
}

- (instancetype)initWithAlbumID:(NSString *)albumID naviMusPage:(UIViewController *)naviMusPage {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _albumID = [albumID copy];
    _naviMusPage = naviMusPage;
    return self;
}

- (void)dealloc {
    if (_nowPlayingObserver) [NSNotificationCenter.defaultCenter removeObserver:_nowPlayingObserver];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _field = [[FZRArtworkField alloc] initWithFrame:self.view.bounds];
    _field.bleed = kBleed;
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_field];
    __weak typeof(self) weakSelf = self;
    [_field whenColored:^{ [weakSelf fieldColored]; }];

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

    _header = [[FZRAlbumHeader alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 500)];
    [_header.play addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    [_header.shuffle addTarget:self action:@selector(shuffle) forControlEvents:UIControlEventTouchUpInside];
    [_header.download addTarget:self action:@selector(download) forControlEvents:UIControlEventTouchUpInside];
    [_header.artist addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openArtist)]];
    _table.tableHeaderView = _header;

    _back = [[FZRRoundButton alloc] initWithSymbol:@"chevron.left" pointSize:20 weight:UIImageSymbolWeightSemibold label:@"Back"];
    _more = [[FZRRoundButton alloc] initWithSymbol:@"ellipsis" pointSize:17 weight:UIImageSymbolWeightBold label:@"More"];
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [_more addTarget:self action:@selector(showMore) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_back];
    [self.view addSubview:_more];

    _nowPlayingObserver = [NSNotificationCenter.defaultCenter addObserverForName:FZNowPlayingDidChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weakSelf showPlayback]; }];
    [self applyOptions];
    [self load];
}

- (void)applyOptions {
    _back.circled = FZHidden(FZRKeyCircleBack);
    _more.circled = FZEnabled(FZRKeyCircleMore);
    _header.shuffle.circled = _header.download.circled = FZEnabled(FZRKeyCircleActions);
    _header.shuffle.hidden = !FZEnabled(FZRKeyAlbumShuffle);
    _header.download.hidden = !FZEnabled(FZRKeyAlbumDownload);
    _header.meta.hidden = !FZEnabled(FZRKeyAlbumMeta);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Pinned under the status bar (the window's inset): the page's own inset includes NaviMus's bar, which
    // stays in place (hidden) under the rebuilt page.
    CGFloat width = self.view.bounds.size.width;
    CGFloat top = self.view.window ? self.view.window.safeAreaInsets.top : self.view.safeAreaInsets.top;
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

// NaviMus's navigation bar stays where it is (its back gesture and SwiftUI path keep working); its drawing
// gives way to the page's own buttons while the page is on top (FZRSetNaviMusBarHidden keeps it hidden).
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyOptions];
    FZRSetNaviMusBarHidden(_naviMusPage, YES, self.transitionCoordinator);
    [self showPlayback];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    FZRSetNaviMusBarHidden(_naviMusPage, NO, self.transitionCoordinator);
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
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *song in _songs) if (string(song[@"id"])) [ids addObject:string(song[@"id"])];
    _songIDs = ids;
    _header.title.text = string(album[@"name"]);
    _header.artist.text = string(album[@"displayArtist"]) ?: string(album[@"artist"]);
    NSMutableArray *meta = [NSMutableArray array];
    NSString *genre = string(album[@"genre"]);
    if (genre.length) [meta addObject:genre];
    NSArray *types = [album[@"releaseTypes"] isKindOfClass:NSArray.class] ? album[@"releaseTypes"] : nil;
    NSString *type = [types.firstObject isKindOfClass:NSString.class] && [types.firstObject length] ? [types.firstObject capitalizedString] : @"Album";
    [meta addObject:type];
    NSString *year = string(album[@"year"]);
    if (year.length && ![year isEqualToString:@"0"]) [meta addObject:year];
    _header.meta.text = [meta componentsJoinedByString:@" · "];
    [_header setNeedsLayout];
    [self.view setNeedsLayout];
    [_table reloadData];
    [self showPlayback];

    NSString *cover = string(album[@"coverArt"]) ?: _albumID;
    CGFloat pixels = self.view.bounds.size.width * kHeroAspect * UIScreen.mainScreen.scale;
    __weak typeof(self) weakSelf = self;
    FZServerImage(FZServerCoverURL(cover, (NSInteger)MIN(pixels, 1500)), ^(UIImage *image) {
        typeof(self) page = weakSelf;
        if (!page || !image) return;
        [UIView transitionWithView:page->_header.picture duration:FZRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ page->_header.picture.image = image; } completion:nil];
        [page->_field setArtwork:image identity:cover animated:YES];
    });
}

- (void)fieldColored {
    UIColor *field = _field.fieldColor;
    FZRAnimate(FZRMotionFade, ^{ self->_header.fieldColor = field; }, nil);
}

- (void)showProblem:(NSString *)message {
    _header.title.text = @"Couldn't load the album";
    _header.meta.text = message;
    [_header setNeedsLayout];
    [self.view setNeedsLayout];
}

#pragma mark playback

- (BOOL)albumIsCurrent {
    NSString *song = FZNowPlayingSongID();
    return song && [_songIDs containsObject:song];
}

- (void)showPlayback {
    BOOL current = [self albumIsCurrent], playing = current && FZNowPlayingIsPlaying();
    _header.play.playing = playing;
    MPChangeShuffleModeCommand *shuffle = MPRemoteCommandCenter.sharedCommandCenter.changeShuffleModeCommand;
    _header.shuffle.glyph.tintColor = current && shuffle.currentShuffleType != MPShuffleTypeOff ? FZRAccent() : FZRPrimary();
    NSString *song = FZNowPlayingSongID();
    for (FZRTrackCell *cell in _table.visibleCells) {
        NSIndexPath *path = [_table indexPathForCell:cell];
        if (!path) continue;
        BOOL here = song && [string(_songs[(NSUInteger)path.row][@"id"]) isEqualToString:song];
        [cell showPlaying:here moving:here && FZNowPlayingIsPlaying()];
    }
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

// Playing this album: NaviMus's own play/pause, as the lock screen's button. Otherwise NaviMus plays it.
- (void)play {
    if ([self albumIsCurrent]) {
        MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
        BOOL done = FZRemoteSend(center.togglePlayPauseCommand)
            || FZRemoteSend(FZNowPlayingIsPlaying() ? center.pauseCommand : center.playCommand);
        if (done) return;
    }
    __weak typeof(self) weakSelf = self;
    FZRNaviMusPlay(@"Album", _albumID, ^(BOOL ok, NSString *why) { [weakSelf report:@"play the album" ok:ok why:why]; });
}

// NaviMus's own shuffle on its own album page, so its queue shuffles the way it does itself.
- (void)shuffle {
    if (!FZRActivateNaviMusControl(_naviMusPage, nil, @[@"Shuffle"])) {
        [self report:@"shuffle" ok:NO why:@"NaviMus's shuffle button wasn't found on its album page."];
    }
}

- (void)download {
    if (!FZRActivateNaviMusControl(_naviMusPage, nil, @[@"Download", @"Downloaded", @"Remove Download"])) {
        [self report:@"download" ok:NO why:@"NaviMus's download button wasn't found on its album page."];
    }
}

- (void)showMore {
    if (!FZRActivateNaviMusControl(_naviMusPage, nil, @[@"More"])) {
        [self report:@"open the menu" ok:NO why:@"NaviMus's ⋯ button wasn't found on its album page."];
    }
}

// A row's ⋯: NaviMus's own ⋯ on the same song's row (the first "More" after the song's title).
- (void)showSongMenu:(UIButton *)sender {
    CGPoint point = [sender convertPoint:CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds)) toView:_table];
    NSIndexPath *path = [_table indexPathForRowAtPoint:point];
    if (!path) return;
    NSString *title = string(_songs[(NSUInteger)path.row][@"title"]);
    if (!FZRActivateNaviMusControl(_naviMusPage, title, @[@"More"])) {
        [self report:@"open the song's menu" ok:NO why:@"NaviMus's ⋯ for this song wasn't found on its album page."];
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
    [cell.more removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.more addTarget:self action:@selector(showSongMenu:) forControlEvents:UIControlEventTouchUpInside];
    NSString *playing = FZNowPlayingSongID();
    BOOL here = playing && [string(song[@"id"]) isEqualToString:playing];
    [cell showPlaying:here moving:here && FZNowPlayingIsPlaying()];
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
    [_header stretchBy:-scroll.contentOffset.y];
}
@end

#pragma mark - options

UIViewController *FZRRedesignOptionsPage(void) {
    FZModRow *circleBack = FZWithSymbol(FZOptionRow(@"Circle behind back", @"chroma.pw shows a bare chevron on iOS 17.", FZRKeyCircleBack), @"chevron.left.circle");
    FZModRow *circleMore = FZWithSymbol(FZSwitchRow(@"Circle behind ⋯", nil, FZRKeyCircleMore), @"ellipsis.circle");
    FZModRow *circleActions = FZWithSymbol(FZSwitchRow(@"Circles behind shuffle and download", nil, FZRKeyCircleActions), @"circle.dashed");
    FZModRow *shuffle = FZWithSymbol(FZSwitchRow(@"Shuffle button", nil, FZRKeyAlbumShuffle), @"shuffle");
    FZModRow *download = FZWithSymbol(FZSwitchRow(@"Download button", @"In place of chroma.pw's +.", FZRKeyAlbumDownload), @"arrow.down.circle");
    FZModRow *meta = FZWithSymbol(FZSwitchRow(@"Genre, type and year", nil, FZRKeyAlbumMeta), @"text.alignleft");
    return [[FZModPage alloc] initWithTitle:@"Redesigned pages" intro:nil sections:@[
        FZNotedSection(@"Buttons", @[circleBack, circleMore, circleActions], @"Off leaves only the icon."),
        FZNotedSection(@"Album", @[shuffle, download, meta], @"Changes show the next time a page opens."),
    ] footer:nil];
}
