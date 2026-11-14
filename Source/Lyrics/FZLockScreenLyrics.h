// Lock screen lyrics: the line being sung takes the artist's place in the system Now Playing info
// (lock screen, Control Center, CarPlay). Adapted from taurus/tweak/Sources/Shared/LockScreenLyrics/
// LockScreenLyrics.x @ fe3211c (GPL-3.0).
//
// NaviMus's info passes through -[MPNowPlayingInfoCenter setNowPlayingInfo:] with the artist swapped,
// and a timer sends it again each time the line changes. NaviMus only ever reads its own dictionary back.
// The song is NaviMus's MPNowPlayingInfoPropertyExternalContentIdentifier (set at 0x100297bb4 in 1.6.1),
// matched against the songID inside NaviMus's saved lyrics (FZNaviMusLyrics.h).
#pragma once

/// Hooks MPNowPlayingInfoCenter (system class, ObjC runtime only). Fail-safe: on any mismatch it logs
/// and NaviMus's info goes out untouched. The switch (FZSettingsKeyLockScreenLyrics) is read live.
void FZInstallLockScreenLyrics(void);
