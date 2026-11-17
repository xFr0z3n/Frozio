// See FZRAnimatedCovers.h.
#import <AVFoundation/AVFoundation.h>
#import <Security/Security.h>
#import "Redesign/Player/FZRAnimatedCovers.h"
#import "Settings/Kit/FZKitCore.h"
#import "Settings/Kit/FZModPage.h"
#import "Settings/Kit/FZPageStyle.h"
#import "Prefs/FZSettings.h"
#import "Core/FZLog.h"
#import <QuartzCore/QuartzCore.h>

NSString *const FZRKeyAnimatedCoversURL = @"fz.animatedCovers.url";
NSString *const FZRKeyAnimatedCoversUser = @"fz.animatedCovers.user";
NSNotificationName const FZRAnimatedCoversDidChangeNotification = @"FZRAnimatedCoversDidChangeNotification";
static NSString *const kOffKey = @"fz.animatedCovers.off";   // [album title, lowercased]
static NSString *const kKeychainService = @"Frozio.AnimatedCovers";
static const NSTimeInterval kListFresh = 15 * 60;

#pragma mark - settings

static NSString *folderAddress(void) {
    NSString *url = [[FZSettings defaults] stringForKey:FZRKeyAnimatedCoversURL];
    url = [url stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!url.length) return nil;
    if (![url.lowercaseString hasPrefix:@"http://"] && ![url.lowercaseString hasPrefix:@"https://"]) url = [@"https://" stringByAppendingString:url];
    return [url hasSuffix:@"/"] ? url : [url stringByAppendingString:@"/"];
}

BOOL FZRAnimatedCoversConfigured(void) { return folderAddress() != nil; }

static NSDictionary *passwordQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService: kKeychainService,
             (__bridge id)kSecAttrAccount: @"password"};
}

static NSString *storedPassword(void) {
    NSMutableDictionary *query = [passwordQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &data) != errSecSuccess || !data) return nil;
    NSString *password = [[NSString alloc] initWithData:(__bridge_transfer NSData *)data encoding:NSUTF8StringEncoding];
    return password.length ? password : nil;
}

static void storePassword(NSString *password) {
    SecItemDelete((__bridge CFDictionaryRef)passwordQuery());
    if (!password.length) return;
    NSMutableDictionary *item = [passwordQuery() mutableCopy];
    item[(__bridge id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

static void authorize(NSMutableURLRequest *request) {
    NSString *user = [[FZSettings defaults] stringForKey:FZRKeyAnimatedCoversUser];
    if (!user.length) return;
    NSString *pair = [NSString stringWithFormat:@"%@:%@", user, storedPassword() ?: @""];
    NSString *encoded = [[pair dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    [request setValue:[@"Basic " stringByAppendingString:encoded] forHTTPHeaderField:@"Authorization"];
}

#pragma mark - matching

static NSString *normalized(NSString *text) {
    if (!text.length) return @"";
    NSString *s = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil].lowercaseString;
    // Brackets: "(Deluxe)", "[Explicit]", "(Unreleased)".
    s = [s stringByReplacingOccurrencesOfString:@"\\([^)]*\\)|\\[[^\\]]*\\]|\\{[^}]*\\}" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, s.length)];
    // Featured artists to the end.
    s = [s stringByReplacingOccurrencesOfString:@"\\s(feat\\.?|ft\\.?|featuring)\\s.*$" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, s.length)];
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@" and "];
    NSMutableString *kept = [NSMutableString string];
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length) options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *ch, NSRange r, NSRange e, BOOL *stop) {
        unichar c = [ch characterAtIndex:0];
        [kept appendString:[NSCharacterSet.alphanumericCharacterSet characterIsMember:c] ? ch : @" "];
    }];
    NSArray *words = [kept componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}

static NSString *squashed(NSString *text) { return [text stringByReplacingOccurrencesOfString:@" " withString:@""]; }

// Each artist named in a credit ("A, B & C", "A x B"), and the credit whole.
static NSArray<NSString *> *artistsIn(NSString *artist) {
    NSMutableArray *names = [NSMutableArray arrayWithObject:normalized(artist)];
    for (NSString *part in [artist componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",&/;"]]) {
        NSString *n = normalized(part);
        if (n.length) [names addObject:n];
    }
    for (NSString *part in [artist.lowercaseString componentsSeparatedByString:@" x "]) {
        NSString *n = normalized(part);
        if (n.length) [names addObject:n];
    }
    return names;
}

static BOOL artistsMatch(NSString *fileArtist, NSString *artist) {
    NSString *file = squashed(normalized(fileArtist));
    if (!file.length) return NO;
    for (NSString *name in artistsIn(artist)) {
        NSString *n = squashed(name);
        if (n.length && ([n isEqualToString:file] || [n containsString:file] || [file containsString:n])) return YES;
    }
    return NO;
}

// 3 the same name, 2 the album's name starts with the file's, 1 one holds the other; 0 no match.
static NSInteger albumScore(NSString *fileAlbum, NSString *album) {
    NSString *f = normalized(fileAlbum), *a = normalized(album);
    if (!f.length || !a.length) return 0;
    if ([f isEqualToString:a] || [squashed(f) isEqualToString:squashed(a)]) return 3;
    if ([a hasPrefix:[f stringByAppendingString:@" "]] || [f hasPrefix:[a stringByAppendingString:@" "]]) return 2;
    NSString *wordsA = [NSString stringWithFormat:@" %@ ", a], *wordsF = [NSString stringWithFormat:@" %@ ", f];
    if ([wordsA containsString:wordsF] || [wordsF containsString:wordsA]) return 1;
    // The raw names, for an album whose whole name is in brackets.
    NSString *rawF = squashed(normalized([fileAlbum stringByReplacingOccurrencesOfString:@"(" withString:@" "])),
             *rawA = squashed(normalized([album stringByReplacingOccurrencesOfString:@"(" withString:@" "]));
    return rawF.length && [rawF isEqualToString:rawA] ? 3 : 0;
}

NSString *FZRAnimatedCoverMatch(NSArray<NSString *> *fileNames, NSString *artist, NSString *album) {
    NSString *best = nil;
    NSInteger bestScore = 0;
    for (NSString *name in fileNames) {
        NSString *stem = name.stringByDeletingPathExtension;
        NSRange dash = [stem rangeOfString:@" - "];
        if (dash.location == NSNotFound) dash = [stem rangeOfString:@" – "];
        if (dash.location == NSNotFound) continue;
        NSString *fileArtist = [stem substringToIndex:dash.location], *fileAlbum = [stem substringFromIndex:NSMaxRange(dash)];
        if (!artistsMatch(fileArtist, artist)) continue;
        NSInteger score = albumScore(fileAlbum, album);
        if (score > bestScore) { bestScore = score; best = name; }
    }
    return best;
}

#pragma mark - the folder's list

static NSDictionary<NSString *, NSURL *> *sList;   // file name → address
static NSDate *sListedAt;
static NSString *sListedFolder;
static NSMutableArray *sListWaiting;

static NSDictionary<NSString *, NSURL *> *filesIn(NSString *body, NSURL *folder, NSString *pattern) {
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    for (NSTextCheckingResult *match in [regex matchesInString:body options:0 range:NSMakeRange(0, body.length)]) {
        NSString *href = [[body substringWithRange:[match rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        NSURL *url = [NSURL URLWithString:href relativeToURL:folder].absoluteURL;
        NSString *name = url.lastPathComponent.stringByRemovingPercentEncoding ?: url.lastPathComponent;
        if ([name.pathExtension.lowercaseString isEqualToString:@"mp4"]) files[name] = url;
    }
    return files;
}

static void finishList(NSDictionary *files, NSString *folder) {
    if (files) {
        sList = files;
        sListedAt = [NSDate date];
        sListedFolder = folder;
        FZLog("animated covers: %lu in the folder", (unsigned long)files.count);
        [NSNotificationCenter.defaultCenter postNotificationName:FZRAnimatedCoversDidChangeNotification object:nil];
    }
    NSArray *waiting = sListWaiting;
    sListWaiting = nil;
    for (void (^done)(NSDictionary *) in waiting) done(sList);
}

static void listFolder(BOOL force, void (^done)(NSDictionary<NSString *, NSURL *> *files)) {
    NSString *folder = folderAddress();
    if (!folder) { done(nil); return; }
    if (!force && sList && [sListedFolder isEqualToString:folder] && -sListedAt.timeIntervalSinceNow < kListFresh) { done(sList); return; }
    if (sListWaiting) { [sListWaiting addObject:[done copy]]; return; }
    sListWaiting = [NSMutableArray arrayWithObject:[done copy]];
    NSURL *url = [NSURL URLWithString:folder];
    if (!url) { finishList(nil, folder); return; }
    // WebDAV first: the folder's members by PROPFIND.
    NSMutableURLRequest *propfind = [NSMutableURLRequest requestWithURL:url];
    propfind.HTTPMethod = @"PROPFIND";
    [propfind setValue:@"1" forHTTPHeaderField:@"Depth"];
    [propfind setValue:@"application/xml" forHTTPHeaderField:@"Content-Type"];
    propfind.HTTPBody = [@"<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/></d:prop></d:propfind>" dataUsingEncoding:NSUTF8StringEncoding];
    propfind.timeoutInterval = 15;
    authorize(propfind);
    [[NSURLSession.sharedSession dataTaskWithRequest:propfind completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (status == 207 && body) {
            NSDictionary *files = filesIn(body, url, @"<(?:[a-z0-9]+:)?href>([^<]+)</(?:[a-z0-9]+:)?href>");
            dispatch_async(dispatch_get_main_queue(), ^{ finishList(files, folder); });
            return;
        }
        // A plain web server: its HTML index.
        NSMutableURLRequest *get = [NSMutableURLRequest requestWithURL:url];
        get.timeoutInterval = 15;
        authorize(get);
        [[NSURLSession.sharedSession dataTaskWithRequest:get completionHandler:^(NSData *page, NSURLResponse *reply, NSError *problem) {
            NSInteger code = [(NSHTTPURLResponse *)reply statusCode];
            NSString *html = page ? [[NSString alloc] initWithData:page encoding:NSUTF8StringEncoding] : nil;
            NSDictionary *files = code >= 200 && code < 300 && html ? filesIn(html, url, @"href=\"([^\"]+\\.mp4)\"") : nil;
            if (!files) FZLogError("animated covers: the folder couldn't be listed (PROPFIND %ld, GET %ld, %@)", (long)status, (long)code,
                                   (problem ?: error).localizedDescription ?: @"no error");
            dispatch_async(dispatch_get_main_queue(), ^{ finishList(files, folder); });
        }] resume];
    }] resume];
}

#pragma mark - files

static NSMutableDictionary<NSString *, id> *sMatches;   // "artist|album" → file name or NSNull

static NSURL *cacheFolder(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [caches URLByAppendingPathComponent:@"Frozio/AnimatedCovers" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return folder;
}

static NSString *safeName(NSURL *remote) {
    NSString *safe = [[remote.absoluteString componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@"_"];
    return safe.length > 160 ? [safe substringFromIndex:safe.length - 160] : safe;
}
// The file as downloaded, the copy made small enough to play smoothly, and its first frame.
static NSURL *downloadedFileFor(NSURL *remote) { return [cacheFolder() URLByAppendingPathComponent:[safeName(remote) stringByAppendingPathExtension:@"mp4"]]; }
static NSURL *readyFileFor(NSURL *remote) { return [cacheFolder() URLByAppendingPathComponent:[safeName(remote) stringByAppendingString:@".ready.mp4"]]; }
static NSURL *posterFileFor(NSURL *ready) { return [ready.URLByDeletingPathExtension URLByAppendingPathExtension:@"jpg"]; }

// Long-running work off the main thread: matching, scaling, first frames (the album page froze and the app was
// killed with a large video, device log build 51).
static dispatch_queue_t workQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("fz.animatedCovers", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0)); });
    return queue;
}

// Motion covers come as large as 2160 px, too much to decode twice while the app works: they're re-encoded once at
// most 1080 px, and their first frame saved, so a cover shows at once and plays smoothly afterwards.
static void prepare(NSURL *downloaded, NSURL *ready, void (^done)(BOOL ok)) {
    dispatch_async(workQueue(), ^{
        if ([NSFileManager.defaultManager fileExistsAtPath:ready.path]) { done(YES); return; }
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:downloaded options:nil];
        AVAssetTrack *video = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        CGSize size = video ? CGSizeApplyAffineTransform(video.naturalSize, video.preferredTransform) : CGSizeZero;
        CGFloat longest = MAX(fabs(size.width), fabs(size.height));
        void (^poster)(void) = ^{
            AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:ready options:nil]];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(900, 900);
            CGImageRef frame = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
            if (frame) {
                [UIImageJPEGRepresentation([UIImage imageWithCGImage:frame], 0.85) writeToURL:posterFileFor(ready) atomically:YES];
                CGImageRelease(frame);
            }
        };
        if (longest > 0 && longest <= 1100) {
            BOOL ok = [NSFileManager.defaultManager copyItemAtURL:downloaded toURL:ready error:nil];
            if (ok) poster();
            done(ok);
            return;
        }
        AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetHEVC1920x1080]
            ?: [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPreset1920x1080];
        if (!export) {
            BOOL ok = [NSFileManager.defaultManager copyItemAtURL:downloaded toURL:ready error:nil];
            if (ok) poster();
            done(ok);
            return;
        }
        NSURL *temp = [ready URLByAppendingPathExtension:@"part.mp4"];
        [NSFileManager.defaultManager removeItemAtURL:temp error:nil];
        export.outputURL = temp;
        export.outputFileType = AVFileTypeMPEG4;
        export.shouldOptimizeForNetworkUse = NO;
        CFTimeInterval started = CACurrentMediaTime();
        [export exportAsynchronouslyWithCompletionHandler:^{
            dispatch_async(workQueue(), ^{
                BOOL ok = export.status == AVAssetExportSessionStatusCompleted && [NSFileManager.defaultManager moveItemAtURL:temp toURL:ready error:nil];
                // Without a smaller copy, the original plays.
                if (!ok) ok = [NSFileManager.defaultManager copyItemAtURL:downloaded toURL:ready error:nil];
                if (ok) poster();
                FZLog("animated covers: %@ prepared from %.0f px in %.1f s (%@)", ready.lastPathComponent, longest,
                      CACurrentMediaTime() - started, export.error.localizedDescription ?: @"scaled");
                done(ok);
            });
        }];
    });
}

#pragma mark - albums' own choices

static NSString *const kAlbumsKey = @"fz.animatedCovers.albums";   // {album title, lowercased: {mode, file}}

static NSString *albumKey(NSString *album) {
    return [album stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
}

static NSDictionary *albumEntry(NSString *album) {
    if (!album.length) return nil;
    id entry = [[FZSettings defaults] dictionaryForKey:kAlbumsKey][albumKey(album)];
    return [entry isKindOfClass:NSDictionary.class] ? entry : nil;
}

static void setAlbumEntry(NSString *album, NSString *field, id value) {
    if (!album.length) return;
    NSMutableDictionary *all = [[[FZSettings defaults] dictionaryForKey:kAlbumsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [albumEntry(album) mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) entry[field] = value; else [entry removeObjectForKey:field];
    if (entry.count) all[albumKey(album)] = entry; else [all removeObjectForKey:albumKey(album)];
    [[FZSettings defaults] setObject:all forKey:kAlbumsKey];
    [sMatches removeAllObjects];
    [NSNotificationCenter.defaultCenter postNotificationName:FZRAnimatedCoversDidChangeNotification object:nil];
}

FZRAnimatedCoverMode FZRAnimatedCoverModeFor(NSString *album) {
    if (album.length && [[[FZSettings defaults] arrayForKey:kOffKey] containsObject:albumKey(album)]) return FZRAnimatedCoverStill;   // build 51's list
    return (FZRAnimatedCoverMode)[albumEntry(album)[@"mode"] integerValue];
}

void FZRSetAnimatedCoverMode(NSString *album, FZRAnimatedCoverMode mode) {
    if (!album.length) return;
    NSMutableArray *off = [[[FZSettings defaults] arrayForKey:kOffKey] mutableCopy];
    if ([off containsObject:albumKey(album)]) { [off removeObject:albumKey(album)]; [[FZSettings defaults] setObject:off forKey:kOffKey]; }
    FZLog("animated covers: %@ set to %ld", album, (long)mode);
    setAlbumEntry(album, @"mode", mode == FZRAnimatedCoverDefault ? nil : @(mode));
}

NSString *FZRAnimatedCoverChosenFile(NSString *album) {
    id file = albumEntry(album)[@"file"];
    return [file isKindOfClass:NSString.class] ? file : nil;
}

void FZRSetAnimatedCoverChosenFile(NSString *album, NSString *fileName) {
    FZLog("animated covers: %@ → %@ chosen", album, fileName ?: @"automatic");
    setAlbumEntry(album, @"file", fileName);
}

BOOL FZRAnimatedCoverOff(NSString *album) { return FZRAnimatedCoverModeFor(album) == FZRAnimatedCoverStill; }
void FZRSetAnimatedCoverOff(NSString *album, BOOL off) { FZRSetAnimatedCoverMode(album, off ? FZRAnimatedCoverStill : FZRAnimatedCoverDefault); }

void FZRAnimatedCoverFileNames(void (^completion)(NSArray<NSString *> *names)) {
    listFolder(NO, ^(NSDictionary<NSString *, NSURL *> *files) {
        completion([files.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] ?: @[]);
    });
}

#pragma mark - finding an album's cover

static NSMutableDictionary<NSURL *, NSMutableArray *> *sDownloads;

static void deliver(NSURL *remote, NSURL *ready) {
    NSArray *waiting = sDownloads[remote];
    [sDownloads removeObjectForKey:remote];
    for (void (^done)(NSURL *) in waiting) done(ready);
}

static void fetchAndPrepare(NSURL *remote, NSString *name, void (^completion)(NSURL *file)) {
    NSURL *ready = readyFileFor(remote), *downloaded = downloadedFileFor(remote);
    if ([NSFileManager.defaultManager fileExistsAtPath:ready.path]) { completion(ready); return; }
    if (!sDownloads) sDownloads = [NSMutableDictionary dictionary];
    if (sDownloads[remote]) { [sDownloads[remote] addObject:[completion copy]]; return; }
    sDownloads[remote] = [NSMutableArray arrayWithObject:[completion copy]];
    void (^prepared)(BOOL) = ^(BOOL ok) { dispatch_async(dispatch_get_main_queue(), ^{ deliver(remote, ok ? ready : nil); }); };
    if ([NSFileManager.defaultManager fileExistsAtPath:downloaded.path]) { prepare(downloaded, ready, prepared); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:remote];
    request.timeoutInterval = 90;
    authorize(request);
    [[NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *temp, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        BOOL ok = temp && status >= 200 && status < 300;
        if (ok) {
            [NSFileManager.defaultManager removeItemAtURL:downloaded error:nil];
            ok = [NSFileManager.defaultManager moveItemAtURL:temp toURL:downloaded error:nil];
        }
        if (!ok) {
            FZLogError("animated covers: %@ didn't download (%ld, %@)", name, (long)status, error.localizedDescription ?: @"-");
            dispatch_async(dispatch_get_main_queue(), ^{ deliver(remote, nil); });
            return;
        }
        prepare(downloaded, ready, prepared);
    }] resume];
}

static NSMutableDictionary<NSString *, NSURL *> *sReady;   // "artist|album" → prepared file, for an instant answer

void FZRAnimatedCoverFor(NSString *artist, NSString *album, void (^completion)(NSURL *file)) {
    if (!FZRAnimatedCoversConfigured() || !album.length || FZRAnimatedCoverOff(album)) { completion(nil); return; }
    NSString *key = [NSString stringWithFormat:@"%@|%@", artist ?: @"", album];
    NSURL *known = sReady[key];
    if (known && [NSFileManager.defaultManager fileExistsAtPath:known.path]) { completion(known); return; }
    NSString *chosen = FZRAnimatedCoverChosenFile(album);
    listFolder(NO, ^(NSDictionary<NSString *, NSURL *> *files) {
        void (^use)(NSString *) = ^(NSString *name) {
            NSURL *remote = name ? files[name] : nil;
            if (!remote) { completion(nil); return; }
            fetchAndPrepare(remote, name, ^(NSURL *file) {
                if (file) { if (!sReady) sReady = [NSMutableDictionary dictionary]; sReady[key] = file; }
                completion(file);
            });
        };
        if (chosen && files[chosen]) { use(chosen); return; }
        if (!sMatches) sMatches = [NSMutableDictionary dictionary];
        id matched = sMatches[key];
        if (matched) { use([matched isKindOfClass:NSString.class] ? matched : nil); return; }
        NSArray *names = files.allKeys;
        dispatch_async(workQueue(), ^{
            NSString *name = FZRAnimatedCoverMatch(names, artist ?: @"", album);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!sMatches) sMatches = [NSMutableDictionary dictionary];
                sMatches[key] = name ?: NSNull.null;
                FZLog("animated covers: %@ by %@ → %@", album, artist, name ?: @"none");
                use(name);
            });
        });
    });
}

void FZRAnimatedCoverPrefetch(NSString *artist, NSString *album) {
    FZRAnimatedCoverFor(artist, album, ^(NSURL *file) {});
}

static void forgetList(void) {
    sList = nil;
    sListedAt = nil;
    [sMatches removeAllObjects];
    [sReady removeAllObjects];
    [NSNotificationCenter.defaultCenter postNotificationName:FZRAnimatedCoversDidChangeNotification object:nil];
}

#pragma mark - one player per video

// Every view showing a video shares its one player (the album page and the player show the same cover), so it's
// decoded once and is already running when another view shows it. The last three are kept, paused when unseen.
@interface FZRCoverLoop : NSObject
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic) NSInteger users;
@property (nonatomic) CFTimeInterval used;
@end
@implementation FZRCoverLoop
@end

static NSMutableDictionary<NSURL *, FZRCoverLoop *> *sLoops;

static FZRCoverLoop *loopFor(NSURL *file) {
    if (!sLoops) sLoops = [NSMutableDictionary dictionary];
    FZRCoverLoop *loop = sLoops[file];
    if (!loop) {
        loop = [FZRCoverLoop new];
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:file];
        loop.player = [AVQueuePlayer queuePlayerWithItems:@[]];
        loop.player.muted = YES;
        loop.player.preventsDisplaySleepDuringVideoPlayback = NO;
        loop.player.allowsExternalPlayback = NO;
        loop.player.automaticallyWaitsToMinimizeStalling = NO;
        loop.looper = [AVPlayerLooper playerLooperWithPlayer:loop.player templateItem:item];
        sLoops[file] = loop;
        // Unused ones beyond three go.
        if (sLoops.count > 3) {
            NSURL *oldest = nil;
            for (NSURL *key in sLoops) {
                FZRCoverLoop *other = sLoops[key];
                if (other.users == 0 && other != loop && (!oldest || other.used < sLoops[oldest].used)) oldest = key;
            }
            if (oldest) { [sLoops[oldest].player pause]; [sLoops removeObjectForKey:oldest]; }
        }
    }
    loop.used = CACurrentMediaTime();
    return loop;
}

static UIImage *posterImage(NSURL *file) {
    static NSCache<NSURL *, UIImage *> *posters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ posters = [NSCache new]; posters.countLimit = 12; });
    UIImage *image = [posters objectForKey:file];
    if (!image) {
        image = [UIImage imageWithContentsOfFile:posterFileFor(file).path];
        if (image) [posters setObject:image forKey:file];
    }
    return image;
}

#pragma mark - the view

@implementation FZRAnimatedCoverView {
    FZRCoverLoop *_loop;
    AVPlayerLayer *_layer;
    UIImageView *_poster;
    BOOL _visible;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    self.alpha = 0;
    // The first frame, shown at once while the video gets going underneath (it then plays over it).
    _poster = [[UIImageView alloc] initWithFrame:self.bounds];
    _poster.contentMode = UIViewContentModeScaleAspectFill;
    _poster.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_poster];
    _layer = [AVPlayerLayer layer];
    _layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.layer addSublayer:_layer];
    [_layer addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionNew context:NULL];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    [_layer removeObserver:self forKeyPath:@"readyForDisplay"];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self release:_loop];
}

- (void)release:(FZRCoverLoop *)loop {
    if (!loop) return;
    loop.users = MAX(0, loop.users - 1);
    if (loop.users == 0) [loop.player pause];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _layer.frame = self.bounds;
    [CATransaction commit];
}

- (BOOL)showing { return _file != nil && (_layer.readyForDisplay || _poster.image); }

- (void)playFile:(NSURL *)file {
    if (!file) { [self stop]; return; }
    if ([file isEqual:_file]) { [self resume]; return; }
    [self release:_loop];
    _file = [file copy];
    _loop = loopFor(file);
    _loop.users++;
    _poster.image = posterImage(file);
    _layer.player = _loop.player;
    [self.layer removeAllAnimations];
    // With its first frame there's nothing to wait for: the cover shows at once.
    if (_poster.image || _layer.readyForDisplay) self.alpha = 1;
    [self resume];
}

- (void)resume {
    if (_loop && self.window) [_loop.player play];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self resume];
    else if (_loop.users <= 1) [_loop.player pause];
}

- (void)stop {
    _file = nil;
    [self release:_loop];
    _loop = nil;
    _layer.player = nil;
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; } completion:^(BOOL finished) {
        if (!self->_file) self->_poster.image = nil;
    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_layer.readyForDisplay && self->_file && self.alpha < 1) [UIView animateWithDuration:0.25 animations:^{ self.alpha = 1; }];
    });
}
@end

#pragma mark - settings section

static void askForFolder(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Animated covers"
        message:@"The folder holding your covers as \"Artist - Album.mp4\", on a WebDAV or web server. A user name and password only if the server asks for them."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://server/covers/";
        field.text = [[FZSettings defaults] stringForKey:FZRKeyAnimatedCoversURL];
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"User name (optional)";
        field.text = [[FZSettings defaults] stringForKey:FZRKeyAnimatedCoversUser];
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = storedPassword() ? @"Password (kept; type to change)" : @"Password (optional)";
        field.secureTextEntry = YES;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSArray<UITextField *> *fields = weakAlert.textFields;
        NSString *url = [fields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [[FZSettings defaults] setObject:url ?: @"" forKey:FZRKeyAnimatedCoversURL];
        [[FZSettings defaults] setObject:fields[1].text ?: @"" forKey:FZRKeyAnimatedCoversUser];
        if (fields[2].text.length) storePassword(fields[2].text);
        if (!fields[1].text.length) storePassword(nil);
        forgetList();
        listFolder(YES, ^(NSDictionary *files) {});
    }]];
    if (FZRAnimatedCoversConfigured()) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Turn Off" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[FZSettings defaults] setObject:@"" forKey:FZRKeyAnimatedCoversURL];
            forgetList();
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [FZTopController() presentViewController:alert animated:YES completion:nil];
}

FZModSection *FZRAnimatedCoversSection(void) {
    FZModRow *folder = FZWithSymbol(FZStatActionRow(@"Covers folder", @"WebDAV or web server, \"Artist - Album.mp4\"", ^NSString *{
        NSString *address = folderAddress();
        return address ? ([NSURL URLWithString:address].host ?: @"Set") : @"Off";
    }, ^{ askForFolder(); }), @"play.rectangle");
    FZModRow *found = FZWithSymbol(FZStatActionRow(@"Covers found", @"Tap to look again", ^NSString *{
        if (!FZRAnimatedCoversConfigured()) return @"–";
        return sList ? [NSString stringWithFormat:@"%lu", (unsigned long)sList.count] : @"…";
    }, ^{ forgetList(); listFolder(YES, ^(NSDictionary *files) {}); }), @"arrow.clockwise");
    FZModRow *kept = FZWithSymbol(FZStatActionRow(@"Albums on their still cover", @"Tap to animate them all again", ^NSString *{
        return [NSString stringWithFormat:@"%lu", (unsigned long)[[FZSettings defaults] arrayForKey:kOffKey].count];
    }, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Animate every album again?"
            message:@"Albums you set to their still cover in the player go back to their animated cover." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Animate Again" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[FZSettings defaults] removeObjectForKey:kOffKey];
            [NSNotificationCenter.defaultCenter postNotificationName:FZRAnimatedCoversDidChangeNotification object:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [FZTopController() presentViewController:alert animated:YES completion:nil];
    }), @"photo");
    if (FZRAnimatedCoversConfigured() && !sList) listFolder(NO, ^(NSDictionary *files) {});
    return FZNotedSection(@"Animated covers", @[folder, found, kept],
                          @"An album's video is shown in place of its cover wherever one matches, in the player and on the album page. Videos are downloaded once and kept in the caches.");
}
