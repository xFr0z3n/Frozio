// Adds a Frozio button to NaviMus's Settings screen (top-right of its navigation bar).
//
// Identity of the Settings screen, verified by the debug screen census (frozio.log, 2026-11-14):
//   class   _TtGC7SwiftUI32NavigationStackHostingControllerVS_7AnyView_   (SwiftUI's type-erased stack host)
//   root of a SwiftUI.UIKitNavigationController (viewControllers.firstObject == self, depth 1)
//   inside SwiftUI.UIKitTabBarController (a tab root)
//   navigationItem.title == "Settings"
// All four must hold; the class alone is shared by every NaviMus screen (AnyView).
#pragma once

void FZInstallSettingsEntry(void);
