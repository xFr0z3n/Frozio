// FZPausedStatus: tells the server "stopped" after a song has been paused for a while (see FZPausedStatus.m).
#pragma once
#import <Foundation/Foundation.h>

extern NSString *const FZKeyPausedStatus;          // "fz.playback.pausedStatusClear": index into the choices, default 2
NSArray<NSString *> *FZPausedStatusChoices(void);  // Never, 1, 2, 5, 10 minutes

/// Hooks task -resume to watch NaviMus's reportPlayback. Reads its setting live.
void FZInstallPausedStatus(void);
