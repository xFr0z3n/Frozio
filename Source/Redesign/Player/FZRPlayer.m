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
#import <objc/message.h>
#import "Redesign/Player/FZRPlayer.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Redesign/Kit/FZRField.h"
#import "Redesign/Kit/FZRKawarp.h"
#import "Redesign/Player/FZRQueue.h"
#import "Redesign/Data/FZServer.h"
#import "Redesign/FZRNaviMusControls.h"
#import "Redesign/Kit/FZRRoundButton.h"
#import "Redesign/Album/FZRAlbumPage.h"
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

static const CGFloat kSide = 24, kHeaderTop = 4, kCircle = 44, kSkipGlyph = 32, kSmallGlyph = 24;
static const CGFloat kPausedScale = 0.84, kPausedScaleReduced = 0.92, kFooterMinBottom = 34;

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
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
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
    // chroma.pw: a 4 pt line with no knob; touched, it thickens and a knob shows.
    CGFloat thickness = _scrubbing ? 6 : 4, thumb = _scrubbing ? 16 : 0;
    CGFloat y = round(b.size.height / 2 - thickness / 2);
    _track.frame = CGRectMake(0, y, b.size.width, thickness);
    _fill.frame = CGRectMake(0, y, b.size.width * _value, thickness);
    _track.layer.cornerRadius = _fill.layer.cornerRadius = thickness / 2;
    _thumb.bounds = CGRectMake(0, 0, thumb, thumb);
    _thumb.layer.cornerRadius = thumb / 2;
    _thumb.hidden = thumb <= 0;
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

// NaviMus's own synced lyrics (FZNaviMusLyrics) as chroma.pw shows them (the user's screenshot): big bold lines on
// the left, the sung one white, the rest dimmed and blurred the further they are from it, the lines fading out at the
// top and bottom; a line tapped seeks there. Values from taurus/tweak/Sources/Redesigned/Lyrics/SGRKaraokeView.m and
// LyricsLook.m @ fe3211c (GPL-3.0): 30 pt bold lines 24 pt apart (its "Apple Music" look), dim 0.3, 1.4 pt of blur
// a line away up to 6, the sung line resting 28 % down, a 10 % fade at each edge, 3 s before following again after
// a scroll by hand.
static const CGFloat kLyricsSize = 30, kLyricsGap = 24, kLyricsDim = 0.3, kBlurPerLine = 1.4, kMaxBlur = 6;
static const CGFloat kLyricsAnchor = 0.28, kLyricsEdgeFade = 0.1;
static const NSTimeInterval kBrowseHold = 3;
// The lyrics' and the queue's layout (taurus PlayerLyrics.x @ fe3211c, GPL-3.0).
static const CGFloat kThumbSide = 72, kThumbGap = 16, kTitleGap = 12, kLyricsTop = 20, kLyricsBottom = 8;

@interface FZRLyricsView : UIScrollView <UIScrollViewDelegate>
@property (nonatomic, copy) void (^seek)(NSTimeInterval seconds);
- (BOOL)showSong:(NSString *)songID;
- (void)follow:(NSTimeInterval)seconds;
@end

@implementation FZRLyricsView {
    FZSyncedLyrics *_lyrics;
    NSString *_song;
    NSMutableArray<UIView *> *_lines;     // each line's own view, which takes the blur (SGRKaraokeLineView's way)
    NSInteger _current;
    CFTimeInterval _browsed;
    CAGradientLayer *_fade;
}
// Room around a line's text inside its view, so its blur isn't cut off at the edges.
static const CGFloat kBlurRoom = 12;

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.showsVerticalScrollIndicator = NO;
    self.alwaysBounceVertical = YES;
    self.delegate = self;
    self.clipsToBounds = NO;
    _lines = [NSMutableArray array];
    _current = -1;
    _fade = [CAGradientLayer layer];
    _fade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    _fade.locations = @[@0, @(kLyricsEdgeFade), @(1 - kLyricsEdgeFade), @1];
    self.layer.mask = _fade;
    return self;
}
- (BOOL)showSong:(NSString *)songID {
    if (songID && [songID isEqualToString:_song] && _lyrics) return YES;
    _song = [songID copy];
    _lyrics = songID ? FZNaviMusSyncedLyrics(songID) : nil;
    for (UIView *line in _lines) [line removeFromSuperview];
    [_lines removeAllObjects];
    _current = -1;
    UIFont *font = [UIFont systemFontOfSize:kLyricsSize weight:UIFontWeightBold];
    for (FZLyricLine *line in _lyrics.lines) {
        UIView *holder = [UIView new];
        holder.backgroundColor = UIColor.clearColor;
        holder.opaque = NO;
        UILabel *label = [UILabel new];
        label.numberOfLines = 0;
        label.text = line.text.length ? line.text : @"♪";
        label.font = font;
        label.textColor = FZRPrimary();
        label.backgroundColor = UIColor.clearColor;
        [holder addSubview:label];
        [holder addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
        Class cls = NSClassFromString(@"CAFilter");
        SEL make = NSSelectorFromString(@"filterWithType:");
        if ([cls respondsToSelector:make]) holder.layer.filters = @[((id (*)(id, SEL, NSString *))objc_msgSend)(cls, make, @"gaussianBlur")];
        [self addSubview:holder];
        [_lines addObject:holder];
    }
    self.contentOffset = CGPointZero;
    [self setNeedsLayout];
    [self restyleAnimated:NO];
    return _lyrics != nil;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fade.frame = CGRectMake(-kBlurRoom, self.contentOffset.y, self.bounds.size.width + 2 * kBlurRoom, self.bounds.size.height);
    [CATransaction commit];
    CGFloat width = self.bounds.size.width, y = self.bounds.size.height * kLyricsAnchor;
    for (UIView *holder in _lines) {
        UILabel *label = holder.subviews.firstObject;
        CGFloat height = ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
        CGRect frame = CGRectMake(-kBlurRoom, y - kBlurRoom, width + 2 * kBlurRoom, height + 2 * kBlurRoom);
        if (!CGRectEqualToRect(holder.frame, frame)) {
            holder.frame = frame;
            label.frame = CGRectMake(kBlurRoom, kBlurRoom, width, height);
        }
        y += height + kLyricsGap;
    }
    CGSize size = CGSizeMake(width, y + self.bounds.size.height * (1 - kLyricsAnchor));
    if (!CGSizeEqualToSize(self.contentSize, size)) self.contentSize = size;
}
// A line's blur eases from wherever it is on screen (SGRKaraokeView's -setBlur:, 0.6 s).
static void blurLine(UIView *holder, CGFloat radius, BOOL animated) {
    if (!holder.layer.filters.count) return;
    NSString *path = @"filters.gaussianBlur.inputRadius";
    id shown = [holder.layer.presentationLayer valueForKeyPath:path];
    [holder.layer setValue:@(radius) forKeyPath:path];
    if (!animated) return;
    CABasicAnimation *ease = [CABasicAnimation animationWithKeyPath:path];
    ease.fromValue = [shown isKindOfClass:NSNumber.class] ? shown : @(radius);
    ease.toValue = @(radius);
    ease.duration = 0.6;
    ease.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [holder.layer addAnimation:ease forKey:@"blur"];
}
- (void)restyleAnimated:(BOOL)animated {
    for (NSUInteger i = 0; i < _lines.count; i++) {
        NSInteger distance = _current < 0 ? 1 : labs((NSInteger)i - _current);
        UIView *holder = _lines[i];
        blurLine(holder, MIN(kMaxBlur, kBlurPerLine * distance), animated);
    }
    void (^apply)(void) = ^{
        for (NSUInteger i = 0; i < self->_lines.count; i++) {
            NSInteger distance = self->_current < 0 ? 1 : labs((NSInteger)i - self->_current);
            self->_lines[i].alpha = distance == 0 ? 1 : kLyricsDim;
        }
    };
    if (animated) [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                                   animations:apply completion:nil];
    else apply();
}
- (void)tapped:(UITapGestureRecognizer *)tap {
    NSUInteger index = [_lines indexOfObject:tap.view];
    if (index == NSNotFound || index >= _lyrics.lines.count || !self.seek) return;
    self.seek(MAX(0, (_lyrics.lines[index].start + _lyrics.offset) / 1000.0));
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scroll { _browsed = CACurrentMediaTime(); }
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scroll { _browsed = CACurrentMediaTime(); }
- (void)follow:(NSTimeInterval)seconds {
    if (!_lyrics) return;
    NSInteger ms = (NSInteger)(seconds * 1000) - _lyrics.offset, current = -1;
    for (NSUInteger i = 0; i < _lyrics.lines.count; i++) {
        if (_lyrics.lines[i].start <= ms) current = (NSInteger)i; else break;
    }
    if (current == _current) return;
    _current = current;
    [self restyleAnimated:YES];
    if (current < 0 || self.isDragging || self.isDecelerating || CACurrentMediaTime() - _browsed < kBrowseHold) return;
    [self layoutIfNeeded];
    UIView *holder = _lines[(NSUInteger)current];
    CGFloat lineTop = CGRectGetMinY(holder.frame) + kBlurRoom;
    CGFloat target = MAX(0, MIN(lineTop - self.bounds.size.height * kLyricsAnchor, self.contentSize.height - self.bounds.size.height));
    FZRAnimate(FZRMotionLayout, ^{ self.contentOffset = CGPointMake(0, target); [self layoutIfNeeded]; }, nil);
}
@end

#pragma mark - queue

// NaviMus's queue (FZRQueue) in its own sections, as NaviMus's player lists it: what was added to play next, the rest
// of what's playing, then autoplay. A song tapped is reached with NaviMus's own next-track handler, once per song
// before it, so NaviMus's queue stays its own.
@interface FZRQueueView : UITableView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, readonly) NSCache<NSString *, UIImage *> *coverCache;
- (void)reload;
@end

@implementation FZRQueueView {
    NSArray<NSDictionary *> *_sections;   // {title, songs}
    NSCache<NSString *, UIImage *> *_covers;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame style:UITableViewStylePlain])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.dataSource = self;
    self.delegate = self;
    self.rowHeight = 60;
    self.showsVerticalScrollIndicator = NO;
    // Rows flush with the section titles and the player's 24 pt margin.
    self.layoutMargins = UIEdgeInsetsZero;
    self.cellLayoutMarginsFollowReadableWidth = NO;
    self.preservesSuperviewLayoutMargins = NO;
    if (@available(iOS 15.0, *)) self.sectionHeaderTopPadding = 0;
    _covers = [NSCache new];
    [self registerClass:UITableViewCell.class forCellReuseIdentifier:@"song"];
    return self;
}
- (void)reload {
    NSDictionary *queue = FZRNaviMusQueue();
    NSMutableArray *sections = [NSMutableArray array];
    NSString *album = string(queue[@"current"][@"album"]);
    NSArray *parts = @[@[@"next", @"Playing Next"], @[@"context", album ? [@"Next from: " stringByAppendingString:album] : @"Up Next"], @[@"autoplay", @"Autoplay"]];
    for (NSArray *part in parts) {
        NSArray *songs = queue[part[0]];
        if ([songs isKindOfClass:NSArray.class] && songs.count) [sections addObject:@{@"title": part[1], @"songs": songs}];
    }
    _sections = sections;
    [self reloadData];
    self.backgroundView = sections.count ? nil : ({
        UILabel *empty = [UILabel new];
        empty.text = queue ? @"Nothing up next" : @"NaviMus's queue shows once a song has started";
        empty.textColor = FZRSecondary();
        empty.textAlignment = NSTextAlignmentCenter;
        empty.numberOfLines = 0;
        empty.font = FZRFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
        empty;
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return (NSInteger)_sections.count; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return (NSInteger)[_sections[(NSUInteger)section][@"songs"] count]; }
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section { return 36; }
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    UILabel *title = [UILabel new];
    title.text = _sections[(NSUInteger)section][@"title"];
    title.font = FZRFont(UIFontTextStyleHeadline, UIFontWeightBold, UIContentSizeCategoryExtraLarge);
    title.textColor = FZRPrimary();
    UIView *header = [UIView new];
    [header addSubview:title];
    title.frame = CGRectMake(0, 8, table.bounds.size.width, 22);
    return header;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"song" forIndexPath:path];
    NSDictionary *song = _sections[(NSUInteger)path.section][@"songs"][(NSUInteger)path.row];
    UIListContentConfiguration *content = UIListContentConfiguration.subtitleCellConfiguration;
    content.text = string(song[@"title"]) ?: @"";
    content.secondaryText = string(song[@"artist"]);
    content.textProperties.font = FZRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    content.textProperties.color = FZRPrimary();
    content.textProperties.numberOfLines = 1;
    content.secondaryTextProperties.font = FZRFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    content.secondaryTextProperties.color = FZRSecondary();
    content.secondaryTextProperties.numberOfLines = 1;
    content.imageProperties.maximumSize = CGSizeMake(44, 44);
    content.imageProperties.reservedLayoutSize = CGSizeMake(44, 44);
    content.imageProperties.cornerRadius = 6;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 0, 8, 0);
    content.imageToTextPadding = 12;
    NSString *cover = string(song[@"coverArt"]);
    UIImage *image = cover ? [_covers objectForKey:cover] : nil;
    content.image = image ?: [UIImage systemImageNamed:@"music.note"];
    content.imageProperties.tintColor = FZRTertiary();
    cell.contentConfiguration = content;
    cell.backgroundColor = UIColor.clearColor;
    cell.preservesSuperviewLayoutMargins = NO;
    cell.layoutMargins = UIEdgeInsetsZero;
    cell.contentView.preservesSuperviewLayoutMargins = NO;
    cell.contentView.layoutMargins = UIEdgeInsetsZero;
    UIView *pressed = [UIView new];
    pressed.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    cell.selectedBackgroundView = pressed;
    if (cover && !image && FZServerReady()) {
        __weak typeof(self) weakSelf = self;
        FZServerImage(FZServerCoverURL(cover, 132), ^(UIImage *loaded) {
            if (!loaded || !weakSelf) return;
            [weakSelf.coverCache setObject:loaded forKey:cover];
            [weakSelf reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
        });
    }
    return cell;
}
- (NSCache<NSString *, UIImage *> *)coverCache { return _covers; }
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSUInteger steps = 1;
    for (NSInteger section = 0; section < path.section; section++) steps += [_sections[(NSUInteger)section][@"songs"] count];
    steps += (NSUInteger)path.row;
    FZLog("player: queue song %lu ahead", (unsigned long)steps);
    MPRemoteCommand *next = MPRemoteCommandCenter.sharedCommandCenter.nextTrackCommand;
    for (NSUInteger i = 0; i < steps; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ FZRemoteSend(next); });
    }
}
@end

#pragma mark - the player

NSString *const FZRKeyPlayerBackground = @"fz.redesign.player.backdrop";     // 0 fluid artwork (Kawarp), 1 blurred cover, 2 colours, 3 cover
NSString *const FZRKeyPlayerRightSlot = @"fz.redesign.player.rightSlot";     // right of next: 0 sleep timer, 1 repeat

// Measured on chroma.pw's player (the user's screenshot, 390 × 844): ⌄ and ⋯ in 44 pt glass circles centred 71 pt
// down, the album name between them; the cover 24 pt from the sides with its top 84 pt under the header's centre;
// the title Title 1 bold, the explicit badge and artist Body under it, + (download here) at the right; the 4 pt
// scrubber 62 pt over the controls; shuffle, previous, a bare 44 pt play/pause glyph, next and the sleep timer
// centred at 36, 112, 195, 278 and 354 pt; lyrics, AirPlay and queue at 20 %, 50 % and 80 % of the width, centred
// 22 pt above the 34 pt bottom inset.
static const CGFloat kCoverBelowHeader = 84, kControlsAboveFooter = 70, kTimesAboveControls = 62, kSkipOffset = 83;

@interface FZRPlayerViewController : UIViewController <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@end

@implementation FZRPlayerViewController {
    FZRArtworkField *_field;
    FZRKawarpView *_fluid;
    FZRRoundButton *_close, *_more;
    UILabel *_contextName;
    UIView *_plate;
    UIImageView *_cover;
    FZRLyricsView *_lyrics;
    FZRQueueView *_queueList;
    UILabel *_title, *_artist, *_explicitBadge;
    FZRRoundButton *_download;
    FZRScrubber *_scrubber;
    UILabel *_elapsed, *_remaining;
    FZRRoundButton *_shuffle, *_previous, *_next, *_play, *_slot;
    UIView *_shuffleDot;
    AVRoutePickerView *_route;
    FZRRoundButton *_lyricsButton, *_queue;
    NSTimer *_timer;
    NSString *_coverSong, *_downloadedSong;
    BOOL _lyricsOpen, _queueOpen, _shuffleOn;
    NSInteger _repeatMode;   // 0 off, 1 all, 2 one
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

// chroma.pw's player: Fluid artwork (its Kawarp field) behind everything; the redesign's other fields as options.
- (void)applyBackground {
    NSInteger kind = FZInt(FZRKeyPlayerBackground, 0);
    BOOL fluid = kind == 0 && _fluid.available;
    _fluid.hidden = !fluid;
    _field.hidden = fluid;
    _field.showsBackdrop = YES;
    _field.flows = kind == 2;
    _field.fluid = NO;
    _field.fills = kind == 3;
    if (fluid) FZRApplyFluidLook(_fluid);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    view.backgroundColor = FZRNeutralField();
    view.clipsToBounds = YES;
    _field = [[FZRArtworkField alloc] initWithFrame:view.bounds];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _field.bleed = UIEdgeInsetsMake(200, 0, 600, 0);
    [view addSubview:_field];
    _fluid = [[FZRKawarpView alloc] initWithFrame:view.bounds];
    _fluid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_fluid];
    [self applyBackground];

    _close = [self button:@"chevron.down" size:20 label:@"Close" action:@selector(closePlayer)];
    _close.circled = YES;
    _more = [self button:@"ellipsis" size:20 label:@"More" action:nil];
    _more.circled = YES;
    _contextName = [self label:UIFontTextStyleHeadline weight:UIFontWeightSemibold color:FZRPrimary()];
    _contextName.textAlignment = NSTextAlignmentCenter;

    // The shadow plate: a rounded rect under the cover carrying its shadow (shadow.artwork).
    _plate = [UIView new];
    _plate.layer.shadowColor = UIColor.blackColor.CGColor;
    _plate.layer.shadowOpacity = 0.45;
    _plate.layer.shadowRadius = 32;
    _plate.layer.shadowOffset = CGSizeMake(0, 12);
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
    _queueList = [FZRQueueView new];
    _queueList.alpha = 0;
    _queueList.hidden = YES;
    [view addSubview:_queueList];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(queueChanged) name:FZRQueueDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(queueChanged) name:FZNowPlayingDidChangeNotification object:nil];

    _title = [self label:UIFontTextStyleTitle1 weight:UIFontWeightBold color:FZRPrimary()];
    _artist = [self label:UIFontTextStyleBody weight:UIFontWeightRegular color:FZRSecondary()];
    // The explicit badge: a small rounded "E" in the secondary white before the artist.
    _explicitBadge = [self label:UIFontTextStyleCaption2 weight:UIFontWeightBold color:UIColor.blackColor];
    _explicitBadge.text = @"E";
    _explicitBadge.textAlignment = NSTextAlignmentCenter;
    _explicitBadge.backgroundColor = FZRTertiary();
    _explicitBadge.layer.cornerRadius = 3;
    _explicitBadge.layer.masksToBounds = YES;
    _download = [self button:@"arrow.down.circle" size:30 label:@"Download" action:@selector(download)];

    _scrubber = [FZRScrubber new];
    [_scrubber addTarget:self action:@selector(scrubbing) forControlEvents:UIControlEventValueChanged];
    [_scrubber addTarget:self action:@selector(scrubbed) forControlEvents:UIControlEventPrimaryActionTriggered];
    [view addSubview:_scrubber];
    _elapsed = [self label:UIFontTextStyleCaption1 weight:UIFontWeightMedium color:FZRSecondary()];
    _remaining = [self label:UIFontTextStyleCaption1 weight:UIFontWeightMedium color:FZRSecondary()];
    _elapsed.font = FZRMonospacedDigitsFont(_elapsed.font);
    _remaining.font = FZRMonospacedDigitsFont(_remaining.font);
    _remaining.textAlignment = NSTextAlignmentRight;

    _shuffle = [self button:@"shuffle" size:kSmallGlyph label:@"Shuffle" action:@selector(toggleShuffle)];
    _shuffleDot = [UIView new];
    _shuffleDot.backgroundColor = FZRAccent();
    _shuffleDot.layer.cornerRadius = 2;
    _shuffleDot.userInteractionEnabled = NO;
    [view addSubview:_shuffleDot];
    _previous = [self button:@"backward.fill" size:kSkipGlyph label:@"Previous" action:@selector(previous)];
    _play = [self button:@"play.fill" size:44 label:@"Play" action:@selector(playPause)];
    _next = [self button:@"forward.fill" size:kSkipGlyph label:@"Next" action:@selector(next)];
    _slot = [self button:@"timer" size:kSmallGlyph label:@"Sleep timer" action:nil];

    _lyricsButton = [self button:@"quote.bubble" size:kSmallGlyph label:@"Lyrics" action:@selector(toggleLyrics)];
    _route = [AVRoutePickerView new];
    _route.prioritizesVideoDevices = NO;
    [view addSubview:_route];
    _queue = [self button:@"list.bullet" size:kSmallGlyph label:@"Queue" action:@selector(openQueue)];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
    pan.delegate = self;
    [view addGestureRecognizer:pan];
    UITapGestureRecognizer *coverTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playPause)];
    coverTap.numberOfTapsRequired = 2;
    [_plate addGestureRecognizer:coverTap];
    // The thumbnail brings the cover back from the lyrics or the queue.
    UITapGestureRecognizer *thumbTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(thumbTapped)];
    [thumbTap requireGestureRecognizerToFail:coverTap];
    [_plate addGestureRecognizer:thumbTap];

    for (NSNotificationName name in @[FZNowPlayingDidChangeNotification, FZRSleepTimerDidChangeNotification, NSUserDefaultsDidChangeNotification, FZRFluidLookDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:name object:nil];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(routeChanged) name:AVAudioSessionRouteChangeNotification object:nil];
    [self refresh];
}

- (void)routeChanged { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; }); }

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

static BOOL externalRoute(void) {
    NSString *type = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject.portType;
    return type && ![type isEqualToString:AVAudioSessionPortBuiltInSpeaker] && ![type isEqualToString:AVAudioSessionPortBuiltInReceiver];
}

- (void)refresh {
    if (!self.isViewLoaded) return;
    NSDictionary *info = FZNowPlayingInfo();
    _title.text = string(info[MPMediaItemPropertyTitle]) ?: @"Not playing";
    _artist.text = string(info[MPMediaItemPropertyArtist]) ?: string(info[MPMediaItemPropertyAlbumArtist]) ?: @"";
    id explicitFlag = info[@"isExplicit"] ?: info[MPMediaItemPropertyIsExplicit];
    _explicitBadge.hidden = !([explicitFlag respondsToSelector:@selector(boolValue)] && [explicitFlag boolValue]);
    _contextName.text = string(info[MPMediaItemPropertyAlbumTitle]) ?: @"";
    _contextName.hidden = !FZEnabled(FZRKeyPlayerContext);
    [self applyBackground];

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
            [_fluid setImage:image animated:animated];
            _coverSong = song;
        }
        if (_lyricsOpen && ![_lyrics showSong:FZNowPlayingSongID()]) [self setLyricsOpen:NO];
    }

    BOOL playing = FZNowPlayingIsPlaying();
    [_play setSymbol:playing ? @"pause.fill" : @"play.fill"];
    _play.accessibilityLabel = playing ? @"Pause" : @"Play";
    _shuffle.glyph.tintColor = _shuffleOn ? FZRAccent() : FZRPrimary();
    _shuffleDot.hidden = !_shuffleOn || _shuffle.hidden;

    // Right of next: the sleep timer (chroma.pw's) or repeat.
    BOOL repeatSlot = FZInt(FZRKeyPlayerRightSlot, 0) == 1;
    [_slot removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
    if (repeatSlot) {
        [_slot setSymbol:_repeatMode == 2 ? @"repeat.1" : @"repeat"];
        _slot.glyph.tintColor = _repeatMode ? FZRAccent() : FZRPrimary();
        _slot.accessibilityLabel = @"Repeat";
        _slot.menu = nil;
        [_slot addTarget:self action:@selector(cycleRepeat) forControlEvents:UIControlEventTouchUpInside];
        _slot.hidden = !FZEnabled(FZRKeyPlayerRepeat);
    } else {
        [_slot setSymbol:@"timer"];
        _slot.glyph.tintColor = sSleepTimer ? FZRAccent() : FZRPrimary();
        _slot.accessibilityLabel = @"Sleep timer";
        _slot.menu = sleepMenu();
        _slot.hidden = !FZEnabled(FZRKeyPlayerSleep);
    }
    _lyricsButton.glyph.tintColor = _lyricsOpen ? FZRAccent() : FZRPrimary();
    _queue.glyph.tintColor = _queueOpen ? FZRAccent() : FZRPrimary();
    [_lyricsButton setSymbol:_lyricsOpen ? @"quote.bubble.fill" : @"quote.bubble"];
    _route.tintColor = externalRoute() ? FZRAccent() : FZRPrimary();
    _route.activeTintColor = FZRAccent();
    _more.menu = [self moreMenu];
    _close.circled = FZEnabled(FZRKeyCircleBack);
    _more.circled = FZEnabled(FZRKeyCircleMore);

    _download.hidden = !FZEnabled(FZRKeyPlayerDownload);
    _shuffle.hidden = !FZEnabled(FZRKeyPlayerShuffle);
    _shuffleDot.hidden = _shuffleDot.hidden || _shuffle.hidden;
    _route.hidden = !FZEnabled(FZRKeyPlayerAirPlay);
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

- (void)showPaused:(BOOL)paused animated:(BOOL)animated {
    CGFloat scale = paused && FZEnabled(FZRKeyPlayerShrink) && !_lyricsOpen && !_queueOpen ? (FZRReduceMotion() ? kPausedScaleReduced : kPausedScale) : 1;
    if (CGAffineTransformEqualToTransform(_plate.transform, CGAffineTransformMakeScale(scale, scale))) return;
    void (^change)(void) = ^{ self->_plate.transform = CGAffineTransformMakeScale(scale, scale); };
    if (animated) FZRAnimate(FZRMotionLayout, change, nil); else change();
}

#pragma mark layout

static void centre(UIView *view, CGFloat x, CGFloat y, CGFloat side) {
    view.frame = CGRectMake(round(x - side / 2), round(y - side / 2), side, side);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat width = b.size.width, side = kSide + MAX(safe.left, safe.right), inner = width - 2 * side;

    // Header: centred 71 pt down on an iPhone with a 47 pt top inset.
    CGFloat headerMid = safe.top + kHeaderTop + kCircle / 2 + 2;
    centre(_close, 16 + safe.left + kCircle / 2, headerMid, kCircle);
    centre(_more, width - 16 - safe.right - kCircle / 2, headerMid, kCircle);
    CGFloat contextX = CGRectGetMaxX(_close.frame) + 8;
    CGFloat nameH = ceil(_contextName.font.lineHeight);
    _contextName.frame = CGRectMake(contextX, round(headerMid - nameH / 2), CGRectGetMinX(_more.frame) - 8 - contextX, nameH);

    // From the bottom up: footer, controls, times and scrubber, title, then the cover in what's left.
    CGFloat footerMid = b.size.height - MAX(safe.bottom, kFooterMinBottom) - kCircle / 2;
    BOOL footer = !_route.hidden || !_lyricsButton.hidden || !_queue.hidden;
    centre(_lyricsButton, width * 0.2, footerMid, kCircle);
    centre(_route, width * 0.5, footerMid, kCircle);
    centre(_queue, width * 0.8, footerMid, kCircle);

    CGFloat controlsMid = footer ? footerMid - kControlsAboveFooter : footerMid;
    CGFloat mid = width / 2;
    centre(_play, mid, controlsMid, 72);
    centre(_previous, mid - kSkipOffset, controlsMid, 60);
    centre(_next, mid + kSkipOffset, controlsMid, 60);
    centre(_shuffle, side + 12, controlsMid, kCircle);
    centre(_slot, width - side - 12, controlsMid, kCircle);
    _shuffleDot.frame = CGRectMake(round(_shuffle.center.x - 2), round(controlsMid + 16), 4, 4);

    CGFloat timesMid = controlsMid - kTimesAboveControls;
    CGFloat timesH = ceil(_elapsed.font.lineHeight);
    _elapsed.frame = CGRectMake(side, round(timesMid - timesH / 2), inner / 2, timesH);
    _remaining.frame = CGRectMake(side + inner / 2, round(timesMid - timesH / 2), inner / 2, timesH);
    CGFloat scrubMid = timesMid - 15;
    _scrubber.frame = CGRectMake(side, round(scrubMid - 14), inner, 28);

    CGFloat titleH = ceil(_title.font.lineHeight), artistH = ceil(_artist.font.lineHeight);
    CGFloat artistY = round(scrubMid - 26 - artistH);
    CGFloat titleY = artistY - titleH;
    CGFloat textW = inner - (_download.hidden ? 0 : kCircle + 8);
    _title.frame = CGRectMake(side, titleY, textW, titleH);
    CGFloat badge = _explicitBadge.hidden ? 0 : 16;
    _explicitBadge.frame = CGRectMake(side, round(artistY + (artistH - badge) / 2), badge, badge);
    CGFloat artistX = side + (badge ? badge + 8 : 0);
    _artist.frame = CGRectMake(artistX, artistY, textW - (artistX - side), artistH);
    centre(_download, width - side - kCircle / 2 + 6, titleY + (titleH + artistH) / 2, kCircle);

    // The cover: the full width between the margins with its top 84 pt under the header's centre, smaller only if
    // the title would meet it.
    CGFloat top = headerMid + kCoverBelowHeader, bottom = titleY - 24;
    CGFloat coverSide = MAX(0, MIN(inner, bottom - top));
    CGRect cover = CGRectMake(round((width - coverSide) / 2), top, coverSide, coverSide);
    CGRect content = CGRectMake(side, headerMid + kCircle / 2 + 12, inner, bottom - (headerMid + kCircle / 2 + 12));
    if (_lyricsOpen || _queueOpen) {
        // Lyrics or the queue (taurus PlayerLyrics.x: a 72 pt thumbnail 8 pt under the band's top, the title 16 pt
        // beside it, 12 pt clear of the trailing controls, the lines 20 pt under the row and 8 pt above the bar).
        CGRect thumb = CGRectMake(side, headerMid + kCircle / 2 + 8, kThumbSide, kThumbSide);
        cover = thumb;
        CGFloat textX = CGRectGetMaxX(thumb) + kThumbGap;
        CGFloat trailing = _download.hidden ? 0 : kCircle + kTitleGap;
        CGFloat rowTextW = width - side - trailing - textX;
        CGFloat rowY = round(CGRectGetMidY(thumb) - (titleH + artistH) / 2);
        _title.frame = CGRectMake(textX, rowY, rowTextW, titleH);
        _explicitBadge.frame = CGRectMake(textX, round(rowY + titleH + (artistH - badge) / 2), badge, badge);
        CGFloat rowArtistX = textX + (badge ? badge + 8 : 0);
        _artist.frame = CGRectMake(rowArtistX, rowY + titleH, rowTextW - (rowArtistX - textX), artistH);
        centre(_download, width - side - kCircle / 2 + 6, CGRectGetMidY(thumb), kCircle);
        CGFloat contentTop = CGRectGetMaxY(thumb) + kLyricsTop;
        content = CGRectMake(side, contentTop, inner, CGRectGetMinY(_scrubber.frame) - kLyricsBottom - contentTop);
    }
    CGAffineTransform transform = _plate.transform;
    _plate.transform = CGAffineTransformIdentity;
    _plate.frame = cover;
    _plate.transform = transform;
    _cover.frame = _plate.bounds;
    CGFloat radius = (_lyricsOpen || _queueOpen) ? FZRRadiusThumb : FZRRadiusArtwork;
    _cover.layer.cornerRadius = radius;
    _plate.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_plate.bounds cornerRadius:radius].CGPath;
    _lyrics.frame = content;
    _queueList.frame = content;
}

#pragma mark actions

- (void)closePlayer { [self dismissViewControllerAnimated:YES completion:nil]; }

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

// Cover, lyrics or queue: the cover moves into the thumbnail and back on the layout spring, the title with it, and
// the lines or the list come up from just under full size (taurus PlayerLyrics.x: in 0.30 s after 0.12 s, out 0.16 s).
- (void)setLyricsOpen:(BOOL)lyrics queueOpen:(BOOL)queue {
    BOOL wasCompact = _lyricsOpen || _queueOpen;
    _lyricsOpen = lyrics;
    _queueOpen = queue;
    BOOL compact = lyrics || queue;
    if (queue) [_queueList reload];
    UIFont *titleFont = FZRFont(compact ? UIFontTextStyleTitle3 : UIFontTextStyleTitle1, UIFontWeightBold, UIContentSizeCategoryExtraExtraLarge);
    if (compact != wasCompact) {
        [UIView transitionWithView:_title duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{ self->_title.font = titleFont; } completion:nil];
    }
    [self showPaused:NO animated:YES];
    FZRAnimateLayout(self.view, ^{ [self.view setNeedsLayout]; }, nil);
    for (UIView *panel in @[_lyrics, _queueList]) {
        BOOL shown = (panel == _lyrics && lyrics) || (panel == _queueList && queue);
        if (shown) {
            panel.hidden = NO;
            panel.transform = CGAffineTransformMakeScale(0.96, 0.96);
            [UIView animateWithDuration:0.3 delay:0.12 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                panel.alpha = 1;
                panel.transform = CGAffineTransformIdentity;
            } completion:nil];
        } else if (!panel.hidden) {
            [UIView animateWithDuration:0.16 animations:^{ panel.alpha = 0; } completion:^(BOOL finished) {
                if (panel.alpha < 0.01) panel.hidden = YES;
            }];
        }
    }
    [self refresh];
}

- (void)setLyricsOpen:(BOOL)open { [self setLyricsOpen:open queueOpen:NO]; }

- (void)thumbTapped {
    if (_lyricsOpen || _queueOpen) [self setLyricsOpen:NO queueOpen:NO];
}

- (void)queueChanged { if (_queueOpen) [_queueList reload]; }

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

// NaviMus's queue, in Frozio's player (as NaviMus's player shows it: the cover up top, the list above the bar).
- (void)openQueue { [self setLyricsOpen:NO queueOpen:!_queueOpen]; }

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

#pragma mark the ⋯ menu

// NaviMus's own player does what Frozio's can't reach on its own (a song's playlist and queue): its menu item is
// pressed out of sight, as for download.
- (void)naviMusSongAction:(NSArray<NSString *> *)labels what:(NSString *)what dismissFirst:(BOOL)dismissFirst {
    void (^run)(void) = ^{
        FZRNaviMusPlayerAction(FZRPlayerTabs(), FZRPlayerMiniBar(), labels, ^(BOOL ok, NSString *why) {
            FZLog("player: %@ → %d%@", what, ok, why ? [@" " stringByAppendingString:why] : @"");
            if (ok) return;
            UIViewController *top = FZRPlayerTabs().view.window.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Couldn't %@", what.lowercaseString]
                                                                           message:why preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [top presentViewController:alert animated:YES completion:nil];
        });
    };
    // NaviMus's playlist picker is a sheet it presents itself, which it can't while Frozio's player is up.
    if (dismissFirst) [self dismissViewControllerAnimated:YES completion:run]; else run();
}

- (void)share {
    NSDictionary *info = FZNowPlayingInfo();
    NSString *title = string(info[MPMediaItemPropertyTitle]) ?: @"";
    NSString *artist = string(info[MPMediaItemPropertyArtist]);
    NSMutableArray *items = [NSMutableArray arrayWithObject:artist ? [NSString stringWithFormat:@"%@ – %@", title, artist] : title];
    UIImage *cover = FZNowPlayingArtwork(CGSizeMake(600, 600));
    if (cover) [items addObject:cover];
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = _more;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)love {
    FZRNaviMusPerform(@"LikeSongIntent", ^(BOOL ok, NSString *why) {
        FZLog("player: love → %d%@", ok, why ? [@" " stringByAppendingString:why] : @"");
        if (ok) [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    });
}

static UIAction *comingAction(NSString *title, NSString *symbol, NSString *subtitle) {
    UIAction *action = [UIAction actionWithTitle:title image:[UIImage systemImageNamed:symbol] identifier:nil handler:^(UIAction *a) {}];
    action.subtitle = subtitle ?: @"Coming in a later Frozio build";
    action.attributes = UIMenuElementAttributesDisabled;
    return action;
}

// NaviMus's playback speed through its own rate handler, when it has one.
- (UIMenuElement *)speedMenu {
    MPRemoteCommand *rate = MPRemoteCommandCenter.sharedCommandCenter.changePlaybackRateCommand;
    if (!FZRemoteHandles(rate)) return comingAction(@"Speed, pitch and reverb", @"slider.horizontal.3", @"NaviMus doesn't take speed from outside yet");
    NSNumber *now = FZNowPlayingInfo()[MPNowPlayingInfoPropertyDefaultPlaybackRate] ?: @1;
    NSMutableArray *rates = [NSMutableArray array];
    for (NSNumber *value in @[@0.5, @0.75, @1, @1.25, @1.5, @2]) {
        UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"%g×", value.doubleValue] image:nil identifier:nil handler:^(UIAction *a) {
            BOOL ok = FZRemoteSendWithOptions(rate, @{@"kMRMediaRemoteOptionPlaybackRate": value});
            FZLog("player: speed %@ → %d", value, ok);
        }];
        action.state = fabs(now.doubleValue - value.doubleValue) < 0.01 ? UIMenuElementStateOn : UIMenuElementStateOff;
        [rates addObject:action];
    }
    UIMenu *menu = [UIMenu menuWithTitle:@"Speed, pitch and reverb" image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil options:0 children:rates];
    menu.subtitle = [NSString stringWithFormat:@"%g×", now.doubleValue];
    return menu;
}

// chroma.pw's player menu, top to bottom (the user's screenshot): Add to playlist, Add to Queue and Share in a row;
// Speed, pitch and reverb; AutoMix; Music Haptics; Artwork; Lyrics; Exclude track from your taste profile (here
// NaviMus's Love, its counterpart); More. What Frozio can't do yet is there, greyed, until it lands.
- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    UIAction *playlist = [UIAction actionWithTitle:@"Add to playlist" image:[UIImage systemImageNamed:@"text.badge.plus"] identifier:nil handler:^(UIAction *a) {
        [weakSelf naviMusSongAction:@[@"Add to Playlist", @"Add to playlist", @"Add to a Playlist"] what:@"Add to playlist" dismissFirst:YES];
    }];
    UIAction *queue = [UIAction actionWithTitle:@"Add to Queue" image:[UIImage systemImageNamed:@"text.line.last.and.arrowtriangle.forward"] identifier:nil handler:^(UIAction *a) {
        [weakSelf naviMusSongAction:@[@"Add to Queue", @"Play Last", @"Queue"] what:@"Add to Queue" dismissFirst:NO];
    }];
    UIAction *share = [UIAction actionWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a) { [weakSelf share]; }];
    UIMenu *top = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[playlist, queue, share]];
    if (@available(iOS 16.0, *)) top.preferredElementSize = UIMenuElementSizeMedium;

    UIAction *noMix = [UIAction actionWithTitle:@"None" image:nil identifier:nil handler:^(UIAction *a) {}];
    noMix.state = UIMenuElementStateOn;
    UIMenu *automix = [UIMenu menuWithTitle:@"AutoMix" image:[UIImage systemImageNamed:@"arrow.triangle.merge"] identifier:nil options:0
                                   children:@[noMix, comingAction(@"AutoMix", nil, nil), comingAction(@"Crossfade", nil, nil)]];
    automix.subtitle = @"None";
    UIAction *haptics = comingAction(@"Music Haptics", @"iphone.radiowaves.left.and.right", @"Needs iOS 18 and Apple Music's tracks");

    UIAction *coverArt = [UIAction actionWithTitle:@"Cover Art" image:[UIImage systemImageNamed:@"photo"] identifier:nil handler:^(UIAction *a) {}];
    coverArt.state = UIMenuElementStateOn;
    UIMenu *visualizer = [UIMenu menuWithTitle:@"Visualizer" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        comingAction(@"Shuffle Shaders", @"shuffle", nil), comingAction(@"Bars", nil, nil), comingAction(@"Nebula", nil, nil),
        comingAction(@"Halo", nil, nil), comingAction(@"Poster", nil, nil), comingAction(@"Cut", nil, nil)]];
    UIMenu *artwork = [UIMenu menuWithTitle:@"Artwork" image:[UIImage systemImageNamed:@"dot.circle.viewfinder"] identifier:nil options:0 children:@[
        coverArt, comingAction(@"Animated", @"livephoto", nil), comingAction(@"Visualizer", @"waveform", nil), comingAction(@"Auto", @"wand.and.stars", nil),
        visualizer]];
    artwork.subtitle = @"Cover Art";

    UIAction *lyricsDefault = [UIAction actionWithTitle:@"Default" image:nil identifier:nil handler:^(UIAction *a) { [weakSelf toggleLyrics]; }];
    lyricsDefault.state = UIMenuElementStateOn;
    UIMenu *lyrics = [UIMenu menuWithTitle:@"Lyrics" image:[UIImage systemImageNamed:@"quote.bubble"] identifier:nil options:0
                                  children:@[lyricsDefault, comingAction(@"Lyrics shaders", nil, nil)]];
    lyrics.subtitle = @"Default";
    UIMenu *features = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline
                                    children:@[[self speedMenu], automix, haptics, artwork, lyrics]];

    UIAction *love = [UIAction actionWithTitle:@"Love" image:[UIImage systemImageNamed:@"heart"] identifier:nil handler:^(UIAction *a) { [weakSelf love]; }];
    NSArray *repeatNames = @[@"Repeat: Off", @"Repeat: All", @"Repeat: One"];
    UIMenu *more = [UIMenu menuWithTitle:@"More" image:[UIImage systemImageNamed:@"ellipsis.circle"] identifier:nil options:0 children:@[
        [UIAction actionWithTitle:@"Download" image:[UIImage systemImageNamed:@"arrow.down.circle"] identifier:nil handler:^(UIAction *a) { [weakSelf download]; }],
        sleepMenu(),
        [UIAction actionWithTitle:repeatNames[(NSUInteger)_repeatMode] image:[UIImage systemImageNamed:_repeatMode == 2 ? @"repeat.1" : @"repeat"]
                       identifier:nil handler:^(UIAction *a) { [weakSelf cycleRepeat]; }],
        [UIAction actionWithTitle:@"Queue and more in NaviMus's player" image:[UIImage systemImageNamed:@"list.bullet"] identifier:nil
                          handler:^(UIAction *a) { [weakSelf openNaviMusPlayer]; }],
    ]];
    UIMenu *last = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[love, more]];
    return [UIMenu menuWithTitle:@"" children:@[top, features, last]];
}

#pragma mark swipe down to close

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (![gesture isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:self.view];
    CGPoint start = [gesture locationInView:self.view];
    // Down and not on the scrubber or in scrolled lyrics.
    if (CGRectContainsPoint(CGRectInset(_scrubber.frame, 0, -10), start)) return NO;
    if (_lyricsOpen && CGRectContainsPoint(_lyrics.frame, start) && _lyrics.contentOffset.y > 1) return NO;
    if (_queueOpen && CGRectContainsPoint(_queueList.frame, start) && _queueList.contentOffset.y > 1) return NO;
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
    FZModRow *miniRound = FZWithSymbol(FZSwitchRow(@"Round cover", nil, @"fz.redesign.mini.roundArtwork"), @"circle");
    FZModRow *miniSwipe = FZWithSymbol(FZSwitchRow(@"Swipe to change song", nil, @"fz.redesign.mini.swipe"), @"hand.draw");

    FZModRow *context = FZWithSymbol(FZSwitchRow(@"Album name at the top", nil, FZRKeyPlayerContext), @"text.alignleft");
    FZModRow *background = FZWithSymbol(FZChoiceRow(@"Background", @"chroma.pw's is Fluid artwork.", FZRKeyPlayerBackground, @[@"Fluid artwork", @"Blurred cover", @"Colours", @"Cover"], 0), @"photo");
    FZModRow *fluidLook = FZWithSymbol(FZPageRow(@"Fluid artwork", ^UIViewController *{ return FZRFluidOptionsPage(); }), @"drop");
    fluidLook.subtitle = @"Preset, speed, warp, grain, blur, saturation, brightness.";
    FZModRow *slot = FZWithSymbol(FZChoiceRow(@"Right of next", @"chroma.pw has the sleep timer there.", FZRKeyPlayerRightSlot, @[@"Sleep timer", @"Repeat"], 0), @"timer");
    FZModRow *download = FZWithSymbol(FZSwitchRow(@"Download", @"In place of chroma.pw's +.", FZRKeyPlayerDownload), @"arrow.down.circle");
    FZModRow *shuffle = FZWithSymbol(FZSwitchRow(@"Shuffle", nil, FZRKeyPlayerShuffle), @"shuffle");
    FZModRow *repeat = FZWithSymbol(FZSwitchRow(@"Repeat", nil, FZRKeyPlayerRepeat), @"repeat");
    FZModRow *times = FZWithSymbol(FZSwitchRow(@"Elapsed and remaining", nil, FZRKeyPlayerTimes), @"clock");
    FZModRow *airPlay = FZWithSymbol(FZSwitchRow(@"AirPlay", nil, FZRKeyPlayerAirPlay), @"airplayaudio");
    FZModRow *sleep = FZWithSymbol(FZSwitchRow(@"Sleep timer", nil, FZRKeyPlayerSleep), @"moon.zzz");
    FZModRow *lyrics = FZWithSymbol(FZSwitchRow(@"Lyrics", nil, FZRKeyPlayerLyrics), @"quote.bubble");
    FZModRow *queue = FZWithSymbol(FZSwitchRow(@"Queue", @"NaviMus's queue, in this player.", FZRKeyPlayerQueue), @"list.bullet");
    FZModRow *more = FZWithSymbol(FZSwitchRow(@"⋯ menu", nil, FZRKeyPlayerMore), @"ellipsis.circle");
    FZModRow *shrink = FZWithSymbol(FZSwitchRow(@"Smaller cover while paused", nil, FZRKeyPlayerShrink), @"arrow.down.right.and.arrow.up.left");
    return @[
        FZNotedSection(@"Rebuilt player", @[rebuilt], @"Applies right away."),
        FZSection(@"Mini player", @[miniPlay, miniPrevious, miniNext, miniAirPlay, miniDownload, miniProgress, miniRound, miniSwipe]),
        FZSection(@"Player", @[background, fluidLook, slot, context, download, shuffle, repeat, times, airPlay, sleep, lyrics, queue, more, shrink]),
    ];
}
