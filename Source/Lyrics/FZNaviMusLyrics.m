#import "Lyrics/FZNaviMusLyrics.h"
#import "Core/FZLog.h"

// A miss is asked about again only this often: NaviMus saves a song's lyrics when it loads them,
// which can be well after the song started.
static const NSTimeInterval kRescanAfter = 10;

@interface FZLyricLine ()
@property (nonatomic) NSInteger start;
@property (nonatomic, copy) NSString *text;
@end
@implementation FZLyricLine
@end

@interface FZSyncedLyrics ()
@property (nonatomic, copy) NSArray<FZLyricLine *> *lines;
@property (nonatomic) NSInteger offset;
@property (nonatomic, copy) NSString *source;
@end
@implementation FZSyncedLyrics
@end

FZSyncedLyrics *FZSyncedLyricsFromJSON(NSData *data, NSString **songID) {
    id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *file = root;
    id song = file[@"songID"], synced = file[@"synced"], raw = file[@"syncedLines"];
    if (![song isKindOfClass:NSString.class] || ![raw isKindOfClass:NSArray.class]) return nil;
    if (songID) *songID = song;
    if (![synced isKindOfClass:NSNumber.class] || ![synced boolValue]) return nil;

    NSMutableArray<FZLyricLine *> *lines = [NSMutableArray array];
    for (id entry in raw) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id start = entry[@"start"], value = entry[@"value"];
        if (![start isKindOfClass:NSNumber.class] || ![value isKindOfClass:NSString.class]) continue;
        FZLyricLine *line = [FZLyricLine new];
        line.start = [start integerValue];
        line.text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [lines addObject:line];
    }
    if (!lines.count) return nil;
    [lines sortUsingComparator:^NSComparisonResult(FZLyricLine *a, FZLyricLine *b) {
        return a.start < b.start ? NSOrderedAscending : a.start > b.start ? NSOrderedDescending : NSOrderedSame;
    }];
    FZSyncedLyrics *lyrics = [FZSyncedLyrics new];
    lyrics.lines = lines;
    id offset = file[@"offset"], source = file[@"source"];
    lyrics.offset = [offset isKindOfClass:NSNumber.class] ? [offset integerValue] : 0;
    lyrics.source = [source isKindOfClass:NSString.class] ? source : @"";
    return lyrics;
}

// NaviMus's own "Auto" order (LyricsSettings.LyricsOrigin): the server first, then LRCLib.
static BOOL better(FZSyncedLyrics *candidate, FZSyncedLyrics *current) {
    if (!current) return YES;
    return [candidate.source isEqualToString:@"navidrome"] && ![current.source isEqualToString:@"navidrome"];
}

#pragma mark - index

static dispatch_queue_t sIndexQueue;
// Index state lives on sIndexQueue; the found map is copied to the main thread after each scan.
static NSMutableDictionary<NSString *, NSString *> *sParsedPaths;          // path -> songID ("" if unusable)
static NSMutableDictionary<NSString *, FZSyncedLyrics *> *sFoundOnQueue;   // songID -> best lyrics
static NSDictionary<NSString *, FZSyncedLyrics *> *sFound;                 // main thread copy
static NSMutableDictionary<NSString *, NSDate *> *sMissedAt;               // main thread
static BOOL sScanning;                                                     // main thread

static NSArray<NSURL *> *lyricsFolders(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *support = [fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *root = [support URLByAppendingPathComponent:@"Arpeggi" isDirectory:YES];
    NSMutableArray<NSURL *> *folders = [NSMutableArray array];
    for (NSURL *database in [fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]) {
        NSURL *lyrics = [database URLByAppendingPathComponent:@"lyrics" isDirectory:YES];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:lyrics.path isDirectory:&isDir] && isDir) [folders addObject:lyrics];
    }
    return folders;
}

static void scanOnQueue(void) {
    NSUInteger added = 0;
    for (NSURL *folder in lyricsFolders()) {
        for (NSURL *file in [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil
                                                                           options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]) {
            if (![file.pathExtension isEqualToString:@"json"] || sParsedPaths[file.path]) continue;
            NSString *songID = nil;
            FZSyncedLyrics *lyrics = FZSyncedLyricsFromJSON([NSData dataWithContentsOfURL:file], &songID);
            sParsedPaths[file.path] = songID ?: @"";
            if (lyrics && songID && better(lyrics, sFoundOnQueue[songID])) {
                sFoundOnQueue[songID] = lyrics;
                added++;
            }
        }
    }
    if (added) FZLog("lyrics: indexed %lu more synced songs (%lu in all)", (unsigned long)added, (unsigned long)sFoundOnQueue.count);
}

FZSyncedLyrics *FZNaviMusSyncedLyrics(NSString *songID) {
    if (!songID.length) return nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sIndexQueue = dispatch_queue_create("com.frozio.lyrics.index", DISPATCH_QUEUE_SERIAL);
        sParsedPaths = [NSMutableDictionary dictionary];
        sFoundOnQueue = [NSMutableDictionary dictionary];
        sMissedAt = [NSMutableDictionary dictionary];
    });
    FZSyncedLyrics *found = sFound[songID];
    if (found) return found;

    NSDate *missed = sMissedAt[songID];
    if (sScanning || (missed && -missed.timeIntervalSinceNow < kRescanAfter)) return nil;
    sMissedAt[songID] = [NSDate date];
    sScanning = YES;
    dispatch_async(sIndexQueue, ^{
        scanOnQueue();
        NSDictionary *copy = [sFoundOnQueue copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            sFound = copy;
            sScanning = NO;
            if (!copy[songID]) FZLog("lyrics: none saved by NaviMus for the playing song yet");
        });
    });
    return nil;
}
