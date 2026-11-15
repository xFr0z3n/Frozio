// Synced lyrics for Frozio's player, for every song rather than only those NaviMus has already saved.
// Automatic asks, in order: NaviMus's own saved lyrics (FZNaviMusSyncedLyrics), the user's server (OpenSubsonic
// getLyricsBySongId), then taurus's sources (Source/Lyrics/Taurus, GPL-3.0) in taurus's order — BiniLyrics,
// Musixmatch, Unison, NetEase, LRCLIB, QQ Music, KuGou — and the first with timed lines answers. Each song can
// instead keep one source of the user's choosing (the player's ⋯ → Lyrics Source), kept for good, as taurus
// keeps its per-track choice; "Imported LRC" is an .lrc file the user picked for that song.
// Only the song's title, artist, album and length are sent to the online sources.
#pragma once
#import <Foundation/Foundation.h>
#import "Lyrics/FZNaviMusLyrics.h"

extern NSString *const FZKeyLyricsLRCLIB;   // "fz.lyrics.lrclib": ask the online sources in Automatic (on)
extern NSString *const FZRLyricsAutomatic;  // "automatic"
extern NSString *const FZRLyricsImported;   // "imported"
extern NSNotificationName const FZRLyricsSourceDidChangeNotification;   // object: the song's ID

/// Every choice, in menu order: @[@[key, name], …], Automatic first.
NSArray<NSArray<NSString *> *> *FZRLyricsSources(void);
/// The song's chosen source, FZRLyricsAutomatic when none was chosen.
NSString *FZRLyricsSourceForSong(NSString *songID);
/// Keeps the choice for good (Automatic forgets it) and drops what was found before, so the next fetch asks it.
void FZRSetLyricsSourceForSong(NSString *songID, NSString *key);
/// Saves an .lrc file's text as the song's imported lyrics and chooses it. NO when it has no timed line.
BOOL FZRImportLRC(NSString *songID, NSString *lrc);

/// The lyrics already known for `songID` from its chosen source, nil otherwise.
FZSyncedLyrics *FZRKnownLyrics(NSString *songID);
/// Finds lyrics for the playing song described by `info` (Now Playing) and `songID`; completion on the main thread.
void FZRFetchLyrics(NSString *songID, NSDictionary *info, void (^completion)(FZSyncedLyrics *lyrics));
/// Parses LRC text ("[mm:ss.xx] line"), nil without timed lines. Exposed for the harness.
FZSyncedLyrics *FZRLyricsFromLRC(NSString *lrc, NSString *songID, NSString *source);
