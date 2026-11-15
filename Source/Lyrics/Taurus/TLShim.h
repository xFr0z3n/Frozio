// What taurus's lyrics sources (Source/Lyrics/Taurus, GPL-3.0) expect of taurus's core, for Frozio. NaviMus's songs
// have no Spotify id, so every song is asked as taurus asks a local file: by its title, artist, album and length,
// which Frozio registers before it asks (TLNoteSong). Musixmatch's translations and BiniLyrics' ISRC lookup were
// Spotify's and are left out.
#pragma once
#import <UIKit/UIKit.h>
#import "Core/FZLog.h"
#import "Settings/Kit/FZKitCore.h"

#define SGLog(fmt, ...) FZLog("lyrics source: %@", [NSString stringWithFormat:fmt, ##__VA_ARGS__])
static inline NSInteger SGInt(NSString *key, NSInteger fallback) { return FZInt(key, fallback); }

/// Frozio's songs are all "local files" to taurus's sources: matched by name, never by a Spotify id.
void TLNoteSong(NSString *songID, NSString *title, NSString *artist, NSString *album, NSInteger seconds);
BOOL SGLocalFileIs(NSString *trackID);
NSDictionary *SGLocalFileInfo(NSString *trackID);
static inline void SGSpotifyISRC(NSString *uri, NSInteger attempt, void (^done)(NSString *isrc)) { done(nil); }
