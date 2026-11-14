// Adapted from taurus/tweak/Sources/Shared/ArtistBlock/ArtistSkip.x and ArtistBlock.m @ fe3211c (GPL-3.0).
// Renamed SG→FZ; Logos replaced by FZHook; Spotify's player, URIs and skip controller replaced by
// NaviMus's Now Playing info and its own nextTrackCommand handler.
#import <MediaPlayer/MediaPlayer.h>
#import "ArtistBlock/FZArtistBlock.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"
#import "Prefs/FZSettings.h"
#import "Settings/Kit/FZKitCore.h"

NSString *const FZKeyArtistBlock = @"fz.artistBlock";
NSString *const FZKeyArtistBlockFeatured = @"fz.artistBlock.featured";
NSString *const FZKeyArtistBlockList = @"fz.artistBlock.list";

// A queue of nothing but blocked songs would otherwise skip forever.
static const NSUInteger kMaxSkipsInARow = 25;

#pragma mark - store

NSArray<NSString *> *FZBlockedArtists(void) {
    NSArray *list = [[FZSettings defaults] arrayForKey:FZKeyArtistBlockList];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id name in list) if ([name isKindOfClass:NSString.class] && [name length]) [names addObject:name];
    return names;
}

static BOOL sameName(NSString *a, NSString *b) {
    return [a compare:b options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch] == NSOrderedSame;
}

BOOL FZArtistBlocked(NSString *name) {
    if (!name.length) return NO;
    for (NSString *blocked in FZBlockedArtists()) if (sameName(blocked, name)) return YES;
    return NO;
}

void FZBlockArtist(NSString *name) {
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || FZArtistBlocked(name)) return;
    NSMutableArray *list = [FZBlockedArtists() mutableCopy];
    [list addObject:name];
    [list sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [[FZSettings defaults] setObject:list forKey:FZKeyArtistBlockList];
    FZLog("artist block: blocked one more (%lu in all)", (unsigned long)list.count);
}

void FZUnblockArtist(NSString *name) {
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *blocked in FZBlockedArtists()) if (!sameName(blocked, name)) [list addObject:blocked];
    [[FZSettings defaults] setObject:list forKey:FZKeyArtistBlockList];
}

NSArray<NSString *> *FZArtistsInCredit(NSString *credit) {
    credit = [credit stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!credit.length) return @[];
    static NSRegularExpression *separators;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        separators = [NSRegularExpression regularExpressionWithPattern:@"\\s*(?:,|;|&|/|\\bfeat\\.?|\\bft\\.?|\\bfeaturing\\b)\\s*"
                                                               options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    __block NSUInteger from = 0;
    void (^take)(NSUInteger) = ^(NSUInteger to) {
        NSString *name = [[credit substringWithRange:NSMakeRange(from, to - from)]
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length) [names addObject:name];
    };
    for (NSTextCheckingResult *match in [separators matchesInString:credit options:0 range:NSMakeRange(0, credit.length)]) {
        take(match.range.location);
        from = NSMaxRange(match.range);
    }
    take(credit.length);
    return names.count ? names : @[credit];
}

// The whole credit, or its main name, or (with Featured on) any name in it.
static NSString *blockedNameIn(NSString *credit) {
    if (FZArtistBlocked(credit)) return credit;
    NSArray<NSString *> *names = FZArtistsInCredit(credit);
    BOOL featured = FZHidden(FZKeyArtistBlockFeatured);
    for (NSUInteger i = 0; i < names.count && (i == 0 || featured); i++) {
        if (FZArtistBlocked(names[i])) return names[i];
    }
    return nil;
}

#pragma mark - skip

static IMP fz_origAddTarget;
static IMP fz_origSetInfo;
static MPRemoteCommandHandlerStatus (^fz_naviMusNext)(MPRemoteCommandEvent *);
static NSDictionary *fz_lastInfo;          // main thread
static NSString *fz_lastSongID;            // main thread: the song already looked at while playing
static NSUInteger fz_skipsInARow;          // main thread

NSString *FZPlayingArtistCredit(void) {
    id credit = fz_lastInfo[MPMediaItemPropertyArtist];
    return [credit isKindOfClass:NSString.class] && [credit length] ? credit : nil;
}

static id fz_addTargetWithHandler(MPRemoteCommand *self, SEL _cmd, MPRemoteCommandHandlerStatus (^handler)(MPRemoteCommandEvent *)) {
    id target = ((id (*)(id, SEL, id))fz_origAddTarget)(self, _cmd, handler);
    if (handler && self == MPRemoteCommandCenter.sharedCommandCenter.nextTrackCommand) {
        fz_naviMusNext = [handler copy];
        FZLog("artist block: NaviMus's next-track handler seen");
    }
    return target;
}

// NaviMus's handler is called with an event like the one the system sends for the lock screen's Next
// button. MPRemoteCommandEvent's -init aborts, so the event comes from its factory
// +eventWithCommand:mediaRemoteType:options: (private; present in iOS 26.5's MediaPlayer, checked at
// run time with its exact types), typed by the command's own -mediaRemoteCommandType.
static MPRemoteCommandEvent *nextTrackEvent(void) {
    MPRemoteCommand *command = MPRemoteCommandCenter.sharedCommandCenter.nextTrackCommand;
    Class eventClass = NSClassFromString(@"MPRemoteCommandEvent");
    SEL make = NSSelectorFromString(@"eventWithCommand:mediaRemoteType:options:");
    SEL typeOf = NSSelectorFromString(@"mediaRemoteCommandType");
    Method factory = eventClass ? class_getClassMethod(eventClass, make) : NULL;
    Method type = command ? class_getInstanceMethod(object_getClass(command), typeOf) : NULL;
    if (!factory || !type || !FZTypesMatchNoDigits(method_getTypeEncoding(factory), "@@:@I@")
        || !FZTypesMatchNoDigits(method_getTypeEncoding(type), "I@:")) {
        FZLogError("artist block: no way to make a next-track event here (factory=%d type=%d)", factory != NULL, type != NULL);
        return nil;
    }
    unsigned int mediaRemoteType = ((unsigned int (*)(id, SEL))method_getImplementation(type))(command, typeOf);
    return ((id (*)(Class, SEL, id, unsigned int, id))method_getImplementation(factory))(eventClass, make, command, mediaRemoteType, @{});
}

static BOOL skipToNext(void) {
    if (!fz_naviMusNext) return NO;
    @try {
        MPRemoteCommandEvent *event = nextTrackEvent();
        return event && fz_naviMusNext(event) == MPRemoteCommandHandlerStatusSuccess;
    } @catch (NSException *e) {
        FZLogError("artist block: skipping threw %@", e.name);
        return NO;
    }
}

static void songMayHaveChanged(NSDictionary *info) {
    fz_lastInfo = info;
    if (!FZHidden(FZKeyArtistBlock)) return;
    id songID = info[MPNowPlayingInfoPropertyExternalContentIdentifier];
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    // Only while the sound moves: a paused song restored at launch is left alone until it plays.
    if (![songID isKindOfClass:NSString.class] || (rate && rate.doubleValue <= 0)) return;
    if ([songID isEqualToString:fz_lastSongID]) return;
    fz_lastSongID = songID;

    NSString *credit = FZPlayingArtistCredit();
    NSString *blocked = credit ? blockedNameIn(credit) : nil;
    if (!blocked) {
        fz_skipsInARow = 0;
        return;
    }
    if (fz_skipsInARow >= kMaxSkipsInARow) {
        FZLogError("artist block: %lu blocked songs in a row; not skipping any more until another plays", (unsigned long)fz_skipsInARow);
        return;
    }
    fz_skipsInARow++;
    BOOL skipped = skipToNext();
#ifdef FROZIO_HARNESS
    FZLog("artist block: %@ by %@ → %@", info[MPMediaItemPropertyTitle], credit, skipped ? @"skipped" : @"NOT skipped");
#else
    FZLog("artist block: a blocked song → %@", skipped ? @"skipped" : @"NOT skipped");
#endif
    (void)skipped; // release builds compile FZLog out
}

static void fz_setNowPlayingInfo(id self, SEL _cmd, NSDictionary *info) {
    ((void (*)(id, SEL, NSDictionary *))fz_origSetInfo)(self, _cmd, info);
    NSDictionary *copy = [info copy];
    dispatch_async(dispatch_get_main_queue(), ^{ songMayHaveChanged(copy); });
}

void FZInstallArtistBlock(void) {
    // Public MediaPlayer API, not NaviMus symbols. Installed after lock screen lyrics, this sees NaviMus's
    // own info only: lyrics re-sends go straight to the original setter.
    BOOL handler = FZHookInstanceMethodNamed(@"MPRemoteCommand", @"addTargetWithHandler:", "@@:@?",
                                             (IMP)fz_addTargetWithHandler, &fz_origAddTarget, "artist-block.handler");
    BOOL info = handler && FZHookInstanceMethodNamed(@"MPNowPlayingInfoCenter", @"setNowPlayingInfo:", "v@:@",
                                                     (IMP)fz_setNowPlayingInfo, &fz_origSetInfo, "artist-block.info");
    if (handler && info) FZLog("artist block installed (%@, %lu blocked)", FZHidden(FZKeyArtistBlock) ? @"on" : @"off",
                               (unsigned long)FZBlockedArtists().count);
    else FZLogError("artist block: hooks incomplete (handler=%d info=%d); nothing is skipped", handler, info);
}
