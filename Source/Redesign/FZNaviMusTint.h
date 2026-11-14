// Drives NaviMus's own tint from the redesign accent (data layer: NaviMus's settings file).
//
// Verified on device (user's Share log, 2026-11-14):
//   path   Library/Application Support/Arpeggi/shared_data/settings.json   (NaviMus 1.6.1)
//   sibling settingsMigrationVersion.json == 2
//   preset form  "appTintColorPreset": {"type":"preset","preset":"purple"}
//   custom form  "appTintColorPreset": {"type":"custom","color":{"red":0,"green":0,"blue":0,"opacity":1}}
//   "dateLastPersisted": seconds since 2001-01-01 (NSDate reference date), compared with iCloud KVS
//
// Runs from Frozio's constructor, before NaviMus's main() and before SettingsManager reads the file,
// so NaviMus loads the new tint itself; changes therefore apply on the next launch.
// Only `appTintColorPreset`, `tintColorBasedOnAppearance` and `dateLastPersisted` are touched; the
// original values are backed up once to settings.json.frozio-backup and restored when the switch is
// turned off. Any unexpected shape (missing file, wrong migration version, non-dictionary JSON,
// unknown tint "type") leaves the file untouched.
#pragma once

void FZSyncNaviMusTint(void);
