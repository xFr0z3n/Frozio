// Blocked artists: a song by a blocked artist is skipped as it starts. Adapted from
// taurus/tweak/Sources/Shared/ArtistBlock/ (GPL-3.0) @ fe3211c.
//
// NaviMus has no artist IDs in reach, so artists are matched by name, as NaviMus reports them in the
// system Now Playing info (MPMediaItemPropertyArtist): case- and accent-insensitive, the whole credit
// or one of the names in it ("A feat. B", "A & B", "A, B").
//
// The skip is NaviMus's own: the handler NaviMus registers on MPRemoteCommandCenter's nextTrackCommand
// (the lock screen's Next button) is kept as it registers and called once per blocked song. No NaviMus symbols.
#pragma once
#import <UIKit/UIKit.h>

extern NSString *const FZKeyArtistBlock;           // "fz.artistBlock": the switch, off until switched on
extern NSString *const FZKeyArtistBlockFeatured;   // "fz.artistBlock.featured": off = the main artist only
extern NSString *const FZKeyArtistBlockList;       // "fz.artistBlock.list": NSArray<NSString *> of names

NSArray<NSString *> *FZBlockedArtists(void);
void FZBlockArtist(NSString *name);
void FZUnblockArtist(NSString *name);
BOOL FZArtistBlocked(NSString *name);

/// The names in an artist credit, the main one first ("A feat. B & C" → A, B, C). Never empty for a
/// non-empty credit; a credit that doesn't split is itself.
NSArray<NSString *> *FZArtistsInCredit(NSString *credit);
/// The artist credit of what NaviMus is playing, nil before it has reported one.
NSString *FZPlayingArtistCredit(void);

/// Hooks -[MPRemoteCommand addTargetWithHandler:] and -[MPNowPlayingInfoCenter setNowPlayingInfo:]
/// (system classes, ObjC runtime only). Call before NaviMus's main() so its handler is seen.
void FZInstallArtistBlock(void);

UIViewController *FZArtistBlockPage(void);
