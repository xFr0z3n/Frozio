// See FZRLyricsFetch.h.
#import <MediaPlayer/MediaPlayer.h>
#import "Redesign/Player/FZRLyricsFetch.h"
#import "Redesign/Data/FZServer.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZLog.h"

NSString *const FZKeyLyricsLRCLIB = @"fz.lyrics.lrclib";
static NSMutableDictionary<NSString *, FZSyncedLyrics *> *sFetched;   // main thread
static NSMutableSet<NSString *> *sMissing;                             // asked everywhere, none

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
    return lyricsFromLines(lines, songID, 0, source);
}

FZSyncedLyrics *FZRKnownLyrics(NSString *songID) {
    if (!songID.length) return nil;
    return FZNaviMusSyncedLyrics(songID) ?: sFetched[songID];
}

static void keep(NSString *songID, FZSyncedLyrics *lyrics, NSString *source) {
    if (!sFetched) sFetched = [NSMutableDictionary dictionary];
    if (lyrics) sFetched[songID] = lyrics;
    FZLog("lyrics: %@ for the playing song from %@", lyrics ? @"synced lines" : @"none", source);
}

static void askLRCLIB(NSString *songID, NSDictionary *info, void (^done)(FZSyncedLyrics *)) {
    NSString *title = info[MPMediaItemPropertyTitle], *artist = info[MPMediaItemPropertyArtist];
    if (!FZEnabled(FZKeyLyricsLRCLIB) || !title.length || !artist.length) { done(nil); return; }
    NSURLComponents *url = [NSURLComponents componentsWithString:@"https://lrclib.net/api/get"];
    NSMutableArray *query = [NSMutableArray arrayWithObjects:[NSURLQueryItem queryItemWithName:@"track_name" value:title],
                             [NSURLQueryItem queryItemWithName:@"artist_name" value:artist], nil];
    NSString *album = info[MPMediaItemPropertyAlbumTitle];
    if (album.length) [query addObject:[NSURLQueryItem queryItemWithName:@"album_name" value:album]];
    NSNumber *duration = info[MPMediaItemPropertyPlaybackDuration];
    if (duration.doubleValue > 0) [query addObject:[NSURLQueryItem queryItemWithName:@"duration" value:@(llround(duration.doubleValue)).stringValue]];
    url.queryItems = query;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
    [request setValue:@"LyricsClient/1.0" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 8;
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *synced = [root isKindOfClass:NSDictionary.class] ? root[@"syncedLyrics"] : nil;
        FZSyncedLyrics *lyrics = [synced isKindOfClass:NSString.class] ? FZRLyricsFromLRC(synced, songID, @"lrclib") : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(lyrics); });
    }] resume];
}

void FZRFetchLyrics(NSString *songID, NSDictionary *info, void (^completion)(FZSyncedLyrics *)) {
    FZSyncedLyrics *known = FZRKnownLyrics(songID);
    if (known || !songID.length) { completion(known); return; }
    if ([sMissing containsObject:songID]) { completion(nil); return; }
    void (^finish)(FZSyncedLyrics *, NSString *) = ^(FZSyncedLyrics *lyrics, NSString *source) {
        keep(songID, lyrics, source);
        if (!lyrics) { if (!sMissing) sMissing = [NSMutableSet set]; [sMissing addObject:songID]; }
        completion(lyrics);
    };
    if (!FZServerReady()) { askLRCLIB(songID, info, ^(FZSyncedLyrics *l) { finish(l, @"LRCLIB"); }); return; }
    FZServerGet(@"getLyricsBySongId", @{@"id": songID}, ^(NSDictionary *response, NSError *error) {
        NSArray *structured = response[@"lyricsList"][@"structuredLyrics"];
        for (NSDictionary *entry in [structured isKindOfClass:NSArray.class] ? structured : @[]) {
            if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"synced"] boolValue]) continue;
            FZSyncedLyrics *lyrics = lyricsFromLines(entry[@"line"], songID, [entry[@"offset"] integerValue], @"navidrome");
            if (lyrics) { finish(lyrics, @"the server"); return; }
        }
        askLRCLIB(songID, info, ^(FZSyncedLyrics *l) { finish(l, @"LRCLIB"); });
    });
}
