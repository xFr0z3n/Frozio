// NaviMus's play queue, for Frozio's player (the user's request, build 42: the queue in Frozio's own player, as
// NaviMus shows it, rather than opening NaviMus's player). Read from NaviMus's AudioManager (an NSObject, kept from
// its own -handleItemChanged / -updateCurrentRoute / -playerDidFinishPlaying: as they run) by Swift reflection
// (FZNaviMus.queue), never changed: a song is chosen with NaviMus's own next-track handler.
#pragma once
#import <Foundation/Foundation.h>

extern NSNotificationName const FZRQueueDidChangeNotification;

/// Keys: "current" (a song), "next" (NaviMus's primary queue: what was added), "context" (its secondary queue: the
/// rest of the album or playlist), "autoplay" (its continuous queue), "history"; each song a dictionary of id, title,
/// artist, album, coverArt, albumId, artistId, duration. nil before NaviMus's AudioManager has been seen.
NSDictionary<NSString *, id> *FZRNaviMusQueue(void);

/// Installs the hooks that find NaviMus's AudioManager. Call before NaviMus's main().
void FZRInstallQueue(void);
