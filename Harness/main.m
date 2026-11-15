// FrozioHarness: a Simulator-only host app for Frozio's UI (settings pages, redesign kit).
//
// NaviMus is an arm64 device binary, so it can't run in the Simulator on this Mac. The harness
// compiles Frozio's own sources for the Simulator around a SwiftUI stand-in for NaviMus's screens
// (NaviMusStandIn.swift), so the redesign and the Frozio entry button land on what SwiftUI really builds.
// Frozio.m (the constructor and version gate) is not linked; only the system-class hooks that are safe
// outside NaviMus (Now Playing, remote commands) are installed, as Frozio.m would.
//
// Launch argument -FZHarnessOpenSettings YES (the default for `make run`) opens Frozio settings
// straight away, so a rebuild lands on the page being worked on.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "Prefs/FZSettings.h"
#import "Settings/FZSettingsPage.h"
#import "Settings/Kit/FZPage.h"
#import "Lyrics/FZLockScreenLyrics.h"
#import "ArtistBlock/FZArtistBlock.h"
#import "Core/FZRemote.h"
#import "Redesign/Player/FZRPlayer.h"
#import "Redesign/FZRLibrarySorts.h"
void FZInstallCoverReuseFix(void);
#import "Settings/FZSettingsEntry.h"
#import "Redesign/FZRAppLook.h"
#import "Diagnostics/FZScreenCensus.h"
#import "Redesign/FZRNaviMusControls.h"
#import "Redesign/Data/FZServer.h"

#pragma mark - lyrics demo

// -FZHarnessLyricsDemo YES stands in for NaviMus playing a song: a lyrics file where NaviMus saves them
// (Application Support/Arpeggi/<db>/lyrics/, CachedLyrics JSON), silent audio so the lock screen shows
// Now Playing, and Now Playing info set the way NaviMus sets it (song ID in ExternalContentIdentifier).
// The lines are the harness's own text, timed every few seconds.
static NSString *const kDemoSongID = @"harness-song";
static AVAudioPlayer *sDemoPlayer;

static void writeDemoLyrics(void) {
    NSArray *texts = @[@"First line of the harness song", @"Second line comes in on time",
                       @"A much longer third line that has to be split into pieces for the lock screen",
                       @"", @"Back after a short break", @"Last line of the demo"];
    NSMutableArray *lines = [NSMutableArray array];
    NSInteger start = 1000;
    for (NSString *text in texts) {
        [lines addObject:@{@"start": @(start), @"value": text}];
        start += text.length ? 4000 : 6000;
    }
    NSDictionary *file = @{@"songID": kDemoSongID, @"offset": @0, @"synced": @YES, @"source": @"navidrome",
                           @"syncedLines": lines, @"formatVersion": @1};
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [support URLByAppendingPathComponent:@"Arpeggi/harness-db/lyrics" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:0 error:nil];
    [data writeToURL:[folder URLByAppendingPathComponent:@"demo.json"] atomically:YES];
}

// One second of 16-bit mono silence as a WAV, looped.
static NSData *silentWAV(void) {
    uint32_t rate = 8000, samples = rate, bytes = samples * 2;
    NSMutableData *d = [NSMutableData data];
    uint32_t u32; uint16_t u16;
    [d appendBytes:"RIFF" length:4]; u32 = 36 + bytes; [d appendBytes:&u32 length:4];
    [d appendBytes:"WAVEfmt " length:8]; u32 = 16; [d appendBytes:&u32 length:4];
    u16 = 1; [d appendBytes:&u16 length:2]; [d appendBytes:&u16 length:2];   // PCM, mono
    [d appendBytes:&rate length:4]; u32 = rate * 2; [d appendBytes:&u32 length:4];
    u16 = 2; [d appendBytes:&u16 length:2]; u16 = 16; [d appendBytes:&u16 length:2];
    [d appendBytes:"data" length:4]; [d appendBytes:&bytes length:4];
    [d increaseLengthBy:bytes];
    return d;
}

static void startLyricsDemo(void) {
    writeDemoLyrics();
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    sDemoPlayer = [[AVAudioPlayer alloc] initWithData:silentWAV() error:nil];
    sDemoPlayer.numberOfLoops = -1;
    [sDemoPlayer play];
    MPRemoteCommandCenter *commands = MPRemoteCommandCenter.sharedCommandCenter;
    [commands.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { return MPRemoteCommandHandlerStatusSuccess; }];
    [commands.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { return MPRemoteCommandHandlerStatusSuccess; }];
    // A queue, and ⏭ moving through it the way NaviMus's handler does, so artist block can skip.
    // -FZHarnessDemoStart <n> starts at song n.
    static NSArray<NSArray<NSString *> *> *queue;
    static NSInteger playing;
    queue = @[@[kDemoSongID, @"Harness Song", @"Harness Artist"],
              @[@"harness-2", @"Second Song", @"Blocked Band feat. Guest Singer"],
              @[@"harness-3", @"Third Song", @"Guest Singer & Harness Artist"],
              @[@"harness-4", @"Fourth Song", @"Harness Artist"]];
    void (^play)(NSInteger) = ^(NSInteger index) {
        playing = index % (NSInteger)queue.count;
        NSArray<NSString *> *song = queue[(NSUInteger)playing];
        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = @{
            MPMediaItemPropertyTitle: song[1],
            MPMediaItemPropertyArtist: song[2],
            MPMediaItemPropertyAlbumTitle: @"Frozio Harness",
            MPMediaItemPropertyPlaybackDuration: @40,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: @0,
            MPNowPlayingInfoPropertyPlaybackRate: @1,
            MPNowPlayingInfoPropertyExternalContentIdentifier: song[0],
        };
        NSLog(@"[harness] now playing %@ by %@", song[1], song[2]);
    };
    [commands.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        play(playing + 1);
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    play([NSUserDefaults.standardUserDefaults integerForKey:@"FZHarnessDemoStart"]);
}

@interface FZHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation FZHarnessDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    // Same order as Frozio.m, minus the version gate and the hooks that need NaviMus itself.
    [FZSettings registerDefaults];
    FZRInstallAppLook();
    if (FZRRedesignActive()) {
        FZInstallServer();
        FZRInstallPages();
        FZRInstallPlayer();
    }
    FZRegisterPages();
    FZInstallSettingsEntry();      // finds the stand-in's "Settings" stack exactly as it finds NaviMus's
    FZInstallLockScreenLyrics();   // a pass-through system hook, safe outside NaviMus
    FZInstallRemote();
    FZInstallArtistBlock();
    FZInstallLibrarySorts();
    FZInstallCoverReuseFix();
    FZInstallScreenCensus();       // debug census + Swift probe, as in a debug device build
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessLyricsDemo"]) startLyricsDemo();
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessShuffleProbe"]) {
        // Which MediaRemote option makes a shuffle event read "items" (MPShuffleTypeItems = 1).
        MPRemoteCommand *shuffle = MPRemoteCommandCenter.sharedCommandCenter.changeShuffleModeCommand;
        MPRemoteCommand *repeatCommand = MPRemoteCommandCenter.sharedCommandCenter.changeRepeatModeCommand;
        for (NSNumber *value in @[@0, @1, @2, @3]) {
            MPChangeRepeatModeCommandEvent *e = (MPChangeRepeatModeCommandEvent *)FZRemoteEvent(repeatCommand, @{@"kMRMediaRemoteOptionRepeatMode": value});
            NSLog(@"[harness] repeat probe %@ → type %ld", value, [e respondsToSelector:@selector(repeatType)] ? (long)e.repeatType : -1L);
        }
        MPChangePlaybackPositionCommandEvent *seek = (MPChangePlaybackPositionCommandEvent *)FZRemoteEvent(
            MPRemoteCommandCenter.sharedCommandCenter.changePlaybackPositionCommand, @{@"kMRMediaRemoteOptionPlaybackPosition": @42.5});
        NSLog(@"[harness] position probe → %@ %.1f", NSStringFromClass(seek.class), [seek respondsToSelector:@selector(positionTime)] ? seek.positionTime : -1.0);
        for (NSString *key in @[@"kMRMediaRemoteOptionShuffleMode", @"shuffleMode"]) {
            for (NSNumber *value in @[@0, @1, @2, @3]) {
                MPChangeShuffleModeCommandEvent *e = (MPChangeShuffleModeCommandEvent *)FZRemoteEvent(shuffle, @{key: value});
                NSLog(@"[harness] shuffle probe %@=%@ → %@ type %ld", key, value, NSStringFromClass(e.class),
                      [e respondsToSelector:@selector(shuffleType)] ? (long)e.shuffleType : -1L);
            }
        }
        MPRemoteCommand *repeat = MPRemoteCommandCenter.sharedCommandCenter.changeRepeatModeCommand;
        MPChangeRepeatModeCommandEvent *r = (MPChangeRepeatModeCommandEvent *)FZRemoteEvent(repeat, @{@"kMRMediaRemoteOptionRepeatMode": @3});
        NSLog(@"[harness] repeat probe → %@ type %ld", NSStringFromClass(r.class), [r respondsToSelector:@selector(repeatType)] ? (long)r.repeatType : -1L);
    }

    // NaviMus's shape in SwiftUI (NaviMusStandIn.swift).
    Class standIn = NSClassFromString(@"FZHarnessStandIn");
    UIViewController *root = [standIn respondsToSelector:@selector(makeRoot)] ? [standIn performSelector:@selector(makeRoot)] : nil;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = root ?: [UIViewController new];
    [self.window makeKeyAndVisible];

    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessOpenSettings"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            FZPresentSettings(self.window.rootViewController);
        });
    }
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(FZHarnessDelegate.class));
    }
}
