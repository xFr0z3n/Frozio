// Adapted from taurus/tweak/Sources/Shared/LockScreenLyrics/LockScreenLyrics.x @ fe3211c (GPL-3.0).
// Renamed SG→FZ; Logos replaced by FZHook; Spotify's karaoke player and word timings replaced by
// NaviMus's saved line timings (FZNaviMusLyrics), with long lines split by estimated time.
//
// The timer follows the playback rate rather than running from launch: a paused player's line does not
// move, so working it out four times a second only wakes the phone. The lock screen keeps the line it
// was left on until the sound starts again.
#import <MediaPlayer/MediaPlayer.h>
#import "Lyrics/FZLockScreenLyrics.h"
#import "Lyrics/FZNaviMusLyrics.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import "Prefs/FZSettings.h"

static const NSTimeInterval kTick = 0.25;
// The artist comes back this long into a line whose next one is still far off (an instrumental break),
// and this long into the last line.
static const NSInteger kBreakMs = 8000;
// About what the lock screen's artist row fits before it cuts the text off.
static const NSUInteger kMaxChars = 30;

static IMP fz_origSetInfo;
static IMP fz_origGetInfo;

// NaviMus may set the info from any thread; the timer reads it on the main one.
static NSObject *fz_lock;
static NSDictionary *fz_naviMusInfo;
static CFAbsoluteTime fz_naviMusInfoAt;
static NSString *fz_shownLine;
static BOOL fz_resending;
static dispatch_source_t fz_timer;
static void setTicking(BOOL on);

static BOOL lockScreenLyricsOn(void) {
    return [[FZSettings defaults] boolForKey:FZSettingsKeyLockScreenLyrics];
}

static void sendInfo(NSDictionary *info) {
    fz_resending = YES;
    ((void (*)(id, SEL, NSDictionary *))fz_origSetInfo)(MPNowPlayingInfoCenter.defaultCenter, @selector(setNowPlayingInfo:), info);
    fz_resending = NO;
}

// A line longer than the artist row holds, split into even pieces rather than a full one and a stub.
// NaviMus keeps no word timings, so each piece shows from its share of the line's time, by characters.
static NSString *pieceAt(NSString *text, NSInteger start, NSInteger end, NSInteger position) {
    if (text.length <= kMaxChars) return text;
    NSArray<NSString *> *words = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSUInteger count = MAX((text.length + kMaxChars - 1) / kMaxChars, 1);
    NSUInteger target = (text.length + count - 1) / count;
    NSMutableArray<NSString *> *pieces = [NSMutableArray array];
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray array];   // characters before each piece
    NSMutableString *piece = [NSMutableString string];
    NSUInteger before = 0;
    for (NSString *word in words) {
        if (!word.length) continue;
        NSUInteger withWord = piece.length ? piece.length + 1 + word.length : word.length;
        if (piece.length && (withWord > kMaxChars || (withWord > target && pieces.count + 1 < count))) {
            [pieces addObject:[piece copy]];
            [offsets addObject:@(before)];
            before += piece.length + 1;
            [piece setString:@""];
        }
        if (piece.length) [piece appendString:@" "];
        [piece appendString:word];
    }
    if (piece.length) {
        [pieces addObject:[piece copy]];
        [offsets addObject:@(before)];
    }
    NSString *shown = pieces.firstObject;
    for (NSUInteger i = 0; i < pieces.count; i++) {
        NSInteger from = start + (NSInteger)((double)(end - start) * offsets[i].doubleValue / text.length);
        if (from <= position) shown = pieces[i];
    }
    return shown;
}

// Seconds into the track at `now`, run on from what NaviMus last reported. A rate it left out runs at 1.
static double elapsedAt(NSDictionary *info, CFAbsoluteTime reportedAt, CFAbsoluteTime now) {
    NSNumber *reported = info[MPNowPlayingInfoPropertyPlaybackRate];
    double rate = reported ? reported.doubleValue : 1;
    return [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue] + rate * (now - reportedAt);
}

// nil between lines, in a long break and for a song without saved synced lyrics.
static NSString *lineFor(NSDictionary *info, double elapsed) {
    id songID = info[MPNowPlayingInfoPropertyExternalContentIdentifier];
    if (![songID isKindOfClass:NSString.class]) return nil;
    FZSyncedLyrics *lyrics = FZNaviMusSyncedLyrics(songID);
    if (!lyrics) return nil;
    // OpenSubsonic: a positive offset shows the lyrics sooner.
    NSInteger position = (NSInteger)(elapsed * 1000) + lyrics.offset;
    NSArray<FZLyricLine *> *lines = lyrics.lines;
    NSInteger index = -1;
    for (NSInteger i = 0; i < (NSInteger)lines.count && lines[i].start <= position; i++) index = i;
    if (index < 0 || !lines[index].text.length) return nil;
    FZLyricLine *line = lines[index];
    NSInteger next = index + 1 < (NSInteger)lines.count ? lines[index + 1].start : NSIntegerMax;
    NSInteger end = MIN(next, line.start + kBreakMs);
    if (position >= end) return nil;
    return pieceAt(line.text, line.start, end, position);
}

// NaviMus's info with the line in place of the artist, or its own artist for nil. The clock always moves
// on to `elapsed`: the system takes the elapsed time as now's, so the one NaviMus reported a while ago
// would pull the progress bar back.
static NSDictionary *withLine(NSDictionary *info, NSString *line, double elapsed) {
    NSMutableDictionary *shown = [info mutableCopy];
    if (line) shown[MPMediaItemPropertyArtist] = line;
    shown[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
    return shown;
}

static void tick(void) {
    if (!lockScreenLyricsOn()) {
        fz_shownLine = nil;
        setTicking(NO);
        return;
    }
    NSDictionary *info;
    CFAbsoluteTime reportedAt;
    @synchronized (fz_lock) {
        info = fz_naviMusInfo;
        reportedAt = fz_naviMusInfoAt;
    }
    if (!info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) return;
    double elapsed = elapsedAt(info, reportedAt, CFAbsoluteTimeGetCurrent());
    NSString *line = lineFor(info, elapsed);
    if (line == fz_shownLine || [line isEqualToString:fz_shownLine]) return;
    fz_shownLine = line;
#ifdef FROZIO_HARNESS
    FZLog("lock screen lyrics: at %.1f s → %@", elapsed, line ?: @"(artist)");
#else
    FZLog("lock screen lyrics: at %.1f s → %@", elapsed, line ? [NSString stringWithFormat:@"a line (%lu chars)", (unsigned long)line.length] : @"(artist)");
#endif
    sendInfo(withLine(info, line, elapsed));
}

// Main thread, as everything the timer touches is.
static void setTicking(BOOL on) {
    if (on == (fz_timer != nil)) return;
    if (!on) {
        dispatch_source_cancel(fz_timer);
        fz_timer = nil;
        return;
    }
    // A strict GCD timer: the main run loop's timers are throttled while the screen is off, and the
    // lines would stand still on a locked phone.
    fz_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_main_queue());
    uint64_t every = (uint64_t)(kTick * NSEC_PER_SEC);
    dispatch_source_set_timer(fz_timer, dispatch_time(DISPATCH_TIME_NOW, every), every, 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(fz_timer, ^{ tick(); });
    dispatch_resume(fz_timer);
}

// Whether the sound is moving. A rate NaviMus did not report at all counts as moving.
static BOOL playingBy(NSDictionary *info) {
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    return !rate || rate.doubleValue > 0;
}

static void refresh(void) {
    NSDictionary *info;
    CFAbsoluteTime reportedAt;
    @synchronized (fz_lock) {
        info = fz_naviMusInfo;
        reportedAt = fz_naviMusInfoAt;
    }
    BOOL enabled = lockScreenLyricsOn();
    BOOL playing = info && playingBy(info) && info[MPNowPlayingInfoPropertyElapsedPlaybackTime] != nil;
    setTicking(enabled && playing);
    if (!enabled) {
        // Switched off: put NaviMus's own artist back now rather than at the next song.
        if (fz_shownLine && info) sendInfo(withLine(info, nil, elapsedAt(info, reportedAt, CFAbsoluteTimeGetCurrent())));
        fz_shownLine = nil;
    } else if (playing) {
        tick();
    }
}

static void fz_setNowPlayingInfo(id self, SEL _cmd, NSDictionary *info) {
    void (*orig)(id, SEL, NSDictionary *) = (void (*)(id, SEL, NSDictionary *))fz_origSetInfo;
    if (fz_resending) {
        orig(self, _cmd, info);
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized (fz_lock) {
        fz_naviMusInfo = info;
        fz_naviMusInfoAt = now;
    }
    BOOL playing = info && playingBy(info) && info[MPNowPlayingInfoPropertyElapsedPlaybackTime] != nil;
    // The lyrics index and the timer are main-thread state; off it the info goes out as it is and the
    // next tick adds the line.
    if (!lockScreenLyricsOn() || !NSThread.isMainThread || !info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
        BOOL on = lockScreenLyricsOn();
        dispatch_block_t update = ^{
            fz_shownLine = nil;
            setTicking(on && playing);
        };
        if (NSThread.isMainThread) update();
        else dispatch_async(dispatch_get_main_queue(), update);
        orig(self, _cmd, info);
        return;
    }
    setTicking(playing);
    double elapsed = elapsedAt(info, now, now);
    NSString *line = lineFor(info, elapsed);
    fz_shownLine = line;
    orig(self, _cmd, withLine(info, line, elapsed));
}

static NSDictionary *fz_nowPlayingInfo(id self, SEL _cmd) {
    NSDictionary *info;
    @synchronized (fz_lock) {
        info = fz_naviMusInfo;
    }
    return info ?: ((NSDictionary *(*)(id, SEL))fz_origGetInfo)(self, _cmd);
}

void FZInstallLockScreenLyrics(void) {
    fz_lock = [NSObject new];
    // Public MediaPlayer API (iOS 5+), not a NaviMus symbol.
    BOOL set = FZHookInstanceMethodNamed(@"MPNowPlayingInfoCenter", @"setNowPlayingInfo:", "v@:@",
                                         (IMP)fz_setNowPlayingInfo, &fz_origSetInfo, "lockscreen-lyrics.set");
    BOOL get = set && FZHookInstanceMethodNamed(@"MPNowPlayingInfoCenter", @"nowPlayingInfo", "@@:",
                                                (IMP)fz_nowPlayingInfo, &fz_origGetInfo, "lockscreen-lyrics.get");
    if (!set || !get) {
        // Without the getter NaviMus would read the swapped artist back, so the setter goes too.
        if (set) {
            Method m = class_getInstanceMethod(NSClassFromString(@"MPNowPlayingInfoCenter"), @selector(setNowPlayingInfo:));
            if (m) method_setImplementation(m, fz_origSetInfo);
        }
        FZLogError("lock screen lyrics: hooks incomplete (set=%d get=%d); NaviMus's info goes out untouched", set, get);
        return;
    }
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ refresh(); });
    }];
    FZLog("lock screen lyrics installed (%@)", lockScreenLyricsOn() ? @"on" : @"off");
}
