// Frozio's stand-in for taurus's Redesigned/Kit/SGRBridges.h (GPL-3.0): the player transition the moving
// field pauses for. Frozio has no player transition of its own yet (R3), so the field never waits for one.
#pragma once
#import <Foundation/Foundation.h>

static inline BOOL FZRPlayerIsTransitioning(void) { return NO; }
static inline void FZRObservePlayerTransition(id owner, void (^began)(id owner), void (^ended)(id owner)) {}
