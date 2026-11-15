// Adapted from taurus/tweak/Sources/Shared/ArtistBlock/ArtistSkip.x and ArtistBlock.m @ fe3211c (GPL-3.0).
// Renamed SG→FZ; Logos replaced by FZHook; Spotify's player, URIs and skip controller replaced by
// NaviMus's Now Playing info and its own nextTrackCommand handler.
#import <MediaPlayer/MediaPlayer.h>
#import "ArtistBlock/FZArtistBlock.h"
#import "Core/FZRemote.h"
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

static NSString *fz_lastSongID;            // main thread: the song already looked at while playing
static NSUInteger fz_skipsInARow;          // main thread

NSString *FZPlayingArtistCredit(void) {
    id credit = FZNowPlayingInfo()[MPMediaItemPropertyArtist];
    return [credit isKindOfClass:NSString.class] && [credit length] ? credit : nil;
}

// NaviMus's own next-track handler, as the lock screen's Next button runs it (FZRemote).
static BOOL skipToNext(void) {
    return FZRemoteSend(MPRemoteCommandCenter.sharedCommandCenter.nextTrackCommand);
}

static void songMayHaveChanged(void) {
    NSDictionary *info = FZNowPlayingInfo();
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

void FZInstallArtistBlock(void) {
    // NaviMus's Now Playing info and its next-track handler come from FZRemote (installed before this).
    [NSNotificationCenter.defaultCenter addObserverForName:FZNowPlayingDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { songMayHaveChanged(); }];
    FZLog("artist block installed (%@, %lu blocked)", FZHidden(FZKeyArtistBlock) ? @"on" : @"off",
          (unsigned long)FZBlockedArtists().count);
}
