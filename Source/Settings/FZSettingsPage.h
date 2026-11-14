// Frozio's own settings, in spoti.pw's redesign settings style (kit adapted from taurus).
#pragma once
#import <UIKit/UIKit.h>

/// Builds the root Frozio settings page.
UIViewController *FZMakeSettingsPage(void);
/// Presents Frozio settings from `owner`, in its own dark navigation controller.
void FZPresentSettings(UIViewController *owner);
/// The Frozio logo from Frozio.bundle (nil if the bundle wasn't copied into the app).
UIImage *FZLogoImage(void);
