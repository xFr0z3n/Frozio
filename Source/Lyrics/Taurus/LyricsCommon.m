// From taurus (github.com/xFr0z3n/taurus @ fe3211c, GPL-3.0), Shared/LyricsSources/LyricsSources.m (the requests and shared parts). Changed for Frozio: imports, and
// Spotify-only parts left out (see Source/Lyrics/Taurus/TLShim.h). docs/LICENSES.md.
#import <stdatomic.h>
#import "Lyrics/Taurus/TLShim.h"
#import "Lyrics/Taurus/LyricsSources.h"

static const NSTimeInterval kTimeout = 6;

@implementation SGLyricsLink
@end

@implementation SGLyricsResult
@end

@implementation SGLyricsQuery
@end

@implementation SGLyricsProvider
@end

#pragma mark - the requests the sources share

// Every request any source has lost to the network or to a server too busy to answer, counted so a
// walk can tell "no source has lyrics" from "a source could not say". Only the first is kept.
static _Atomic NSUInteger sg_failures;

BOOL SGLyricsReplyFailed(NSURLResponse *response, NSError *error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    return error || status == 429 || status >= 500;
}

void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {
    if (SGLyricsReplyFailed(response, error)) atomic_fetch_add(&sg_failures, 1);
}

NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}

static NSMutableURLRequest *requestFor(NSURL *url, NSDictionary<NSString *, NSString *> *headers) {
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kTimeout];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    return request;
}

// The body whatever the status, and the reply it came with; nil for both when there was none.
static void sendForReply(NSURLRequest *request, void (^done)(NSData *body, NSHTTPURLResponse *response)) {
    if (!request) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, nil); });
        return;
    }
    NSURL *url = request.URL;
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *reply = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        SGLyricsNoteReply(response, error);
        if (error || reply.statusCode >= 400) SGLog(@"lyrics: %@ answered %ld, error %@", url.host, (long)reply.statusCode, error);
        dispatch_async(dispatch_get_main_queue(), ^{ done(data, reply); });
    }] resume];
}

static void send(NSURLRequest *request, void (^done)(NSData *body)) {
    sendForReply(request, ^(NSData *body, NSHTTPURLResponse *reply) {
        done(reply.statusCode >= 400 ? nil : body);
    });
}

static id jsonIn(NSData *body) {
    return body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
}

// A source may answer JSON null where a number should be; NSNull is not nil and does not answer
// doubleValue, and reading one straight off killed whole launches. Every unguarded number in a
// source's JSON goes through this.
NSInteger SGLyricsNumber(id value) {
    return [value respondsToSelector:@selector(doubleValue)] ? (NSInteger)[value doubleValue] : 0;
}

void SGLyricsGetJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root)) {
    send(requestFor(url, headers), ^(NSData *body) {
        done(jsonIn(body));
    });
}

void SGLyricsGetJSONReply(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root, NSHTTPURLResponse *response)) {
    sendForReply(requestFor(url, headers), ^(NSData *body, NSHTTPURLResponse *reply) {
        done(jsonIn(body), reply);
    });
}

void SGLyricsGetText(NSURL *url, void (^done)(NSString *text)) {
    send(requestFor(url, nil), ^(NSData *body) {
        done(body.length ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : nil);
    });
}

void SGLyricsPostJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body, void (^done)(id root)) {
    NSData *written = [NSJSONSerialization isValidJSONObject:body]
        ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : nil;
    NSMutableURLRequest *request = written ? requestFor(url, headers) : nil;
    request.HTTPMethod = @"POST";
    request.HTTPBody = written;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    send(request, ^(NSData *answer) {
        done(jsonIn(answer));
    });
}

// A pause this long between two lines gets a ♪, so Spotify's page does not hold the last one.
static const NSInteger kBreakMs = 3000;

void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray<NSNumber *> *at = [NSMutableArray array];
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    SGKaraokeLine *last = nil;
    for (SGKaraokeLine *line in lines) {
        if (last && line.start - last.end >= kBreakMs) {
            [at addObject:@(last.end)];
            [said addObject:@"♪"];
        }
        NSString *text = SGKaraokeLineText(line);
        // The backing vocals read on the same line on Spotify's own page, which has one row a line.
        if (line.backing) text = [text stringByAppendingFormat:@" %@", SGKaraokeLineText(line.backing)];
        [at addObject:@(line.start)];
        [said addObject:text];
        last = line;
    }
    if (last) {
        [at addObject:@(last.end)];
        [said addObject:@""];
    }
    *starts = at;
    *texts = said;
}


NSArray<NSString *> *SGLyricsTranslationLanguages(void) {
    return @[@"", @"ar", @"zh-Hans", @"zh-Hant", @"cs", @"da", @"nl", @"en", @"fi", @"fr", @"de", @"el", @"he",
             @"hi", @"hu", @"id", @"it", @"ja", @"ko", @"nb", @"pl", @"pt", @"ro", @"ru", @"sk", @"es", @"sv",
             @"th", @"tr", @"uk", @"vi"];
}

NSArray<NSString *> *SGLyricsTranslationLanguageNames(void) {
    NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en"];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *tag in SGLyricsTranslationLanguages()) {
        [names addObject:tag.length ? [english localizedStringForLocaleIdentifier:tag] ?: tag : @"Any · iPhone's language"];
    }
    return names;
}

NSString *SGLyricsTranslationLanguage(void) {
    NSArray<NSString *> *tags = SGLyricsTranslationLanguages();
    NSInteger index = SGInt(SGKeyLyricsTranslationLanguage, 0);
    return index > 0 && index < (NSInteger)tags.count ? tags[(NSUInteger)index] : nil;
}


#pragma mark - Frozio: songs by name

static NSMutableDictionary<NSString *, NSDictionary *> *tl_songs;

void TLNoteSong(NSString *songID, NSString *title, NSString *artist, NSString *album, NSInteger seconds) {
    if (!songID.length) return;
    @synchronized (NSNull.null) {
        if (!tl_songs) tl_songs = [NSMutableDictionary dictionary];
        tl_songs[songID] = @{@"title": title ?: @"", @"artist": artist ?: @"", @"album": album ?: @"", @"seconds": @(seconds)};
    }
}

BOOL SGLocalFileIs(NSString *trackID) { return YES; }

NSDictionary *SGLocalFileInfo(NSString *trackID) {
    @synchronized (NSNull.null) { return trackID ? tl_songs[trackID] : nil; }
}
