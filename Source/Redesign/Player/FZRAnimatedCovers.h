// Animated covers from the user's own server: a folder on a WebDAV or plain HTTP server holding one video per
// album, named "Artist - Album.mp4" (the user's dumped Apple Music motion artwork). Frozio lists the folder (WebDAV
// PROPFIND, else the server's HTML index), matches an album to a file loosely — case, accents, punctuation,
// "(Deluxe)"-style brackets and featured artists don't count, and the file's album may be the start of the album's
// name ("Yeat - 2093.mp4" is "2093 (Unreleased)") — downloads the file once into the caches and loops it, muted,
// in place of the still cover wherever one is found (the player and the album page; the player's Artwork → Auto,
// the default).
//
// Frozio settings → Appearance → Redesigned pages → Animated covers: the folder's address, and a user name and
// password when the server asks for them (the password kept in the Keychain, never in exported settings).
#pragma once
#import <UIKit/UIKit.h>

extern NSString *const FZRKeyAnimatedCoversURL;    // "fz.animatedCovers.url": the folder, "" = off
extern NSString *const FZRKeyAnimatedCoversUser;   // "fz.animatedCovers.user"
extern NSNotificationName const FZRAnimatedCoversDidChangeNotification;   // the folder or its list changed

BOOL FZRAnimatedCoversConfigured(void);
/// The file name a cover would match, without fetching anything ("Yeat - 2093.mp4"), nil for none. Exposed for tests.
NSString *FZRAnimatedCoverMatch(NSArray<NSString *> *fileNames, NSString *artist, NSString *album);
/// Albums the user keeps on their still cover (the player's ⋯ → Artwork), kept for good, by album title.
BOOL FZRAnimatedCoverOff(NSString *album);
void FZRSetAnimatedCoverOff(NSString *album, BOOL off);
/// The album's animated cover as a local file, downloading it the first time; nil when there is none. Main thread.
void FZRAnimatedCoverFor(NSString *artist, NSString *album, void (^completion)(NSURL *file));

/// Loops a cover video, muted, filling its bounds; fades in once its first frame shows.
@interface FZRAnimatedCoverView : UIView
@property (nonatomic, readonly, copy) NSURL *file;
@property (nonatomic, readonly) BOOL showing;   // a video is playing in it
- (void)playFile:(NSURL *)file;
- (void)stop;
@end

@class FZModSection;
FZModSection *FZRAnimatedCoversSection(void);
