// The redesign's player (R3), 1:1 with chroma.pw's. Adapted from taurus/tweak/Sources/Redesigned/Player/
// PlayerHeader.x, PlayerArtwork.x, PlayerControls.x, PlayerFooter.x, PlayerField.x and PlayerLyrics.x @ fe3211c
// (GPL-3.0), values in docs/DESIGN_TOKENS.md:
// - the field from the cover (FZRArtworkField), the cover with radius 12 and its shadow plate (black 45 %, 32 pt
//   blur, 12 pt down), shrinking to 0.84 while paused (0.92 under Reduce Motion), on the layout spring;
// - glass ⌄ and ⋯ in 44 pt circles, the "Playing from" line between them;
// - the title Title 2 bold, the artist Body secondary, download beside them (the user's choice over chroma.pw's +);
// - the scrubber with elapsed and remaining in monospaced digits;
// - shuffle, previous and next at 32 pt, play/pause in a white circle, repeat;
// - the footer 20 pt above the safe area (34 at least): AirPlay, sleep timer, lyrics, queue.
// Every button can be hidden (Frozio settings → Appearance → Redesigned pages).
#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import "Redesign/Player/FZRPlayer.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Redesign/Kit/FZRField.h"
#import "Redesign/Kit/FZRRoundButton.h"
#import "Lyrics/FZNaviMusLyrics.h"
#import "Settings/Kit/FZModPage.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZRemote.h"
#import "Core/FZLog.h"

NSString *const FZRKeyPlayerContext = @"fz.redesign.player.context";
NSString *const FZRKeyPlayerDownload = @"fz.redesign.player.download";
NSString *const FZRKeyPlayerShuffle = @"fz.redesign.player.shuffle";
NSString *const FZRKeyPlayerRepeat = @"fz.redesign.player.repeat";
NSString *const FZRKeyPlayerAirPlay = @"fz.redesign.player.airplay";
NSString *const FZRKeyPlayerSleep = @"fz.redesign.player.sleep";
NSString *const FZRKeyPlayerLyrics = @"fz.redesign.player.lyrics";
NSString *const FZRKeyPlayerQueue = @"fz.redesign.player.queue";
NSString *const FZRKeyPlayerMore = @"fz.redesign.player.more";
NSString *const FZRKeyPlayerShrink = @"fz.redesign.player.shrink";
NSString *const FZRKeyPlayerTimes = @"fz.redesign.player.times";

static const CGFloat kSide = 24, kHeaderTop = 4, kCircle = 44, kPlayCircle = 68, kSkipGlyph = 32, kSmallGlyph = 22;
static const CGFloat kPausedScale = 0.84, kPausedScaleReduced = 0.92, kFooterAbove = 20, kFooterMinBottom = 34;

static NSString *string(id value) { return [value isKindOfClass:NSString.class] && [value length] ? value : nil; }

static NSString *timeText(NSTimeInterval seconds) {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    NSInteger s = (NSInteger)floor(seconds);
    return s >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(s / 3600), (long)(s / 60 % 60), (long)(s % 60)]
                     : [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

#pragma mark - sleep timer

// Frozio's own: NaviMus's pause handler when the time is up, or at the end of the song.
static NSTimer *sSleepTimer;
static NSDate *sSleepEnd;
static BOOL sSleepEndOfSong;
static NSString *sSleepSong;
NSNotificationName const FZRSleepTimerDidChangeNotification = @"fz.redesign.sleepTimerDidChange";

static void pauseNow(void) {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    BOOL done = FZRemoteSend(center.pauseCommand) || (FZNowPlayingIsPlaying() && FZRemoteSend(center.togglePlayPauseCommand));
    FZLog("player: sleep timer paused → %d", done);
}

static void stopSleepTimer(void) {
    [sSleepTimer invalidate];
    sSleepTimer = nil;
    sSleepEnd = nil;
    sSleepEndOfSong = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:FZRSleepTimerDidChangeNotification object:nil];
}

static void startSleepTimer(NSTimeInterval minutes) {
    stopSleepTimer();
    sSleepEndOfSong = minutes <= 0;
    sSleepSong = FZNowPlayingSongID();
    sSleepEnd = sSleepEndOfSong ? nil : [NSDate dateWithTimeIntervalSinceNow:minutes * 60];
    sSleepTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        BOOL due = NO;
        if (sSleepEndOfSong) {
            NSTimeInterval duration = FZNowPlayingDuration();
            NSString *song = FZNowPlayingSongID();
            // The last half second of the song, or the next one already started.
            due = (duration > 0 && FZNowPlayingElapsed() >= duration - 0.75) || (song && sSleepSong && ![song isEqualToString:sSleepSong]);
        } else {
            due = sSleepEnd.timeIntervalSinceNow <= 0;
        }
        if (!due) return;
        pauseNow();
        stopSleepTimer();
    }];
    FZLog("player: sleep timer %@", sSleepEndOfSong ? @"at the end of the song" : [NSString stringWithFormat:@"in %.0f min", minutes]);
    [NSNotificationCenter.defaultCenter postNotificationName:FZRSleepTimerDidChangeNotification object:nil];
}

static NSString *sleepSummary(void) {
    if (sSleepEndOfSong) return @"End of song";
    if (!sSleepEnd) return nil;
    return [NSString stringWithFormat:@"%@ left", timeText(MAX(0, sSleepEnd.timeIntervalSinceNow))];
}

static UIMenu *sleepMenu(void) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSNumber *minutes in @[@5, @10, @15, @30, @45, @60]) {
        [items addObject:[UIAction actionWithTitle:[NSString stringWithFormat:@"%@ minutes", minutes] image:nil identifier:nil
                                           handler:^(UIAction *a) { startSleepTimer(minutes.doubleValue); }]];
    }
    [items addObject:[UIAction actionWithTitle:@"End of song" image:[UIImage systemImageNamed:@"music.note"] identifier:nil
                                       handler:^(UIAction *a) { startSleepTimer(0); }]];
    if (sSleepTimer) {
        UIAction *off = [UIAction actionWithTitle:@"Turn off timer" image:[UIImage systemImageNamed:@"xmark"] identifier:nil
                                          handler:^(UIAction *a) { stopSleepTimer(); }];
        off.attributes = UIMenuElementAttributesDestructive;
        [items addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[off]]];
    }
    NSString *summary = sleepSummary();
    return [UIMenu menuWithTitle:summary ? [NSString stringWithFormat:@"Sleep timer · %@", summary] : @"Sleep timer" children:items];
}

#pragma mark - the scrubber

@interface FZRScrubber : UIControl
@property (nonatomic) double value;          // 0…1
@property (nonatomic, readonly) BOOL scrubbing;
@end

@implementation FZRScrubber {
    UIView *_track, *_fill, *_thumb;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _track = [UIView new];
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.24];
    _track.userInteractionEnabled = NO;
    _fill = [UIView new];
    _fill.backgroundColor = UIColor.whiteColor;
    _fill.userInteractionEnabled = NO;
    _thumb = [UIView new];
    _thumb.backgroundColor = UIColor.whiteColor;
    _thumb.userInteractionEnabled = NO;
    for (UIView *v in @[_track, _fill, _thumb]) [self addSubview:v];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Position";
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    return self;
}
- (void)setValue:(double)value {
    _value = MIN(1, MAX(0, isfinite(value) ? value : 0));
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat thickness = _scrubbing ? 6 : 4, thumb = _scrubbing ? 18 : 12;
    CGFloat y = round(b.size.height / 2 - thickness / 2);
    _track.frame = CGRectMake(0, y, b.size.width, thickness);
    _fill.frame = CGRectMake(0, y, b.size.width * _value, thickness);
    _track.layer.cornerRadius = _fill.layer.cornerRadius = thickness / 2;
    _thumb.bounds = CGRectMake(0, 0, thumb, thumb);
    _thumb.layer.cornerRadius = thumb / 2;
    _thumb.center = CGPointMake(MIN(MAX(thumb / 2, b.size.width * _value), b.size.width - thumb / 2), b.size.height / 2);
}
- (void)follow:(UITouch *)touch {
    CGFloat x = [touch locationInView:self].x;
    self.value = self.bounds.size.width > 0 ? x / self.bounds.size.width : 0;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _scrubbing = YES;
    [self follow:touch];
    FZRAnimate(FZRMotionPress, ^{ [self layoutIfNeeded]; }, nil);
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self follow:touch]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _scrubbing = NO;
    FZRAnimate(FZRMotionPress, ^{ [self layoutIfNeeded]; }, nil);
    [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    _scrubbing = NO;
    [self setNeedsLayout];
}
- (void)accessibilityIncrement { self.value += 0.05; [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered]; }
- (void)accessibilityDecrement { self.value -= 0.05; [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered]; }
@end

#pragma mark - lyrics

// NaviMus's own synced lyrics (FZNaviMusLyrics), the sung line bright and the rest dimmed, following the song;
// a line tapped seeks there. PlayerLyrics.x's values: lines fade in over 0.30 s after 0.12 s.
@interface FZRLyricsView : UIScrollView
@property (nonatomic, copy) void (^seek)(NSTimeInterval seconds);
- (BOOL)showSong:(NSString *)songID;
- (void)follow:(NSTimeInterval)seconds;
@end

@implementation FZRLyricsView {
    FZSyncedLyrics *_lyrics;
    NSString *_song;
    NSMutableArray<UILabel *> *_labels;
    NSInteger _current;
    NSTimeInterval _userScrolled;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.showsVerticalScrollIndicator = NO;
    self.alwaysBounceVertical = YES;
    _labels = [NSMutableArray array];
    _current = -1;
    return self;
}
- (BOOL)showSong:(NSString *)songID {
    if (songID && [songID isEqualToString:_song] && _lyrics) return YES;
    _song = [songID copy];
    _lyrics = songID ? FZNaviMusSyncedLyrics(songID) : nil;
    for (UILabel *label in _labels) [label removeFromSuperview];
    [_labels removeAllObjects];
    _current = -1;
    for (FZLyricLine *line in _lyrics.lines) {
        UILabel *label = [UILabel new];
        label.numberOfLines = 0;
        label.text = line.text.length ? line.text : @"♪";
        label.font = FZRFont(UIFontTextStyleTitle2, UIFontWeightBold, UIContentSizeCategoryExtraExtraLarge);
        label.textColor = FZRPrimary();
        label.alpha = 0.35;
        label.userInteractionEnabled = YES;
        [label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
        [self addSubview:label];
        [_labels addObject:label];
    }
    self.contentOffset = CGPointZero;
    [self setNeedsLayout];
    return _lyrics != nil;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, y = self.bounds.size.height * 0.25;
    for (UILabel *label in _labels) {
        CGFloat height = ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
        label.frame = CGRectMake(0, y, width, height);
        y += height + 18;
    }
    self.contentSize = CGSizeMake(width, y + self.bounds.size.height * 0.5);
}
- (void)tapped:(UITapGestureRecognizer *)tap {
    NSUInteger index = [_labels indexOfObject:(UILabel *)tap.view];
    if (index == NSNotFound || index >= _lyrics.lines.count || !self.seek) return;
    self.seek(MAX(0, (_lyrics.lines[index].start + _lyrics.offset) / 1000.0));
}
- (void)follow:(NSTimeInterval)seconds {
    if (!_lyrics) return;
    NSInteger ms = (NSInteger)(seconds * 1000) - _lyrics.offset, current = -1;
    for (NSUInteger i = 0; i < _lyrics.lines.count; i++) {
        if (_lyrics.lines[i].start <= ms) current = (NSInteger)i; else break;
    }
    if (current == _current) return;
    _current = current;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        for (NSUInteger i = 0; i < self->_labels.count; i++) self->_labels[i].alpha = (NSInteger)i == current ? 1 : 0.35;
    } completion:nil];
    // Follows the song unless the user is reading elsewhere (for 3 s after a drag).
    if (self.isDragging || self.isDecelerating) _userScrolled = CACurrentMediaTime();
    if (current < 0 || CACurrentMediaTime() - _userScrolled < 3) return;
    [self layoutIfNeeded];
    UILabel *label = _labels[(NSUInteger)current];
    CGFloat target = MAX(0, MIN(CGRectGetMinY(label.frame) - self.bounds.size.height * 0.28, self.contentSize.height - self.bounds.size.height));
    FZRAnimate(FZRMotionLayout, ^{ self.contentOffset = CGPointMake(0, target); }, nil);
}
@end

#pragma mark - the player

@interface FZRPlayerViewController : UIViewController <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@end

@implementation FZRPlayerViewController {
    FZRArtworkField *_field;
    FZRRoundButton *_close, *_more;
    UILabel *_contextTop, *_contextName;
    UIView *_plate;
    UIImageView *_cover;
    FZRLyricsView *_lyrics;
    UILabel *_title, *_artist;
    FZRRoundButton *_download;
    FZRScrubber *_scrubber;
    UILabel *_elapsed, *_remaining;
    FZRRoundButton *_shuffle, *_previous, *_next, *_repeat;
    UIControl *_play;
    UIImageView *_playGlyph;
    AVRoutePickerView *_route;
    FZRRoundButton *_sleep, *_lyricsButton, *_queue;
    NSTimer *_timer;
    NSString *_coverSong, *_downloadedSong;
    BOOL _lyricsOpen, _shuffleOn;
    NSInteger _repeatMode;   // 0 off, 1 all, 2 one
    CGRect _coverFrame;
}

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalPresentationCapturesStatusBarAppearance = YES;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    _shuffleOn = center.changeShuffleModeCommand.currentShuffleType != MPShuffleTypeOff;
    MPRepeatType repeat = center.changeRepeatModeCommand.currentRepeatType;
    _repeatMode = repeat == MPRepeatTypeAll ? 1 : repeat == MPRepeatTypeOne ? 2 : 0;
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (FZRRoundButton *)button:(NSString *)symbol size:(CGFloat)size label:(NSString *)label action:(SEL)action {
    FZRRoundButton *button = [[FZRRoundButton alloc] initWithSymbol:symbol pointSize:size weight:UIImageSymbolWeightRegular label:label];
    button.circled = NO;
    if (action) [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    return button;
}

- (UILabel *)label:(UIFontTextStyle)style weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.font = FZRFont(style, weight, UIContentSizeCategoryExtraExtraLarge);
    label.textColor = color;
    [self.view addSubview:label];
    return label;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    view.backgroundColor = FZRNeutralField();
    view.clipsToBounds = YES;
    _field = [[FZRArtworkField alloc] initWithFrame:view.bounds];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_field];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fieldColored:) name:FZRFieldColorDidChangeNotification object:_field];

    _close = [self button:@"chevron.down" size:19 label:@"Close" action:@selector(closePlayer)];
    _close.circled = YES;
    _more = [self button:@"ellipsis" size:19 label:@"More" action:nil];
    _more.circled = YES;
    _contextTop = [self label:UIFontTextStyleCaption2 weight:UIFontWeightSemibold color:FZRSecondary()];
    _contextTop.textAlignment = NSTextAlignmentCenter;
    _contextName = [self label:UIFontTextStyleFootnote weight:UIFontWeightBold color:FZRPrimary()];
    _contextName.textAlignment = NSTextAlignmentCenter;

    // The shadow plate: a rounded rect under the cover carrying its shadow (shadow.artwork).
    _plate = [UIView new];
    _plate.layer.shadowColor = UIColor.blackColor.CGColor;
    _plate.layer.shadowOpacity = 0.45;
    _plate.layer.shadowRadius = 32;
    _plate.layer.shadowOffset = CGSizeMake(0, 12);
    _plate.userInteractionEnabled = NO;
    [view addSubview:_plate];
    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = FZRRadiusArtwork;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [_plate addSubview:_cover];

    _lyrics = [FZRLyricsView new];
    _lyrics.alpha = 0;
    _lyrics.hidden = YES;
    __weak typeof(self) weakSelf = self;
    _lyrics.seek = ^(NSTimeInterval seconds) { [weakSelf seekTo:seconds]; };
    [view addSubview:_lyrics];

    _title = [self label:UIFontTextStyleTitle2 weight:UIFontWeightBold color:FZRPrimary()];
    _artist = [self label:UIFontTextStyleBody weight:UIFontWeightRegular color:FZRSecondary()];
    _download = [self button:@"arrow.down.circle" size:26 label:@"Download" action:@selector(download)];

    _scrubber = [FZRScrubber new];
    [_scrubber addTarget:self action:@selector(scrubbing) forControlEvents:UIControlEventValueChanged];
    [_scrubber addTarget:self action:@selector(scrubbed) forControlEvents:UIControlEventPrimaryActionTriggered];
    [view addSubview:_scrubber];
    _elapsed = [self label:UIFontTextStyleCaption1 weight:UIFontWeightMedium color:FZRTertiary()];
    _remaining = [self label:UIFontTextStyleCaption1 weight:UIFontWeightMedium color:FZRTertiary()];
    _elapsed.font = FZRMonospacedDigitsFont(_elapsed.font);
    _remaining.font = FZRMonospacedDigitsFont(_remaining.font);
    _remaining.textAlignment = NSTextAlignmentRight;

    _shuffle = [self button:@"shuffle" size:kSmallGlyph label:@"Shuffle" action:@selector(toggleShuffle)];
    _previous = [self button:@"backward.fill" size:kSkipGlyph label:@"Previous" action:@selector(previous)];
    _next = [self button:@"forward.fill" size:kSkipGlyph label:@"Next" action:@selector(next)];
    _repeat = [self button:@"repeat" size:kSmallGlyph label:@"Repeat" action:@selector(cycleRepeat)];
    _play = [UIControl new];
    _play.backgroundColor = UIColor.whiteColor;
    _play.isAccessibilityElement = YES;
    _play.accessibilityTraits = UIAccessibilityTraitButton;
    [_play addTarget:self action:@selector(playPause) forControlEvents:UIControlEventTouchUpInside];
    [_play addTarget:self action:@selector(pressPlay:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_play addTarget:self action:@selector(releasePlay:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    _playGlyph = [UIImageView new];
    _playGlyph.contentMode = UIViewContentModeCenter;
    _playGlyph.tintColor = UIColor.blackColor;
    [_play addSubview:_playGlyph];
    [view addSubview:_play];

    _route = [AVRoutePickerView new];
    _route.tintColor = FZRPrimary();
    _route.activeTintColor = FZRAccent();
    [view addSubview:_route];
    _sleep = [self button:@"moon.zzz" size:kSmallGlyph label:@"Sleep timer" action:nil];
    _lyricsButton = [self button:@"quote.bubble" size:kSmallGlyph label:@"Lyrics" action:@selector(toggleLyrics)];
    _queue = [self button:@"list.bullet" size:kSmallGlyph label:@"Queue" action:@selector(openQueue)];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
    pan.delegate = self;
    [view addGestureRecognizer:pan];
    UITapGestureRecognizer *coverTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playPause)];
    coverTap.numberOfTapsRequired = 2;
    _plate.userInteractionEnabled = YES;
    [_plate addGestureRecognizer:coverTap];

    for (NSNotificationName name in @[FZNowPlayingDidChangeNotification, FZRSleepTimerDidChangeNotification, NSUserDefaultsDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:name object:nil];
    }
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_timer invalidate];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    [self refresh];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

#pragma mark state

- (void)refresh {
    if (!self.isViewLoaded) return;
    NSDictionary *info = FZNowPlayingInfo();
    _title.text = string(info[MPMediaItemPropertyTitle]) ?: @"Not playing";
    _artist.text = string(info[MPMediaItemPropertyArtist]) ?: string(info[MPMediaItemPropertyAlbumArtist]) ?: @"";
    NSString *album = string(info[MPMediaItemPropertyAlbumTitle]);
    _contextTop.text = album ? @"PLAYING FROM ALBUM" : @"";
    _contextName.text = album ?: @"";
    _contextTop.hidden = _contextName.hidden = !FZEnabled(FZRKeyPlayerContext);

    NSString *song = FZNowPlayingSongID() ?: _title.text;
    // The check after a download stays with that song.
    BOOL downloaded = _downloadedSong && [song isEqualToString:_downloadedSong];
    [_download setSymbol:downloaded ? @"checkmark.circle.fill" : @"arrow.down.circle"];
    _download.glyph.tintColor = downloaded ? FZRAccent() : FZRPrimary();
    if (![song isEqualToString:_coverSong] || !_cover.image) {
        UIImage *image = FZNowPlayingArtwork(CGSizeMake(600, 600));
        if (image) {
            BOOL animated = _cover.image != nil && self.view.window != nil;
            if (animated) {
                [UIView transitionWithView:_cover duration:FZRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                                animations:^{ self->_cover.image = image; } completion:nil];
            } else {
                _cover.image = image;
            }
            [_field setArtwork:image identity:song animated:animated];
            _coverSong = song;
        }
        if (_lyricsOpen && ![_lyrics showSong:FZNowPlayingSongID()]) [self setLyricsOpen:NO];
    }

    BOOL playing = FZNowPlayingIsPlaying();
    _playGlyph.image = [UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightBold]];
    _play.accessibilityLabel = playing ? @"Pause" : @"Play";
    _shuffle.glyph.tintColor = _shuffleOn ? FZRAccent() : FZRPrimary();
    [_repeat setSymbol:_repeatMode == 2 ? @"repeat.1" : @"repeat"];
    _repeat.glyph.tintColor = _repeatMode ? FZRAccent() : FZRPrimary();
    _sleep.glyph.tintColor = sSleepTimer ? FZRAccent() : FZRPrimary();
    _sleep.menu = sleepMenu();
    _lyricsButton.glyph.tintColor = _lyricsOpen ? FZRAccent() : FZRPrimary();
    [_lyricsButton setSymbol:_lyricsOpen ? @"quote.bubble.fill" : @"quote.bubble"];
    _more.menu = [self moreMenu];

    _download.hidden = !FZEnabled(FZRKeyPlayerDownload);
    _shuffle.hidden = !FZEnabled(FZRKeyPlayerShuffle);
    _repeat.hidden = !FZEnabled(FZRKeyPlayerRepeat);
    _route.hidden = !FZEnabled(FZRKeyPlayerAirPlay);
    _sleep.hidden = !FZEnabled(FZRKeyPlayerSleep);
    _lyricsButton.hidden = !FZEnabled(FZRKeyPlayerLyrics);
    _queue.hidden = !FZEnabled(FZRKeyPlayerQueue);
    _more.hidden = !FZEnabled(FZRKeyPlayerMore);
    _elapsed.hidden = _remaining.hidden = !FZEnabled(FZRKeyPlayerTimes);
    [self tick];
    [self.view setNeedsLayout];
    [self showPaused:!playing animated:self.view.window != nil];
}

- (void)tick {
    NSTimeInterval duration = FZNowPlayingDuration(), elapsed = FZNowPlayingElapsed();
    if (!_scrubber.scrubbing) {
        _scrubber.value = duration > 0 ? elapsed / duration : 0;
        _elapsed.text = timeText(elapsed);
        _remaining.text = [@"-" stringByAppendingString:timeText(MAX(0, duration - elapsed))];
    }
    if (_lyricsOpen) [_lyrics follow:elapsed];
}

- (void)fieldColored:(NSNotification *)note {
    UIColor *color = note.userInfo[@"color"];
    if (color) FZRAnimate(FZRMotionFade, ^{ self->_playGlyph.tintColor = color; }, nil);
}

- (void)showPaused:(BOOL)paused animated:(BOOL)animated {
    CGFloat scale = paused && FZEnabled(FZRKeyPlayerShrink) && !_lyricsOpen ? (FZRReduceMotion() ? kPausedScaleReduced : kPausedScale) : 1;
    if (CGAffineTransformEqualToTransform(_plate.transform, CGAffineTransformMakeScale(scale, scale))) return;
    void (^change)(void) = ^{ self->_plate.transform = CGAffineTransformMakeScale(scale, scale); };
    if (animated) FZRAnimate(FZRMotionLayout, change, nil); else change();
}

#pragma mark layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat width = b.size.width, side = kSide + MAX(safe.left, safe.right);

    CGFloat headerY = safe.top + kHeaderTop;
    _close.frame = CGRectMake(16 + safe.left, headerY, kCircle, kCircle);
    _more.frame = CGRectMake(width - 16 - safe.right - kCircle, headerY, kCircle, kCircle);
    CGFloat contextX = CGRectGetMaxX(_close.frame) + 8, contextW = CGRectGetMinX(_more.frame) - 8 - contextX;
    CGFloat topH = ceil(_contextTop.font.lineHeight), nameH = ceil(_contextName.font.lineHeight);
    CGFloat contextY = headerY + round((kCircle - topH - nameH) / 2);
    _contextTop.frame = CGRectMake(contextX, contextY, contextW, topH);
    _contextName.frame = CGRectMake(contextX, contextY + topH, contextW, nameH);

    // From the bottom up: footer, controls, times, scrubber, title.
    CGFloat footerBottom = b.size.height - MAX(safe.bottom + kFooterAbove - 14, kFooterMinBottom);
    CGFloat footerY = footerBottom - kCircle;
    NSMutableArray<UIView *> *footerRight = [NSMutableArray array];
    for (UIView *v in @[_sleep, _lyricsButton, _queue]) if (!v.hidden) [footerRight addObject:v];
    _route.frame = CGRectMake(side - 8, footerY, kCircle, kCircle);
    CGFloat x = width - side + 8;
    for (UIView *v in footerRight.reverseObjectEnumerator) {
        x -= kCircle;
        v.frame = CGRectMake(x, footerY, kCircle, kCircle);
        x -= 12;
    }
    BOOL footer = !_route.hidden || footerRight.count;

    CGFloat controlsY = (footer ? footerY - 20 : footerBottom) - kPlayCircle;
    CGFloat inner = width - 2 * side;
    _play.frame = CGRectMake(round((width - kPlayCircle) / 2), controlsY, kPlayCircle, kPlayCircle);
    _play.layer.cornerRadius = kPlayCircle / 2;
    _playGlyph.frame = _play.bounds;
    CGFloat skipW = 56, mid = CGRectGetMidY(_play.frame);
    CGFloat skipGap = MIN(28, (inner / 2 - kPlayCircle / 2 - skipW - kCircle) / 2 + 12);
    _previous.frame = CGRectMake(CGRectGetMinX(_play.frame) - skipGap - skipW, mid - skipW / 2, skipW, skipW);
    _next.frame = CGRectMake(CGRectGetMaxX(_play.frame) + skipGap, mid - skipW / 2, skipW, skipW);
    _shuffle.frame = CGRectMake(side - 10, mid - kCircle / 2, kCircle, kCircle);
    _repeat.frame = CGRectMake(width - side + 10 - kCircle, mid - kCircle / 2, kCircle, kCircle);

    CGFloat timesH = ceil(_elapsed.font.lineHeight);
    CGFloat timesY = controlsY - 16 - (_elapsed.hidden ? 0 : timesH);
    _elapsed.frame = CGRectMake(side, timesY, inner / 2, timesH);
    _remaining.frame = CGRectMake(side + inner / 2, timesY, inner / 2, timesH);
    CGFloat scrubH = 28;
    _scrubber.frame = CGRectMake(side, timesY - scrubH + (_elapsed.hidden ? 0 : 4), inner, scrubH);

    CGFloat titleH = ceil(_title.font.lineHeight), artistH = ceil(_artist.font.lineHeight);
    CGFloat titleY = CGRectGetMinY(_scrubber.frame) - 12 - titleH - artistH;
    CGFloat textW = inner - (_download.hidden ? 0 : kCircle + 8);
    _title.frame = CGRectMake(side, titleY, textW, titleH);
    _artist.frame = CGRectMake(side, titleY + titleH, textW, artistH);
    _download.frame = CGRectMake(width - side - kCircle + 8, titleY + round((titleH + artistH - kCircle) / 2), kCircle, kCircle);

    // The cover: as large as fits between the header and the title, centred in that space.
    CGFloat top = headerY + kCircle + 24, bottom = titleY - 28;
    CGFloat coverSide = MAX(0, MIN(inner, bottom - top));
    CGRect cover = CGRectMake(round((width - coverSide) / 2), top + round((bottom - top - coverSide) / 2), coverSide, coverSide);
    CGAffineTransform transform = _plate.transform;
    _plate.transform = CGAffineTransformIdentity;
    _plate.frame = cover;
    _plate.transform = transform;
    _cover.frame = _plate.bounds;
    _plate.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_plate.bounds cornerRadius:FZRRadiusArtwork].CGPath;
    _coverFrame = cover;
    _lyrics.frame = CGRectMake(side, top - 8, inner, bottom - top + 8);
}

#pragma mark actions

- (void)closePlayer { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)pressPlay:(UIControl *)control { FZRAnimate(FZRMotionPress, ^{ control.transform = CGAffineTransformMakeScale(0.92, 0.92); }, nil); }
- (void)releasePlay:(UIControl *)control { FZRAnimate(FZRMotionPress, ^{ control.transform = CGAffineTransformIdentity; }, nil); }

- (void)playPause {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    BOOL done = FZRemoteSend(center.togglePlayPauseCommand) || FZRemoteSend(FZNowPlayingIsPlaying() ? center.pauseCommand : center.playCommand);
    if (!done) FZLogError("player: NaviMus has no play/pause handler");
}

- (void)next { if (!FZRemoteSend(MPRemoteCommandCenter.sharedCommandCenter.nextTrackCommand)) FZLogError("player: no next-track handler"); }

// NaviMus's own previous-track handler, as the lock screen's button.
- (void)previous {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    if (!FZRemoteSend(center.previousTrackCommand)) FZLogError("player: no previous-track handler");
}

- (void)toggleShuffle {
    BOOL on = !_shuffleOn;
    BOOL ok = FZRemoteSendWithOptions(MPRemoteCommandCenter.sharedCommandCenter.changeShuffleModeCommand,
                                      @{@"kMRMediaRemoteOptionShuffleMode": on ? @3 : @1});
    FZLog("player: shuffle %@ → %d", on ? @"on" : @"off", ok);
    if (ok) _shuffleOn = on;
    [self refresh];
}

- (void)cycleRepeat {
    NSInteger mode = (_repeatMode + 1) % 3;
    // MediaRemote's repeat modes: 1 off, 2 one, 3 all.
    NSNumber *option = mode == 0 ? @1 : mode == 2 ? @2 : @3;
    BOOL ok = FZRemoteSendWithOptions(MPRemoteCommandCenter.sharedCommandCenter.changeRepeatModeCommand,
                                      @{@"kMRMediaRemoteOptionRepeatMode": option});
    FZLog("player: repeat %ld → %d", (long)mode, ok);
    if (ok) _repeatMode = mode;
    [self refresh];
}

- (void)seekTo:(NSTimeInterval)seconds {
    BOOL ok = FZRemoteSeek(seconds);
    if (!ok) FZLogError("player: NaviMus has no change-position handler");
}

- (void)scrubbing {
    NSTimeInterval duration = FZNowPlayingDuration();
    _elapsed.text = timeText(_scrubber.value * duration);
    _remaining.text = [@"-" stringByAppendingString:timeText(MAX(0, duration - _scrubber.value * duration))];
}

- (void)scrubbed {
    NSTimeInterval duration = FZNowPlayingDuration();
    if (duration > 0) [self seekTo:_scrubber.value * duration];
}

- (void)setLyricsOpen:(BOOL)open {
    _lyricsOpen = open;
    if (open) _lyrics.hidden = NO;
    FZRAnimate(FZRMotionLayout, ^{
        self->_lyrics.alpha = open ? 1 : 0;
        self->_plate.alpha = open ? 0 : 1;
        self->_lyrics.transform = open ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.96, 0.96);
    }, ^(BOOL finished) {
        if (!self->_lyricsOpen) self->_lyrics.hidden = YES;
    });
    [self refresh];
}

- (void)toggleLyrics {
    if (_lyricsOpen) { [self setLyricsOpen:NO]; return; }
    if ([_lyrics showSong:FZNowPlayingSongID()]) {
        [self setLyricsOpen:YES];
        [_lyrics follow:FZNowPlayingElapsed()];
        return;
    }
    // No synced lyrics saved for this song: NaviMus's own player has its lyrics (and fetches them).
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No synced lyrics yet"
        message:@"NaviMus hasn't saved synced lyrics for this song. Open NaviMus's own player to load them?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self openNaviMusPlayer]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openNaviMusPlayer {
    UIViewController *presenter = self.presentingViewController;
    [self dismissViewControllerAnimated:YES completion:^{
        UITabBarController *tabs = FZRPlayerTabs();
        if (tabs) FZRShowNaviMusPlayer(tabs, FZRPlayerMiniBar());
        (void)presenter;
    }];
}

// NaviMus's queue: in its own player, for now.
- (void)openQueue { [self openNaviMusPlayer]; }

- (void)download {
    UITabBarController *tabs = FZRPlayerTabs();
    __weak typeof(self) weakSelf = self;
    _download.enabled = NO;
    FZRNaviMusPlayerAction(tabs, FZRPlayerMiniBar(), @[@"Download", @"Download Song", @"Download Track", @"Remove Download", @"Delete Download"],
                           ^(BOOL ok, NSString *why) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_download.enabled = YES;
        FZLog("player: download → %d%@", ok, why ? [@" " stringByAppendingString:why] : @"");
        if (ok) {
            strongSelf->_downloadedSong = FZNowPlayingSongID() ?: strongSelf->_title.text;
            [strongSelf refresh];
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't download" message:why preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Open NaviMus's player" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf openNaviMusPlayer]; }]];
        [strongSelf presentViewController:alert animated:YES completion:nil];
    });
}

// Every feature of the player, those still to come shown greyed out (REDESIGN_PLAN.md R3).
- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *now = [NSMutableArray array];
    [now addObject:[UIAction actionWithTitle:@"Download" image:[UIImage systemImageNamed:@"arrow.down.circle"] identifier:nil
                                     handler:^(UIAction *a) { [weakSelf download]; }]];
    [now addObject:[UIAction actionWithTitle:@"Lyrics" image:[UIImage systemImageNamed:@"quote.bubble"] identifier:nil
                                     handler:^(UIAction *a) { [weakSelf toggleLyrics]; }]];
    [now addObject:sleepMenu()];
    [now addObject:[UIAction actionWithTitle:@"Queue and more in NaviMus's player" image:[UIImage systemImageNamed:@"list.bullet"] identifier:nil
                                     handler:^(UIAction *a) { [weakSelf openNaviMusPlayer]; }]];
    NSMutableArray *coming = [NSMutableArray array];
    for (NSArray *item in @[@[@"Speed and pitch", @"gauge.with.dots.needle.50percent"], @[@"Reverb", @"waveform"], @[@"AutoMix", @"arrow.triangle.merge"],
                            @[@"Music Haptics", @"iphone.radiowaves.left.and.right"], @[@"Artwork modes", @"photo.on.rectangle"]]) {
        UIAction *action = [UIAction actionWithTitle:item[0] image:[UIImage systemImageNamed:item[1]] identifier:nil handler:^(UIAction *a) {}];
        action.subtitle = @"Coming in a later Frozio build";
        action.attributes = UIMenuElementAttributesDisabled;
        [coming addObject:action];
    }
    return [UIMenu menuWithTitle:@"" children:@[
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:now],
        [UIMenu menuWithTitle:@"Coming" image:[UIImage systemImageNamed:@"sparkles"] identifier:nil options:0 children:coming],
    ]];
}

#pragma mark swipe down to close

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (![gesture isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:self.view];
    CGPoint start = [gesture locationInView:self.view];
    // Down and not on the scrubber or in scrolled lyrics.
    if (CGRectContainsPoint(CGRectInset(_scrubber.frame, 0, -10), start)) return NO;
    if (_lyricsOpen && CGRectContainsPoint(_lyrics.frame, start) && _lyrics.contentOffset.y > 1) return NO;
    return velocity.y > fabs(velocity.x);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    CGFloat y = MAX(0, [pan translationInView:self.view].y);
    switch (pan.state) {
        case UIGestureRecognizerStateChanged:
            self.view.transform = CGAffineTransformMakeTranslation(0, y);
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat velocity = [pan velocityInView:self.view].y;
            if (pan.state == UIGestureRecognizerStateEnded && (y > 140 || velocity > 900)) {
                [self dismissViewControllerAnimated:YES completion:nil];
            } else {
                FZRAnimate(FZRMotionRespond, ^{ self.view.transform = CGAffineTransformIdentity; }, nil);
            }
            break;
        }
        default: break;
    }
}
@end

#pragma mark - opening it

void FZRPresentPlayer(void) {
    UITabBarController *tabs = FZRPlayerTabs();
    UIViewController *top = tabs.view.window.rootViewController ?: tabs;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    if ([top isKindOfClass:FZRPlayerViewController.class]) return;
    FZLog("player: opening Frozio's player");
    [top presentViewController:[FZRPlayerViewController new] animated:YES completion:nil];
}

#pragma mark - options

NSArray *FZRPlayerOptionSections(void) {
    FZModRow *rebuilt = FZWithSymbol(FZSwitchRow(@"Rebuilt mini player and player", @"Off brings back NaviMus's own.", FZRKeyPlayerRebuilt), @"play.rectangle");
    FZModRow *miniPlay = FZWithSymbol(FZSwitchRow(@"Play and pause", nil, @"fz.redesign.mini.playPause"), @"playpause");
    FZModRow *miniPrevious = FZWithSymbol(FZOptionRow(@"Previous", nil, @"fz.redesign.mini.previous"), @"backward");
    FZModRow *miniNext = FZWithSymbol(FZSwitchRow(@"Next", nil, @"fz.redesign.mini.next"), @"forward");
    FZModRow *miniAirPlay = FZWithSymbol(FZOptionRow(@"AirPlay", nil, @"fz.redesign.mini.airplay"), @"airplayaudio");
    FZModRow *miniDownload = FZWithSymbol(FZSwitchRow(@"Download", @"In place of chroma.pw's +.", @"fz.redesign.mini.download"), @"arrow.down.circle");
    FZModRow *miniProgress = FZWithSymbol(FZSwitchRow(@"Progress line", nil, @"fz.redesign.mini.progress"), @"minus");
    FZModRow *miniRound = FZWithSymbol(FZOptionRow(@"Round cover", nil, @"fz.redesign.mini.roundArtwork"), @"circle");
    FZModRow *miniSwipe = FZWithSymbol(FZSwitchRow(@"Swipe to change song", nil, @"fz.redesign.mini.swipe"), @"hand.draw");

    FZModRow *context = FZWithSymbol(FZSwitchRow(@"Playing from", nil, FZRKeyPlayerContext), @"text.alignleft");
    FZModRow *download = FZWithSymbol(FZSwitchRow(@"Download", @"In place of chroma.pw's +.", FZRKeyPlayerDownload), @"arrow.down.circle");
    FZModRow *shuffle = FZWithSymbol(FZSwitchRow(@"Shuffle", nil, FZRKeyPlayerShuffle), @"shuffle");
    FZModRow *repeat = FZWithSymbol(FZSwitchRow(@"Repeat", nil, FZRKeyPlayerRepeat), @"repeat");
    FZModRow *times = FZWithSymbol(FZSwitchRow(@"Elapsed and remaining", nil, FZRKeyPlayerTimes), @"clock");
    FZModRow *airPlay = FZWithSymbol(FZSwitchRow(@"AirPlay", nil, FZRKeyPlayerAirPlay), @"airplayaudio");
    FZModRow *sleep = FZWithSymbol(FZSwitchRow(@"Sleep timer", nil, FZRKeyPlayerSleep), @"moon.zzz");
    FZModRow *lyrics = FZWithSymbol(FZSwitchRow(@"Lyrics", nil, FZRKeyPlayerLyrics), @"quote.bubble");
    FZModRow *queue = FZWithSymbol(FZSwitchRow(@"Queue", @"Opens NaviMus's own player for now.", FZRKeyPlayerQueue), @"list.bullet");
    FZModRow *more = FZWithSymbol(FZSwitchRow(@"⋯ menu", nil, FZRKeyPlayerMore), @"ellipsis.circle");
    FZModRow *shrink = FZWithSymbol(FZSwitchRow(@"Smaller cover while paused", nil, FZRKeyPlayerShrink), @"arrow.down.right.and.arrow.up.left");
    return @[
        FZNotedSection(@"Player", @[rebuilt], @"Applies right away."),
        FZSection(@"Mini player", @[miniPlay, miniPrevious, miniNext, miniAirPlay, miniDownload, miniProgress, miniRound, miniSwipe]),
        FZSection(@"Player buttons", @[context, download, shuffle, repeat, times, airPlay, sleep, lyrics, queue, more, shrink]),
    ];
}
