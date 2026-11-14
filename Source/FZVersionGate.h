// Version gate: Frozio installs hooks only into a NaviMus build it was verified against.
#pragma once
#import <Foundation/Foundation.h>

/// Evaluates the gate once (thread-safe) and logs the result once.
/// YES only when CFBundleShortVersionString, CFBundleVersion and the main
/// executable's LC_UUID all match an entry in the known-good list.
BOOL FZVersionGatePassed(void);
