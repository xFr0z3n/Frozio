// The redesign's mini player (R2): a glass card over the tab bar, as chroma.pw's. Adapted from
// taurus/tweak/Sources/Redesigned/NowPlayingBar/NowPlayingBar.x @ fe3211c (GPL-3.0): the card's 24 pt radius,
// its glass, the cover, the 2 pt progress line 3 pt off the bottom with a 24 % white track.
// See FZRPlayer.h for how it sits over NaviMus's own.
#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import "Redesign/Player/FZRPlayer.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Redesign/Kit/FZGlass.h"
#import "Redesign/Kit/FZRRoundButton.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZRemote.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

NSString *const FZRKeyPlayerRebuilt = @"fz.redesign.player";
NSString *const FZRKeyMiniPlayPause = @"fz.redesign.mini.playPause";
NSString *const FZRKeyMiniPrevious = @"fz.redesign.mini.previous";
NSString *const FZRKeyMiniNext = @"fz.redesign.mini.next";
NSString *const FZRKeyMiniAirPlay = @"fz.redesign.mini.airplay";
NSString *const FZRKeyMiniDownload = @"fz.redesign.mini.download";
NSString *const FZRKeyMiniProgress = @"fz.redesign.mini.progress";
NSString *const FZRKeyMiniRoundArtwork = @"fz.redesign.mini.roundArtwork";
NSString *const FZRKeyMiniSwipe = @"fz.redesign.mini.swipe";

static const CGFloat kCardHeight = 56, kCardRadius = 24, kCardSide = 8, kCardAboveBar = 8;
static const CGFloat kArtwork = 40, kInset = 8, kButton = 40, kTextGap = 10;

static NSArray<NSString *> *downloadLabels(void) {
    return @[@"Download", @"Download Song", @"Download Track", @"Remove Download", @"Delete Download"];
}

BOOL FZRPlayerActive(void) {
    return FZRRedesignActive() && FZEnabled(FZRKeyPlayerRebuilt);
}

#pragma mark - the progress line

@interface FZRMiniProgress : UIView
@property (nonatomic) CGFloat progress;
@end

@implementation FZRMiniProgress {
    UIView *_track, *_fill;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    _track = [UIView new];
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.24];
    _fill = [UIView new];
    _fill.backgroundColor = UIColor.whiteColor;
    [self addSubview:_track];
    [self addSubview:_fill];
    return self;
}
- (void)setProgress:(CGFloat)progress {
    _progress = MIN(1, MAX(0, isfinite(progress) ? progress : 0));
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _track.frame = b;
    _fill.frame = CGRectMake(0, 0, b.size.width * _progress, b.size.height);
    _track.layer.cornerRadius = _fill.layer.cornerRadius = b.size.height / 2;
}
@end

#pragma mark - the bar

@interface FZRMiniBar : UIView
@property (nonatomic, weak) UITabBarController *tabs;
- (void)refresh;
@end

@implementation FZRMiniBar {
    UIVisualEffectView *_glass;
    UIView *_content;
    UIImageView *_artwork;
    UILabel *_title, *_artist;
    FZRRoundButton *_download, *_previous, *_play, *_next;
    AVRoutePickerView *_route;
    FZRMiniProgress *_progress;
    NSTimer *_timer;
    NSString *_artworkSong;
}
static char kBarGlassKey;

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.accessibilityIdentifier = @"FZRMiniPlayer";
    _glass = FZGlassFor(self, &kBarGlassKey);
    _content = [UIView new];
    _content.clipsToBounds = YES;
    _content.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_content];

    _artwork = [UIImageView new];
    _artwork.contentMode = UIViewContentModeScaleAspectFill;
    _artwork.clipsToBounds = YES;
    _artwork.layer.cornerCurve = kCACornerCurveContinuous;
    _artwork.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _title = [UILabel new];
    _title.font = FZRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge);
    _title.textColor = FZRPrimary();
    _artist = [UILabel new];
    _artist.font = FZRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    _artist.textColor = FZRSecondary();
    for (UIView *v in @[_artwork, _title, _artist]) [_content addSubview:v];

    _download = [self button:@"arrow.down.circle" size:21 label:@"Download" action:@selector(download)];
    _previous = [self button:@"backward.fill" size:18 label:@"Previous" action:@selector(previous)];
    _play = [self button:@"play.fill" size:22 label:@"Play" action:@selector(playPause)];
    _next = [self button:@"forward.fill" size:18 label:@"Next" action:@selector(next)];
    _route = [AVRoutePickerView new];
    _route.tintColor = FZRPrimary();
    _route.activeTintColor = FZRAccent();
    _route.prioritizesVideoDevices = NO;
    [_content addSubview:_route];

    _progress = [FZRMiniProgress new];
    [_content addSubview:_progress];

    self.isAccessibilityElement = NO;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)];
    [self addGestureRecognizer:tap];
    UISwipeGestureRecognizer *up = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(open)];
    up.direction = UISwipeGestureRecognizerDirectionUp;
    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
    left.direction = UISwipeGestureRecognizerDirectionLeft;
    UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
    right.direction = UISwipeGestureRecognizerDirectionRight;
    for (UIGestureRecognizer *g in @[up, left, right]) [self addGestureRecognizer:g];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:FZNowPlayingDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:NSUserDefaultsDidChangeNotification object:nil];
    return self;
}

- (FZRRoundButton *)button:(NSString *)symbol size:(CGFloat)size label:(NSString *)label action:(SEL)action {
    FZRRoundButton *button = [[FZRRoundButton alloc] initWithSymbol:symbol pointSize:size weight:UIImageSymbolWeightRegular label:label];
    button.circled = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_content addSubview:button];
    return button;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_timer invalidate];
    _timer = nil;
    if (!self.window) return;
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    [self refresh];
}

- (void)tick {
    NSTimeInterval duration = FZNowPlayingDuration();
    _progress.progress = duration > 0 ? FZNowPlayingElapsed() / duration : 0;
}

- (void)refresh {
    NSDictionary *info = FZNowPlayingInfo();
    _title.text = info[MPMediaItemPropertyTitle] ?: @"";
    _artist.text = info[MPMediaItemPropertyArtist] ?: info[MPMediaItemPropertyAlbumArtist] ?: @"";
    BOOL playing = FZNowPlayingIsPlaying();
    [_play setSymbol:playing ? @"pause.fill" : @"play.fill"];
    _play.accessibilityLabel = playing ? @"Pause" : @"Play";
    NSString *song = FZNowPlayingSongID() ?: _title.text;
    UIImage *image = FZNowPlayingArtwork(CGSizeMake(kArtwork * 3, kArtwork * 3));
    if (image || ![song isEqualToString:_artworkSong]) {
        if (image && ![song isEqualToString:_artworkSong] && _artwork.image) {
            [UIView transitionWithView:_artwork duration:FZRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self->_artwork.image = image; } completion:nil];
        } else {
            _artwork.image = image;
        }
        _artworkSong = image ? song : nil;
    }
    _download.hidden = !FZEnabled(FZRKeyMiniDownload);
    _previous.hidden = !FZHidden(FZRKeyMiniPrevious);
    _play.hidden = !FZEnabled(FZRKeyMiniPlayPause);
    _next.hidden = !FZEnabled(FZRKeyMiniNext);
    _route.hidden = !FZHidden(FZRKeyMiniAirPlay);
    _progress.hidden = !FZEnabled(FZRKeyMiniProgress);
    [self tick];
    [self setNeedsLayout];
    [self.superview setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat radius = MIN(kCardRadius, b.size.height / 2);
    _glass.frame = b;
    FZShapeGlass(_glass, radius, NO);
    BOOL liquid = NO;
    if (@available(iOS 26.0, *)) liquid = YES;
    if (!liquid) {
        // chroma.pw on iOS 17: the grey material with a faint lighter ring, as its glass circles.
        _glass.layer.borderWidth = 1;
        _glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    }
    _content.frame = b;
    _content.layer.cornerRadius = radius;

    CGFloat artwork = MIN(kArtwork, b.size.height - 2 * kInset);
    _artwork.frame = CGRectMake(kInset, round((b.size.height - artwork) / 2), artwork, artwork);
    _artwork.layer.cornerRadius = FZHidden(FZRKeyMiniRoundArtwork) ? artwork / 2 : FZRRadiusThumb;

    CGFloat x = b.size.width - kInset;
    for (UIView *button in @[_next, _play, _previous, _route, _download]) {
        if (button.hidden) continue;
        x -= kButton;
        button.frame = CGRectMake(x, round((b.size.height - kButton) / 2), kButton, kButton);
    }
    CGFloat textX = CGRectGetMaxX(_artwork.frame) + kTextGap;
    CGFloat textWidth = MAX(0, x - 4 - textX);
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = _artist.text.length ? ceil(_artist.font.lineHeight) : 0;
    CGFloat top = round((b.size.height - titleHeight - artistHeight) / 2);
    _title.frame = CGRectMake(textX, top, textWidth, titleHeight);
    _artist.frame = CGRectMake(textX, top + titleHeight, textWidth, artistHeight);

    // Along the bottom edge, clear of the rounded corners.
    CGFloat thickness = 2, sideInset = radius;
    _progress.frame = CGRectMake(sideInset, b.size.height - 3 - thickness, MAX(0, b.size.width - 2 * sideInset), thickness);
}

- (NSArray *)accessibilityElements {
    UIAccessibilityElement *summary = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:self];
    summary.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", _title.text ?: @"", _artist.text ?: @""];
    summary.accessibilityHint = @"Opens the player";
    summary.accessibilityTraits = UIAccessibilityTraitButton;
    summary.accessibilityFrameInContainerSpace = CGRectMake(0, 0, MAX(0, _title.frame.origin.x + _title.frame.size.width), self.bounds.size.height);
    NSMutableArray *elements = [NSMutableArray arrayWithObject:summary];
    for (UIView *button in @[_download, _route, _previous, _play, _next]) if (!button.hidden) [elements addObject:button];
    return elements;
}

- (BOOL)accessibilityActivate { [self open]; return YES; }

#pragma mark actions

- (void)open { FZRPresentPlayer(); }

- (void)playPause {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    BOOL done = FZRemoteSend(center.togglePlayPauseCommand) || FZRemoteSend(FZNowPlayingIsPlaying() ? center.pauseCommand : center.playCommand);
    if (!done) FZLogError("player: NaviMus has no play/pause handler");
}
- (void)next { if (!FZRemoteSend(MPRemoteCommandCenter.sharedCommandCenter.nextTrackCommand)) FZLogError("player: no next-track handler"); }
- (void)previous { if (!FZRemoteSend(MPRemoteCommandCenter.sharedCommandCenter.previousTrackCommand)) FZLogError("player: no previous-track handler"); }

- (void)swiped:(UISwipeGestureRecognizer *)swipe {
    if (!FZEnabled(FZRKeyMiniSwipe)) return;
    if (swipe.direction == UISwipeGestureRecognizerDirectionLeft) [self next]; else [self previous];
}

- (void)download {
    UITabBarController *tabs = self.tabs;
    __weak typeof(self) weakSelf = self;
    FZRNaviMusPlayerAction(tabs, self, downloadLabels(), ^(BOOL ok, NSString *why) {
        FZLog("player: mini player download → %d%@", ok, why ? [@" " stringByAppendingString:why] : @"");
        if (ok || !weakSelf) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't download" message:why preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf.tabs presentViewController:alert animated:YES completion:nil];
    });
}
@end

#pragma mark - over the tab bar controller

static IMP fz_origTabsLayout;
static __weak UITabBarController *sTabs;
static char kMiniBarKey;

static FZRMiniBar *barOf(UITabBarController *tabs) {
    FZRMiniBar *bar = objc_getAssociatedObject(tabs, &kMiniBarKey);
    if (!bar) {
        bar = [FZRMiniBar new];
        bar.tabs = tabs;
        objc_setAssociatedObject(tabs, &kMiniBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        FZLog("player: Frozio's mini player made for %@", NSStringFromClass(tabs.class));
    }
    return bar;
}

static void placeBar(UITabBarController *tabs) {
    if (!tabs.isViewLoaded || !tabs.view.window) return;
    sTabs = tabs;
    BOOL active = FZRPlayerActive();
    BOOL playing = FZNowPlayingInfo() != nil;
    FZRMiniBar *bar = objc_getAssociatedObject(tabs, &kMiniBarKey);
    if (!active || !playing) {
        bar.hidden = YES;
        if (!active) FZRSetNaviMusMiniHidden(tabs, NO);
        else FZRSetNaviMusMiniHidden(tabs, YES);
        return;
    }
    bar = barOf(tabs);
    UIView *host = tabs.view;
    UITabBar *tabBar = tabs.tabBar;
    // Under the tab bar where it's the host's own subview (iOS 17), else over the content.
    if (tabBar.superview == host) {
        if (bar.superview != host || [host.subviews indexOfObject:bar] > [host.subviews indexOfObject:tabBar]) [host insertSubview:bar belowSubview:tabBar];
    } else if (bar.superview != host) {
        [host addSubview:bar];
    }
    BOOL barShown = tabBar.window && !tabBar.hidden && tabBar.alpha > 0.01;
    CGFloat bottom = barShown ? CGRectGetMinY([tabBar convertRect:tabBar.bounds toView:host]) : host.bounds.size.height - host.safeAreaInsets.bottom;
    CGRect frame = CGRectMake(kCardSide + host.safeAreaInsets.left, bottom - kCardAboveBar - kCardHeight,
                              host.bounds.size.width - 2 * kCardSide - host.safeAreaInsets.left - host.safeAreaInsets.right, kCardHeight);
    if (!CGRectEqualToRect(bar.frame, frame)) bar.frame = frame;
    bar.hidden = FZRNaviMusPlayerShown();
    FZRSetNaviMusMiniHidden(tabs, YES);
}

static void fz_tabsLayout(UITabBarController *self, SEL _cmd) {
    ((void (*)(id, SEL))fz_origTabsLayout)(self, _cmd);
    placeBar(self);
}

void FZRInstallPlayer(void) {
    if (!FZRRedesignActive()) return;
    BOOL layout = FZHookInstanceMethod(UITabBarController.class, @selector(viewDidLayoutSubviews), "v@:",
                                       (IMP)fz_tabsLayout, &fz_origTabsLayout, "redesign.player.tabs");
    // A song starting or the switch flipping lays the bar out again.
    for (NSNotificationName name in @[FZNowPlayingDidChangeNotification, NSUserDefaultsDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            UITabBarController *tabs = sTabs;
            if (tabs) placeBar(tabs);
        }];
    }
    FZLog("redesign: player %@", layout ? @"installed" : @"NOT installed");
}

UITabBarController *FZRPlayerTabs(void) { return sTabs; }
UIView *FZRPlayerMiniBar(void) { UITabBarController *tabs = sTabs; return tabs ? objc_getAssociatedObject(tabs, &kMiniBarKey) : nil; }
