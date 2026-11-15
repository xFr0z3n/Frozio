// Synced lyrics for Frozio's player, so they show for every song rather than only those NaviMus has already saved
// (the user, build 44: "No synced lyrics yet" too often). Asked in order: NaviMus's own saved lyrics
// (FZNaviMusSyncedLyrics), the user's server (OpenSubsonic getLyricsBySongId, Navidrome 0.53+), then LRCLIB
// (lrclib.net, the service NaviMus itself uses: only the song's title, artist, album and length are sent).
// Results are kept in memory for the session.
#pragma once
#import <Foundation/Foundation.h>
#import "Lyrics/FZNaviMusLyrics.h"

extern NSString *const FZKeyLyricsLRCLIB;   // "fz.lyrics.lrclib": ask LRCLIB when NaviMus and the server have none (on)

/// The lyrics already known for `songID` (saved by NaviMus or fetched before), nil otherwise.
FZSyncedLyrics *FZRKnownLyrics(NSString *songID);
/// Finds lyrics for the playing song described by `info` (Now Playing) and `songID`; completion on the main thread.
void FZRFetchLyrics(NSString *songID, NSDictionary *info, void (^completion)(FZSyncedLyrics *lyrics));
/// Parses LRC text ("[mm:ss.xx] line"), nil without timed lines. Exposed for the harness.
FZSyncedLyrics *FZRLyricsFromLRC(NSString *lrc, NSString *songID, NSString *source);
