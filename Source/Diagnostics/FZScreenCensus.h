// Screen census (DEBUG builds only): logs every view controller NaviMus shows, with its exact runtime
// class, its parent chain, titles and the tab bar layout. Phase 2 uses these logs to pick hook targets
// by verified class type (FROZIO_PROMPT §7.4), e.g. the UIHostingController that hosts SettingsView.
#pragma once

void FZInstallScreenCensus(void);
