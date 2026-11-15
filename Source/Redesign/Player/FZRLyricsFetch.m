// See FZRLyricsFetch.h.
#import <MediaPlayer/MediaPlayer.h>
#import "Redesign/Player/FZRLyricsFetch.h"
#import "Redesign/Data/FZServer.h"
#import "Settings/Kit/FZKitCore.h"
#import "Prefs/FZSettings.h"
#import "Lyrics/Taurus/TLShim.h"
#import "Lyrics/Taurus/LyricsSources.h"
#import "Core/FZLog.h"

NSString *const FZKeyLyricsLRCLIB = @"fz.lyrics.lrclib";
NSString *const FZRLyricsAutomatic = @"automatic";
NSString *const FZRLyricsImported = @"imported";
NSNotificationName const FZRLyricsSourceDidChangeNotification = @"FZRLyricsSourceDidChangeNotification";
static NSString *const kSongSourcesKey = @"fz.lyrics.songSources";   // {songID: source key}, kept for good

static NSMutableDictionary<NSString *, FZSyncedLyrics *> *sFetched;   // "songID|source", main thread
static NSMutableSet<NSString *> *sMissing;                             // "songID|source" asked, none

NSArray<NSArray<NSString *> *> *FZRLyricsSources(void) {
    return @[@[FZRLyricsAutomatic, @"Automatic"], @[@"navimus", @"NaviMus"], @[@"server", @"Your server"],
             @[@"binilyrics", @"BiniLyrics"], @[@"musixmatch", @"Musixmatch"], @[@"unison", @"Unison"], @[@"netease", @"NetEase"],
             @[@"lrclib", @"LRCLIB"], @[@"qqmusic", @"QQ Music"], @[@"kugou", @"KuGou"], @[FZRLyricsImported, @"Imported LRC"]];
}

static NSDictionary<NSString *, SGLyricsAsk> *taurusAsks(void) {
    return @{@"binilyrics": SGBiniLyricsAsk, @"musixmatch": SGMusixmatchAsk, @"unison": SGUnisonAsk, @"netease": SGNetEaseAsk,
             @"lrclib": SGLrcLibAsk, @"qqmusic": SGQQMusicAsk, @"kugou": SGKuGouAsk};
}
static NSArray<NSString *> *taurusOrder(void) {
    return @[@"binilyrics", @"musixmatch", @"unison", @"netease", @"lrclib", @"qqmusic", @"kugou"];
}

NSString *FZRLyricsSourceForSong(NSString *songID) {
    NSDictionary *chosen = [[FZSettings defaults] dictionaryForKey:kSongSourcesKey];
    NSString *key = songID ? chosen[songID] : nil;
    return [key isKindOfClass:NSString.class] ? key : FZRLyricsAutomatic;
}

static NSString *cacheKey(NSString *songID) { return [NSString stringWithFormat:@"%@|%@", songID, FZRLyricsSourceForSong(songID)]; }

void FZRSetLyricsSourceForSong(NSString *songID, NSString *key) {
    if (!songID.length) return;
    NSMutableDictionary *chosen = [[[FZSettings defaults] dictionaryForKey:kSongSourcesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (!key.length || [key isEqualToString:FZRLyricsAutomatic]) [chosen removeObjectForKey:songID];
    else chosen[songID] = key;
    [[FZSettings defaults] setObject:chosen forKey:kSongSourcesKey];
    NSString *ck = cacheKey(songID);
    [sFetched removeObjectForKey:ck];
    [sMissing removeObject:ck];
    FZLog("lyrics: %@ chosen for %@", key ?: FZRLyricsAutomatic, songID);
    [NSNotificationCenter.defaultCenter postNotificationName:FZRLyricsSourceDidChangeNotification object:songID];
}

// Lyrics in NaviMus's CachedLyrics shape, parsed by the same reader as NaviMus's saved files.
static FZSyncedLyrics *lyricsFromLines(NSArray<NSDictionary *> *lines, NSString *songID, NSInteger offset, NSString *source) {
    if (!lines.count) return nil;
    NSDictionary *file = @{@"songID": songID, @"synced": @YES, @"offset": @(offset), @"source": source, @"syncedLines": lines};
    return FZSyncedLyricsFromJSON([NSJSONSerialization dataWithJSONObject:file options:0 error:nil], NULL);
}

FZSyncedLyrics *FZRLyricsFromLRC(NSString *lrc, NSString *songID, NSString *source) {
    NSRegularExpression *stamp = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]" options:0 error:nil];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *row in [lrc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray<NSTextCheckingResult *> *stamps = [stamp matchesInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!stamps.count) continue;
        NSString *text = [row substringFromIndex:NSMaxRange(stamps.lastObject.range)];
        for (NSTextCheckingResult *match in stamps) {
            double minutes = [[row substringWithRange:[match rangeAtIndex:1]] doubleValue];
            double seconds = [[row substringWithRange:[match rangeAtIndex:2]] doubleValue];
            [lines addObject:@{@"start": @((NSInteger)llround((minutes * 60 + seconds) * 1000)), @"value": text}];
        }
    }
    [lines sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"start"] compare:b[@"start"]]; }];
    return lyricsFromLines(lines, songID, 0, source);
}

// A taurus source's answer as timed lines: its own starts and texts, or those of its karaoke lines.
static FZSyncedLyrics *lyricsFromResult(SGLyricsResult *result, NSString *songID, NSString *source) {
    if (!result) return nil;
    NSArray<NSNumber *> *starts = result.starts;
    NSArray<NSString *> *texts = result.texts;
    if ((!starts.count || !result.synced) && result.karaokeLines.count && SGKaraokeLinesTiming(result.karaokeLines) != SGKaraokeTimingNone) {
        SGLyricsPageLines(result.karaokeLines, &starts, &texts);
    } else if (!result.synced) {
        return nil;
    }
    NSMutableArray *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN(starts.count, texts.count); i++) {
        if (i + 1 == starts.count && !texts[i].length) continue;   // taurus's empty last line
        [lines addObject:@{@"start": starts[i], @"value": texts[i]}];
    }
    return lyricsFromLines(lines, songID, 0, source);
}

#pragma mark imported .lrc files

static NSString *importedPath(NSString *songID) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *dir = [support.path stringByAppendingPathComponent:@"Frozio/Lyrics"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:"];
    NSString *name = [[songID componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
    return [dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"lrc"]];
}

BOOL FZRImportLRC(NSString *songID, NSString *lrc) {
    if (!songID.length || !FZRLyricsFromLRC(lrc, songID, @"imported")) return NO;
    if (![lrc writeToFile:importedPath(songID) atomically:YES encoding:NSUTF8StringEncoding error:nil]) return NO;
    [sFetched removeObjectForKey:[songID stringByAppendingString:@"|imported"]];
    [sMissing removeObject:[songID stringByAppendingString:@"|imported"]];
    FZRSetLyricsSourceForSong(songID, FZRLyricsImported);
    return YES;
}

static FZSyncedLyrics *importedLyrics(NSString *songID) {
    NSString *lrc = [NSString stringWithContentsOfFile:importedPath(songID) encoding:NSUTF8StringEncoding error:nil];
    return lrc ? FZRLyricsFromLRC(lrc, songID, @"imported") : nil;
}

#pragma mark fetching

FZSyncedLyrics *FZRKnownLyrics(NSString *songID) {
    if (!songID.length) return nil;
    NSString *source = FZRLyricsSourceForSong(songID);
    if ([source isEqualToString:FZRLyricsImported]) return importedLyrics(songID);
    if ([source isEqualToString:FZRLyricsAutomatic] || [source isEqualToString:@"navimus"]) {
        FZSyncedLyrics *saved = FZNaviMusSyncedLyrics(songID);
        if (saved) return saved;
    }
    return sFetched[cacheKey(songID)];
}

static void askServer(NSString *songID, void (^done)(FZSyncedLyrics *)) {
    if (!FZServerReady()) { done(nil); return; }
    FZServerGet(@"getLyricsBySongId", @{@"id": songID}, ^(NSDictionary *response, NSError *error) {
        NSArray *structured = response[@"lyricsList"][@"structuredLyrics"];
        for (NSDictionary *entry in [structured isKindOfClass:NSArray.class] ? structured : @[]) {
            if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"synced"] boolValue]) continue;
            FZSyncedLyrics *lyrics = lyricsFromLines(entry[@"line"], songID, [entry[@"offset"] integerValue], @"navidrome");
            if (lyrics) { done(lyrics); return; }
        }
        done(nil);
    });
}

static void askTaurus(NSString *key, NSString *songID, NSDictionary *info, void (^done)(FZSyncedLyrics *)) {
    SGLyricsAsk ask = taurusAsks()[key];
    NSString *title = info[MPMediaItemPropertyTitle], *artist = info[MPMediaItemPropertyArtist];
    if (!ask || !title.length) { done(nil); return; }
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = songID;
    query.title = title;
    query.artist = artist;
    query.album = info[MPMediaItemPropertyAlbumTitle];
    query.seconds = (NSInteger)llround([info[MPMediaItemPropertyPlaybackDuration] doubleValue]);
    TLNoteSong(songID, query.title, query.artist, query.album, query.seconds);
    @try {
        ask(query, ^(SGLyricsResult *result) {
            FZSyncedLyrics *lyrics = lyricsFromResult(result, songID, key);
            dispatch_async(dispatch_get_main_queue(), ^{ done(lyrics); });
        });
    } @catch (NSException *e) {
        FZLogError("lyrics: %@ threw %@", key, e.name);
        done(nil);
    }
}

// Automatic: the server, then taurus's sources one after another until one has timed lines.
static void askInTurn(NSArray<NSString *> *keys, NSUInteger index, NSString *songID, NSDictionary *info,
                      void (^done)(FZSyncedLyrics *, NSString *)) {
    if (index >= keys.count) { done(nil, @"nowhere"); return; }
    NSString *key = keys[index];
    void (^next)(FZSyncedLyrics *) = ^(FZSyncedLyrics *lyrics) {
        if (lyrics) done(lyrics, key);
        else askInTurn(keys, index + 1, songID, info, done);
    };
    if ([key isEqualToString:@"server"]) askServer(songID, next);
    else askTaurus(key, songID, info, next);
}

void FZRFetchLyrics(NSString *songID, NSDictionary *info, void (^completion)(FZSyncedLyrics *)) {
    FZSyncedLyrics *known = FZRKnownLyrics(songID);
    if (known || !songID.length) { completion(known); return; }
    NSString *source = FZRLyricsSourceForSong(songID), *ck = cacheKey(songID);
    if ([sMissing containsObject:ck] || [source isEqualToString:FZRLyricsImported] || [source isEqualToString:@"navimus"]) {
        completion(nil);
        return;
    }
    void (^finish)(FZSyncedLyrics *, NSString *) = ^(FZSyncedLyrics *lyrics, NSString *from) {
        if (!sFetched) sFetched = [NSMutableDictionary dictionary];
        if (!sMissing) sMissing = [NSMutableSet set];
        if (lyrics) sFetched[ck] = lyrics;
        else [sMissing addObject:ck];
        FZLog("lyrics: %@ for %@ from %@ (%@)", lyrics ? @"synced lines" : @"none", songID, from, source);
        // Only if the song's choice hasn't changed meanwhile.
        if ([FZRLyricsSourceForSong(songID) isEqualToString:source]) completion(lyrics);
    };
    NSArray<NSString *> *keys;
    if ([source isEqualToString:FZRLyricsAutomatic]) {
        keys = FZEnabled(FZKeyLyricsLRCLIB) ? [@[@"server"] arrayByAddingObjectsFromArray:taurusOrder()] : @[@"server"];
    } else {
        keys = @[source];
    }
    askInTurn(keys, 0, songID, info, finish);
}
