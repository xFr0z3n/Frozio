// FZRemote: NaviMus's player as the system sees it, for every Frozio feature that follows or drives it.
//
// - Commands: the handlers NaviMus registers on MPRemoteCommandCenter (play, pause, toggle, next, previous,
//   change position, shuffle, repeat, …) are kept as they register (-[MPRemoteCommand addTargetWithHandler:]),
//   and FZRemoteSend runs NaviMus's handler with an event like the system's, exactly as the lock screen's
//   buttons do. Verified on device for next-track (blocked artists, build 28).
// - Now Playing: NaviMus's own info as it sets it (-[MPNowPlayingInfoCenter setNowPlayingInfo:], hooked
//   after lock screen lyrics so its re-sends with a lyric line aren't seen), posted on the main thread.
// Public MediaPlayer API only, no NaviMus symbols.
#pragma once
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>

/// Main thread, after NaviMus sets its Now Playing info.
extern NSNotificationName const FZNowPlayingDidChangeNotification;

NSDictionary *FZNowPlayingInfo(void);     // NaviMus's latest info, main thread; nil before any
NSString *FZNowPlayingSongID(void);       // its ExternalContentIdentifier (NaviMus's song ID)
BOOL FZNowPlayingIsPlaying(void);         // reported rate above 0
NSTimeInterval FZNowPlayingElapsed(void); // seconds into the song now: the reported time, run on at the rate
NSTimeInterval FZNowPlayingDuration(void);// seconds, 0 when unknown
UIImage *FZNowPlayingArtwork(CGSize size);// the artwork NaviMus hands the system, nil without one

/// Whether NaviMus has a handler for `command`.
BOOL FZRemoteHandles(MPRemoteCommand *command);

/// Seeks with NaviMus's change-position handler, as the lock screen's scrubber does.
BOOL FZRemoteSeek(NSTimeInterval seconds);

/// Runs NaviMus's handler for `command` (e.g. MPRemoteCommandCenter.sharedCommandCenter.togglePlayPauseCommand).
/// NO when NaviMus has no handler for it or the event can't be made.
BOOL FZRemoteSend(MPRemoteCommand *command);

/// The same with the event's MediaRemote options (e.g. a shuffle or repeat mode).
BOOL FZRemoteSendWithOptions(MPRemoteCommand *command, NSDictionary *options);

/// An event for `command` with `options`, as the system would send it (nil if it can't be made). For tests.
MPRemoteCommandEvent *FZRemoteEvent(MPRemoteCommand *command, NSDictionary *options);

/// Installs both hooks. Call before NaviMus's main(), after FZInstallLockScreenLyrics.
void FZInstallRemote(void);
