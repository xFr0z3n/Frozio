// FZServer: the redesign's access to the user's Navidrome/OpenSubsonic server, through NaviMus's own login.
//
// NaviMus's library store is a partial cache (docs/FEATURES.md, R0b), so rebuilt pages also ask the server.
// Frozio doesn't read NaviMus's keychain: it reuses the server address and the auth query parameters
// (u, t, s, v, c, or apiKey) of the /rest/ requests NaviMus itself sends, seen at system seams:
// -[NSURLSession dataTaskWithRequest:(completionHandler:)], -[NSURLSession dataTaskWithURL:(completionHandler:)],
// -[AVURLAsset initWithURL:options:], and -resume on the session task class (Swift async requests). They're kept in memory only and never logged or stored.
#pragma once
#import <UIKit/UIKit.h>

extern NSNotificationName const FZServerReadyNotification;   // the first time NaviMus's login is seen

/// YES once a NaviMus request has shown the server and its auth parameters.
BOOL FZServerReady(void);

/// GET /rest/<endpoint>.view with NaviMus's auth and f=json. `completion` runs on the main thread with the
/// "subsonic-response" object (status ok) or an error.
void FZServerGet(NSString *endpoint, NSDictionary<NSString *, NSString *> *parameters,
                 void (^completion)(NSDictionary *response, NSError *error));

/// The URL of a cover (getCoverArt) at `size` pixels, nil before the server is known.
NSURL *FZServerCoverURL(NSString *coverArtID, NSInteger size);

/// Loads an image (cached in memory). Main-thread completion, nil on failure.
void FZServerImage(NSURL *url, void (^completion)(UIImage *image));

/// Installs the hooks that see NaviMus's requests. Call before NaviMus's main().
void FZInstallServer(void);
