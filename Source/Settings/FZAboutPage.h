// Adapted from taurus/tweak/Sources/App/About/About.h @ fe3211c (GPL-3.0, github.com/xFr0z3n/taurus).
// The About page: build details, licenses, settings backup and reset.
#pragma once
#import <UIKit/UIKit.h>

UIViewController *FZAboutPage(void);
UIViewController *FZLicensesPage(void);

// Writes every Frozio setting to frozio-settings.json and offers it in the share sheet.
void FZExportSettings(void);
// Picks a file made by FZExportSettings and, once confirmed, replaces Frozio's settings with it.
void FZImportSettings(void);
// Asks first, then removes every Frozio setting so each one is back at its default.
void FZConfirmResetAll(void);
