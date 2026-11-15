// The redesign's app-wide look on NaviMus's own screens (matrix rows redesign-ui, redesign-amoled,
// redesign-tabbar): always dark, so NaviMus's backgrounds are black; the tab bar and navigation bars in
// spoti.pw's redesign style, tinted with the redesign accent.
//
// Strategy (b) of docs/PHASE0_REPORT.md: system UIKit seams only, no NaviMus symbols.
//   - dark: -[UIViewController setOverrideUserInterfaceStyle:] and the UIWindow one are coerced to dark
//     (SwiftUI's preferredColorScheme, which NaviMus's own appearance setting uses, lands on the root
//     UIHostingController), and every window is set dark as it becomes key (-[UIWindow becomeKeyWindow]).
//   - bars: UITabBar / UINavigationBar appearance proxies, set before NaviMus builds its UI. iOS 26 keeps
//     the system's Liquid Glass bars (tokens tabbar.system, navbar.liquidGlass) and only tints them; before
//     26 the bars get the glass fallback material (material.glass.fallback, SystemChromeMaterialDark).
// The switch (FZSettingsKeyRedesign) is read once at launch, as spoti.pw's is.
#pragma once
#import <Foundation/Foundation.h>

/// YES when the redesigned look was on at launch.
BOOL FZRRedesignActive(void);

@class UITabBarAppearance;
/// The redesign's tab bar appearance before iOS 26 (nil with the system's glass bars), for bars SwiftUI made
/// transparent.
UITabBarAppearance *FZRTabBarLook(void);

/// Installs the look if FZSettingsKeyRedesign is on. Call before NaviMus's main().
void FZRInstallAppLook(void);
