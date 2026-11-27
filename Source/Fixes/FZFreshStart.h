// FZFreshStart: every launch starts on Home with every tab at its first page (see FZFreshStart.m).
#pragma once
#import <Foundation/Foundation.h>

extern NSString *const FZKeyFreshStart;   // "fz.freshStart": YES = don't restore the last tab and pages
/// Call from the constructor, before NaviMus's main() reads its saved state.
void FZApplyFreshStart(void);
