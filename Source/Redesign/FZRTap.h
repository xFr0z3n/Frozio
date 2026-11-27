// FZRTap: a real tap at a point of a window, delivered through UIApplication's event path as a finger would.
//
// For NaviMus's controls that accessibility can't activate on iOS 17 (SwiftUI menus only open on a touch;
// device log, build 36), the same way VoiceOver falls back to tapping and UI-test frameworks (KIF, EarlGrey)
// tap on real devices: a UITouch with a digitizer HID event, began then ended, sent with -[UIApplication sendEvent:].
// Private UIKit selectors and IOKit functions, each looked up at run time; if any is missing, nothing is sent
// and NO is returned.
#pragma once
#import <UIKit/UIKit.h>

/// Taps `point` (window coordinates) in `window`. Synchronous: the touch has ended when it returns.
BOOL FZRTap(UIWindow *window, CGPoint point);
/// The same, the finger lifted `hold` seconds later (on a later turn of the run loop), as a person taps.
BOOL FZRTapHeld(UIWindow *window, CGPoint point, NSTimeInterval hold);

/// The same, aimed at what `root` has at `point` (window coordinates), whatever lies over it in the window (a
/// view controller presented over the app).
BOOL FZRTapIn(UIView *root, CGPoint point);

/// A finger drag from `from` to `to` (window coordinates) over `duration` seconds; returns at once, the moves
/// and the lift follow on the main queue.
BOOL FZRDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval duration);
