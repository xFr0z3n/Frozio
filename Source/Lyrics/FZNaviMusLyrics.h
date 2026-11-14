// Reads the synced lyrics NaviMus has already saved on the device. Frozio fetches nothing itself.
//
// Where NaviMus keeps them, verified in the 1.6.1 binary (otool disassembly, work/dumps/disasm.txt):
//   - the loader at 0x1008f46f4 logs "Lyrics folder not found" / "Could not load lyrics: " (domain "LyricsLoader")
//   - its folder helper 0x1008e9f80 takes NSApplicationSupportDirectory (0xe) and a folder case; the case
//     names at 0x1008e87e4 are Swift small strings: case 6 = "lyrics", case 5 = "database", all under
//     "Arpeggi/<database id>/"
//   - the file name is SHA-256("<songID>_<source>") (CryptoKit, 0x1008ebc6c) + ".json"
//   - the file is decoded with JSONDecoder (0x1008f522c) into Arpeggi.CachedLyrics, whose CodingKeys are
//     songID, lang, offset, synced, plainLyrics, syncedLines{start, value, …}, source, …
//     (work/dumps/swift_dump_demangled.txt:2592)
// Frozio doesn't recompute the hash: it reads each file once and indexes it by its own songID field.
#pragma once
#import <Foundation/Foundation.h>

@interface FZLyricLine : NSObject
@property (nonatomic, readonly) NSInteger start;   // ms into the track
@property (nonatomic, readonly, copy) NSString *text;
@end

@interface FZSyncedLyrics : NSObject
@property (nonatomic, readonly, copy) NSArray<FZLyricLine *> *lines;   // sorted by start, never empty
@property (nonatomic, readonly) NSInteger offset;                      // ms, as NaviMus stored it
@property (nonatomic, readonly, copy) NSString *source;                // "navidrome" or "lrclib"
@end

/// The synced lyrics NaviMus saved for `songID`, or nil when it has none (or only plain text).
/// Main thread. A miss starts a background rescan of the folder; ask again on a later tick.
FZSyncedLyrics *FZNaviMusSyncedLyrics(NSString *songID);

/// Parses one cache file's JSON. Exposed for the harness; nil unless it's synced CachedLyrics.
FZSyncedLyrics *FZSyncedLyricsFromJSON(NSData *data, NSString **songID);
