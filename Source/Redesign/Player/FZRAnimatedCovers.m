// See FZRAnimatedCovers.h.
#import <AVFoundation/AVFoundation.h>
#import <Security/Security.h>
#import "Redesign/Player/FZRAnimatedCovers.h"
#import "Settings/Kit/FZKitCore.h"
#import "Settings/Kit/FZModPage.h"
#import "Settings/Kit/FZPageStyle.h"
#import "Prefs/FZSettings.h"
#import "Core/FZLog.h"

NSString *const FZRKeyAnimatedCoversURL = @"fz.animatedCovers.url";
NSString *const FZRKeyAnimatedCoversUser = @"fz.animatedCovers.user";
NSNotificationName const FZRAnimatedCoversDidChangeNotification = @"FZRAnimatedCoversDidChangeNotification";
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

static NSURL *cacheFolder(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [caches URLByAppendingPathComponent:@"Frozio/AnimatedCovers" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return folder;
}

static NSURL *cachedFileFor(NSURL *remote) {
    NSString *safe = [[remote.absoluteString componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@"_"];
    if (safe.length > 180) safe = [safe substringFromIndex:safe.length - 180];
    return [cacheFolder() URLByAppendingPathComponent:[safe stringByAppendingPathExtension:@"mp4"]];
}

static NSMutableDictionary<NSURL *, NSMutableArray *> *sDownloads;
static NSMutableDictionary<NSString *, id> *sMatches;   // "artist|album" → file name or NSNull

void FZRAnimatedCoverFor(NSString *artist, NSString *album, void (^completion)(NSURL *file)) {
    if (!FZRAnimatedCoversConfigured() || !album.length) { completion(nil); return; }
    listFolder(NO, ^(NSDictionary<NSString *, NSURL *> *files) {
        NSString *key = [NSString stringWithFormat:@"%@|%@", artist ?: @"", album];
        if (!sMatches) sMatches = [NSMutableDictionary dictionary];
        id known = sMatches[key];
        NSString *name = [known isKindOfClass:NSString.class] ? known : nil;
        if (!known) {
            name = FZRAnimatedCoverMatch(files.allKeys, artist ?: @"", album);
            sMatches[key] = name ?: NSNull.null;
            FZLog("animated covers: %@ by %@ → %@", album, artist, name ?: @"none");
        }
        NSURL *remote = name ? files[name] : nil;
        if (!remote) { completion(nil); return; }
        NSURL *local = cachedFileFor(remote);
        if ([NSFileManager.defaultManager fileExistsAtPath:local.path]) { completion(local); return; }
        if (!sDownloads) sDownloads = [NSMutableDictionary dictionary];
        if (sDownloads[remote]) { [sDownloads[remote] addObject:[completion copy]]; return; }
        sDownloads[remote] = [NSMutableArray arrayWithObject:[completion copy]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:remote];
        request.timeoutInterval = 60;
        authorize(request);
        [[NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *temp, NSURLResponse *response, NSError *error) {
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            BOOL ok = temp && status >= 200 && status < 300;
            if (ok) {
                [NSFileManager.defaultManager removeItemAtURL:local error:nil];
                ok = [NSFileManager.defaultManager moveItemAtURL:temp toURL:local error:nil];
            }
            if (!ok) FZLogError("animated covers: %@ didn't download (%ld, %@)", name, (long)status, error.localizedDescription ?: @"-");
            dispatch_async(dispatch_get_main_queue(), ^{
                NSArray *waiting = sDownloads[remote];
                [sDownloads removeObjectForKey:remote];
                for (void (^done)(NSURL *) in waiting) done(ok ? local : nil);
            });
        }] resume];
    });
}

static void forgetList(void) {
    sList = nil;
    sListedAt = nil;
    [sMatches removeAllObjects];
    [NSNotificationCenter.defaultCenter postNotificationName:FZRAnimatedCoversDidChangeNotification object:nil];
}

#pragma mark - the view

@implementation FZRAnimatedCoverView {
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    AVPlayerLayer *_layer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    self.alpha = 0;
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
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _layer.frame = self.bounds;
    [CATransaction commit];
}

- (BOOL)showing { return _file != nil && _layer.readyForDisplay; }

- (void)playFile:(NSURL *)file {
    if (!file || [file isEqual:_file]) { [self resume]; return; }
    _file = [file copy];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:file];
    _player = [AVQueuePlayer queuePlayerWithItems:@[]];
    _player.muted = YES;
    _player.preventsDisplaySleepDuringVideoPlayback = NO;
    _player.allowsExternalPlayback = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:_player templateItem:item];
    _layer.player = _player;
    [_player play];
}

- (void)resume { if (_player && self.window) [_player play]; }

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self resume]; else [_player pause];
}

- (void)stop {
    _file = nil;
    [_player pause];
    _looper = nil;
    _player = nil;
    _layer.player = nil;
    [UIView animateWithDuration:0.25 animations:^{ self.alpha = 0; }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_layer.readyForDisplay && self->_file) [UIView animateWithDuration:0.45 animations:^{ self.alpha = 1; }];
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
    if (FZRAnimatedCoversConfigured() && !sList) listFolder(NO, ^(NSDictionary *files) {});
    return FZNotedSection(@"Animated covers", @[folder, found],
                          @"An album's video is shown in place of its cover wherever one matches, in the player and on the album page. Videos are downloaded once and kept in the caches.");
}
