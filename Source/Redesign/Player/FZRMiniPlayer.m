// The redesign's mini player (R2): a glass card over the tab bar, as chroma.pw's. Adapted from
// taurus/tweak/Sources/Redesigned/NowPlayingBar/NowPlayingBar.x @ fe3211c (GPL-3.0): the card's 24 pt radius,
// its glass, the cover, the 2 pt progress line 3 pt off the bottom with a 24 % white track.
// See FZRPlayer.h for how it sits over NaviMus's own.
#import "Redesign/Player/FZRAnimatedCovers.h"
#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import "Redesign/Player/FZRPlayer.h"
#import "Redesign/Player/FZRQueue.h"
#import "Redesign/FZRBarButtons.h"
#import "Redesign/FZRAppLook.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Redesign/Kit/FZGlass.h"
#import "Redesign/Kit/FZRRoundButton.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZRemote.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import "Redesign/Data/FZServer.h"

NSString *const FZRKeyPlayerRebuilt = @"fz.redesign.player";
NSString *const FZRKeyMiniPlayPause = @"fz.redesign.mini.playPause";
NSString *const FZRKeyMiniPrevious = @"fz.redesign.mini.previous";
NSString *const FZRKeyMiniNext = @"fz.redesign.mini.next";
NSString *const FZRKeyMiniAirPlay = @"fz.redesign.mini.airplay";
NSString *const FZRKeyMiniDownload = @"fz.redesign.mini.download";
NSString *const FZRKeyMiniProgress = @"fz.redesign.mini.progress";
NSString *const FZRKeyMiniRoundArtwork = @"fz.redesign.mini.roundArtwork";
NSString *const FZRKeyMiniSwipe = @"fz.redesign.mini.swipe";

// Measured on chroma.pw's mini player (the user's screenshot, 390 pt wide): a 55 pt card 8 pt from the sides, corners
// about 18 pt, a 40 pt round cover 8 pt in, the text 64 pt in, 44 pt buttons 8 pt from the right edge, and a 2 pt
// progress line flush along the bottom, clipped by the corners.
static const CGFloat kCardHeight = 56, kCardRadius = 18, kCardSide = 8, kCardAboveBar = 8;
static const CGFloat kArtwork = 40, kInset = 8, kButton = 44, kTextGap = 16, kProgress = 2;

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
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.28];
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
    // Square ends: the card's rounded corners clip the line, so it runs into them seamlessly.
    _track.frame = b;
    _fill.frame = CGRectMake(0, 0, b.size.width * _progress, b.size.height);
}
@end

#pragma mark - the bar

// The output the sound goes to, shown under the title in the accent as chroma.pw does ("WH-1000XM6" with a
// Bluetooth glyph); nothing for the phone's own speaker.
static NSString *routeName(NSString **symbol) {
    AVAudioSessionPortDescription *output = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    NSString *type = output.portType;
    if (!output || [type isEqualToString:AVAudioSessionPortBuiltInSpeaker] || [type isEqualToString:AVAudioSessionPortBuiltInReceiver]) return nil;
    NSString *glyph = @"hifispeaker";
    if ([type isEqualToString:AVAudioSessionPortBluetoothA2DP] || [type isEqualToString:AVAudioSessionPortBluetoothHFP]
        || [type isEqualToString:AVAudioSessionPortBluetoothLE]) glyph = @"headphones";   // SF Symbols has no Bluetooth logo
    else if ([type isEqualToString:AVAudioSessionPortAirPlay]) glyph = @"airplayaudio";
    else if ([type isEqualToString:AVAudioSessionPortHeadphones]) glyph = @"headphones";
    else if ([type isEqualToString:AVAudioSessionPortCarAudio]) glyph = @"car";
    if (symbol) *symbol = glyph;
    return output.portName.length ? output.portName : nil;
}

static UIImage *routeGlyph(NSString *symbol, UIFont *font) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithFont:font scale:UIImageSymbolScaleSmall];
    return [UIImage systemImageNamed:symbol withConfiguration:config];
}

static void placeBar(UITabBarController *tabs);

@interface FZRMiniBar : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UITabBarController *tabs;
- (void)refresh;
@end

@implementation FZRMiniBar {
    UIVisualEffectView *_glass;
    UIView *_content;
    UIImageView *_artwork, *_routeIcon;
    UILabel *_title, *_byline, *_route;
    FZRRoundButton *_download, *_previous, *_play, *_next;
    AVRoutePickerView *_airPlay;
    FZRMiniProgress *_progress;
    NSTimer *_timer;
    NSString *_artworkSong;
    NSString *_serverCoverSong;   // the song whose cover was asked of the server
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
    _title.lineBreakMode = NSLineBreakByTruncatingTail;
    _title.font = FZRFont(UIFontTextStyleSubheadline, UIFontWeightMedium, UIContentSizeCategoryExtraLarge);
    _title.textColor = FZRPrimary();
    _byline = [UILabel new];
    _byline.lineBreakMode = NSLineBreakByTruncatingTail;
    _byline.font = FZRFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    _byline.textColor = FZRSecondary();
    _route = [UILabel new];
    _route.font = FZRFont(UIFontTextStyleFootnote, UIFontWeightMedium, UIContentSizeCategoryExtraLarge);
    _route.textColor = FZRAccent();
    _routeIcon = [UIImageView new];
    _routeIcon.tintColor = FZRAccent();
    _routeIcon.contentMode = UIViewContentModeCenter;
    for (UIView *v in @[_artwork, _title, _byline, _route, _routeIcon]) [_content addSubview:v];

    _airPlay = [AVRoutePickerView new];
    _airPlay.prioritizesVideoDevices = NO;
    [_content addSubview:_airPlay];
    _download = [self button:@"arrow.down.circle" size:22 label:@"Download" action:@selector(download)];
    _previous = [self button:@"backward.fill" size:20 label:@"Previous" action:@selector(previous)];
    _next = [self button:@"forward.fill" size:20 label:@"Next" action:@selector(next)];
    _play = [self button:@"play.fill" size:24 label:@"Play" action:@selector(playPause)];

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
    for (UIGestureRecognizer *g in @[tap, up, left, right]) g.delegate = self;

    for (NSNotificationName name in @[FZNowPlayingDidChangeNotification, NSUserDefaultsDidChangeNotification, AVAudioSessionRouteChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshSoon) name:name object:nil];
    }
    return self;
}

- (FZRRoundButton *)button:(NSString *)symbol size:(CGFloat)size label:(NSString *)label action:(SEL)action {
    FZRRoundButton *button = [[FZRRoundButton alloc] initWithSymbol:symbol pointSize:size weight:UIImageSymbolWeightRegular label:label];
    button.circled = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_content addSubview:button];
    return button;
}

// The bar's own tap and swipes leave its buttons (and AirPlay's picker) to themselves.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:AVRoutePickerView.class]) return NO;
    }
    return YES;
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
    // Stays just over NaviMus's root view in the window (placeBar), whatever is added later.
    UITabBarController *tabs = self.tabs;
    if (tabs) placeBar(tabs);
}

- (void)refreshSoon {
    // Route changes arrive off the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)refresh {
    NSDictionary *info = FZNowPlayingInfo();
    NSString *title = info[MPMediaItemPropertyTitle] ?: @"";
    NSString *artist = info[MPMediaItemPropertyArtist] ?: info[MPMediaItemPropertyAlbumArtist] ?: @"";
    // "Title • Artist" on one line, the artist in the secondary white (chroma.pw); the title gives way first, so the
    // artist still shows beside a long title (the user's screenshot, build 44).
    _title.text = title;
    _byline.text = artist.length ? [@" • " stringByAppendingString:artist] : nil;
    NSString *symbol = nil;
    NSString *route = routeName(&symbol);
    _route.text = route;
    _route.hidden = _routeIcon.hidden = route == nil;
    _routeIcon.image = symbol ? routeGlyph(symbol, _route.font) : nil;
    _airPlay.tintColor = route ? FZRAccent() : FZRPrimary();
    _airPlay.activeTintColor = FZRAccent();

    BOOL playing = FZNowPlayingIsPlaying();
    [_play setSymbol:playing ? @"pause.fill" : @"play.fill"];
    _play.accessibilityLabel = playing ? @"Pause" : @"Play";
    NSString *song = FZNowPlayingSongID() ?: title;
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
    // NaviMus sometimes hands the system no picture (back in the app, or after iOS relaunched it): the mini player was
    // an empty grey circle (the user's screenshot, build 70). The cover then comes from the server, as Frozio's pages
    // load theirs.
    if (!_artworkSong && song.length && ![song isEqualToString:_serverCoverSong]) {
        _serverCoverSong = song;
        NSDictionary *current = FZRNaviMusQueue()[@"current"];
        NSString *coverID = [current isKindOfClass:NSDictionary.class] && [current[@"id"] isEqual:song] && [current[@"coverArt"] isKindOfClass:NSString.class]
            ? current[@"coverArt"] : song;
        __weak typeof(self) weakSelf = self;
        FZServerImage(FZServerCoverURL(coverID, (NSInteger)(kArtwork * 3)), ^(UIImage *cover) {
            typeof(self) bar = weakSelf;
            if (!bar || !cover || bar->_artworkSong) return;
            NSString *now = FZNowPlayingSongID() ?: bar->_title.text;
            if (![now isEqualToString:song]) return;
            bar->_artwork.image = cover;
            FZLog("mini player: cover from the server for %@ (Now Playing had none)", song);
        });
    }
    _download.hidden = !FZEnabled(FZRKeyMiniDownload);
    _previous.hidden = !FZHidden(FZRKeyMiniPrevious);
    _play.hidden = !FZEnabled(FZRKeyMiniPlayPause);
    _next.hidden = !FZEnabled(FZRKeyMiniNext);
    _airPlay.hidden = !FZHidden(FZRKeyMiniAirPlay);
    _progress.hidden = !FZEnabled(FZRKeyMiniProgress);
    [self tick];
    [self setNeedsLayout];
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
        _glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    }
    _content.frame = b;
    _content.layer.cornerRadius = radius;

    CGFloat artwork = MIN(kArtwork, b.size.height - 2 * kInset);
    _artwork.frame = CGRectMake(kInset, round((b.size.height - artwork) / 2), artwork, artwork);
    _artwork.layer.cornerRadius = FZEnabled(FZRKeyMiniRoundArtwork) ? artwork / 2 : FZRRadiusThumb;

    // From the right: play/pause last, next just before it, then previous, download and AirPlay (chroma.pw's
    // AirPlay, +, pause; the user asked for next before play/pause).
    CGFloat x = b.size.width - kInset;
    for (UIView *button in @[_play, _next, _previous, _download, _airPlay]) {
        if (button.hidden) continue;
        x -= kButton;
        button.frame = CGRectMake(x, round((b.size.height - kButton) / 2), kButton, kButton);
    }
    CGFloat textX = CGRectGetMaxX(_artwork.frame) + kTextGap;
    CGFloat textWidth = MAX(0, x - 6 - textX);
    CGFloat titleHeight = ceil(_title.font.lineHeight), routeHeight = _route.hidden ? 0 : ceil(_route.font.lineHeight);
    CGFloat top = round((b.size.height - titleHeight - routeHeight) / 2);
    CGFloat bylineNatural = _byline.text.length ? ceil([_byline sizeThatFits:CGSizeMake(CGFLOAT_MAX, titleHeight)].width) : 0;
    CGFloat titleNatural = ceil([_title sizeThatFits:CGSizeMake(CGFLOAT_MAX, titleHeight)].width);
    CGFloat bylineWidth = MIN(bylineNatural, MAX(textWidth - titleNatural, textWidth * 0.6));
    CGFloat titleWidth = MIN(titleNatural, MAX(0, textWidth - bylineWidth));
    _title.frame = CGRectMake(textX, top, titleWidth, titleHeight);
    _byline.frame = CGRectMake(textX + titleWidth, top, bylineWidth, titleHeight);
    CGFloat icon = _routeIcon.image ? 14 : 0;
    _routeIcon.frame = CGRectMake(textX - 2, top + titleHeight, icon, routeHeight);
    _route.frame = CGRectMake(textX + icon + (icon ? 4 : 0), top + titleHeight, MAX(0, textWidth - icon - 4), routeHeight);

    // Flush along the bottom edge, the full width: the card's corners clip it.
    _progress.frame = CGRectMake(0, b.size.height - kProgress, b.size.width, kProgress);
}

- (NSArray *)accessibilityElements {
    UIAccessibilityElement *summary = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:self];
    summary.accessibilityLabel = [NSString stringWithFormat:@"%@%@", _title.text ?: @"", _byline.text ?: @""];
    summary.accessibilityValue = _route.hidden ? nil : _route.text;
    summary.accessibilityHint = @"Opens the player";
    summary.accessibilityTraits = UIAccessibilityTraitButton;
    summary.accessibilityFrameInContainerSpace = CGRectMake(0, 0, MAX(0, CGRectGetMaxX(_byline.frame)), self.bounds.size.height);
    NSMutableArray *elements = [NSMutableArray arrayWithObject:summary];
    for (UIView *button in @[_airPlay, _download, _previous, _next, _play]) if (!button.hidden) [elements addObject:button];
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

// SwiftUI can make NaviMus's tab bar transparent (its backdrop came from the band now hidden): the redesign's
// material goes back on before iOS 26 whenever the bar has no background of its own.
static void ensureTabBarBackground(UITabBar *tabBar) {
    UITabBarAppearance *look = FZRTabBarLook();
    if (!look || !tabBar) return;
    for (UITabBarAppearance *appearance in @[tabBar.standardAppearance ?: NSNull.null, tabBar.scrollEdgeAppearance ?: NSNull.null]) {
        BOOL bare = [appearance isKindOfClass:NSNull.class]
            || (!((UITabBarAppearance *)appearance).backgroundEffect && CGColorGetAlpha(((UITabBarAppearance *)appearance).backgroundColor.CGColor) < 0.5
                && !((UITabBarAppearance *)appearance).backgroundImage);
        if (!bare) continue;
        tabBar.standardAppearance = look;
        tabBar.scrollEdgeAppearance = look;
        FZLog("player: the tab bar's background put back");
        return;
    }
}

static void placeBar(UITabBarController *tabs) {
    if (!tabs.isViewLoaded || !tabs.view.window) return;
    ensureTabBarBackground(tabs.tabBar);
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
    // In the window just over NaviMus's root view, under anything presented: NaviMus draws its own card in its root
    // hosting view over the tabs (device, build 40), and SwiftUI's gestures there would also take every touch on a
    // bar inside that view (harness: the card underneath was tapped with each of Frozio's buttons).
    UIWindow *window = tabs.view.window;
    UIView *top = tabs.view;
    while (top.superview && top.superview != window) top = top.superview;
    UIView *host = window ?: tabs.view;
    if (top.superview == window) {
        NSUInteger above = [window.subviews indexOfObject:top] + 1;
        if (bar.superview != window || [window.subviews indexOfObject:bar] != above) [window insertSubview:bar aboveSubview:top];
    } else if (bar.superview != host) {
        [host addSubview:bar];
    }
    UITabBar *tabBar = tabs.tabBar;
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
    FZRInstallQueue();
    FZRInstallLibraryChips();
    FZRInstallAnimatedCoverWarmUp();
    BOOL layout = FZHookInstanceMethod(UITabBarController.class, @selector(viewDidLayoutSubviews), "v@:",
                                       (IMP)fz_tabsLayout, &fz_origTabsLayout, "redesign.player.tabs");
    // A song starting or the switch flipping lays the bar out again.
    for (NSNotificationName name in @[FZNowPlayingDidChangeNotification, NSUserDefaultsDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            // NaviMus writes its settings often: one pass on the next turn of the run loop for any number of them.
            static BOOL pending;
            if (pending) return;
            pending = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                pending = NO;
                UITabBarController *tabs = sTabs;
                if (tabs) placeBar(tabs);
            });
        }];
    }
    FZLog("redesign: player %@", layout ? @"installed" : @"NOT installed");
}

void FZRRecheckNaviMusMini(void) {
    for (NSNumber *delay in @[@0, @0.2, @0.45]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UITabBarController *tabs = sTabs;
            if (tabs && FZRPlayerActive() && FZNowPlayingInfo()) FZRSetNaviMusMiniHidden(tabs, YES);
        });
    }
}

UITabBarController *FZRPlayerTabs(void) { return sTabs; }
UIView *FZRPlayerMiniBar(void) { UITabBarController *tabs = sTabs; return tabs ? objc_getAssociatedObject(tabs, &kMiniBarKey) : nil; }
