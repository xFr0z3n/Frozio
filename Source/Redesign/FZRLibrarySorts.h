// More sort options in NaviMus's Library (the user's request, build 40): NaviMus's Albums sort menu offers Name,
// Artist, Recently Added, Frequently Played, Recently Played and Random, though its own list type
// (Arpeggi.SubsonicAPI.AlbumListType, kept with @AppStorage) also has byYear and starred. Frozio adds Year (newest
// first, oldest first) and Favourites to that menu; choosing one sets NaviMus's own stored sort, so NaviMus loads and
// shows the list itself. The storage key is learned from NaviMus's own writes (it's not "albumType", build 41). getAlbumList2's byYear needs a year range, which Frozio adds to NaviMus's
// request when it has none (fromYear > toYear sorts newest first, per the Subsonic API).
#pragma once
#import <Foundation/Foundation.h>

extern NSString *const FZKeyLibrarySorts;   // "fz.library.sorts": the extra sort options (on)

/// Installs the menu and request hooks. Call before NaviMus's main().
void FZInstallLibrarySorts(void);
