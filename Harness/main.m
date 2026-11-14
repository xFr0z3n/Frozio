// FrozioHarness: a Simulator-only host app for Frozio's UI (settings pages, redesign kit).
//
// NaviMus is an arm64 device binary, so it can't run in the Simulator on this Mac. The harness
// compiles Frozio's own sources for the Simulator and stands in for NaviMus's Settings tab: a
// dark navigation stack titled "Settings", with the Frozio entry button top-right as on device.
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

@interface FZHarnessSettingsStandIn : UIViewController
@end

@implementation FZHarnessSettingsStandIn
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:FZLogoImage() ?: [UIImage systemImageNamed:@"snowflake"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openFrozio)];

    UILabel *note = [UILabel new];
    note.translatesAutoresizingMaskIntoConstraints = NO;
    note.numberOfLines = 0;
    note.textAlignment = NSTextAlignmentCenter;
    note.textColor = UIColor.secondaryLabelColor;
    note.text = @"Stand-in for NaviMus's Settings tab.\nTap the Frozio button top-right.";
    [self.view addSubview:note];
    [NSLayoutConstraint activateConstraints:@[
        [note.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [note.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [note.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-48],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    static BOOL opened;
    if (!opened && [NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessOpenSettings"]) {
        opened = YES;
        [self openFrozio];
    }
}

- (void)openFrozio {
    FZPresentSettings(self);
}
@end

@interface FZHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation FZHarnessDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    // Same order as Frozio.m, minus the version gate and every NaviMus hook.
    [FZSettings registerDefaults];
    FZRegisterPages();
    FZInstallLockScreenLyrics();   // a pass-through system hook, safe outside NaviMus
    FZInstallArtistBlock();
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FZHarnessLyricsDemo"]) startLyricsDemo();

    UITabBarController *tabs = [UITabBarController new];
    UINavigationController *settings =
        [[UINavigationController alloc] initWithRootViewController:[FZHarnessSettingsStandIn new]];
    settings.navigationBar.prefersLargeTitles = YES;
    settings.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
                                                        image:[UIImage systemImageNamed:@"gear"]
                                                          tag:0];
    tabs.viewControllers = @[settings];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(FZHarnessDelegate.class));
    }
}
