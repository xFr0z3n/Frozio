// CloudKit guard: keeps NaviMus's SwiftData store local-only, as in the App Store build.
//
// Why: the App Store build is signed with `com.apple.developer.icloud-container-identifiers = []`,
// so SwiftData's `.automatic` CloudKit setting never mirrors the library. Re-signers often embed
// a profile that lists iCloud containers but no `aps-environment`; SwiftData then builds an
// NSCloudKitMirroringDelegate, and CloudKit throws inside CKFetchAPSEnvironmentFromServerOrEntitlements.
// The app aborts as soon as a server is added (crash Arpeggi-2026-11-14-034741.ips; the stock IPA
// re-signed the same way crashes identically).
//
// How: returns nil from -[NSPersistentStoreDescription cloudKitContainerOptions] and drops values passed
// to -setCloudKitContainerOptions:. A nil value is Core Data's documented "don't mirror to CloudKit"
// state. These are public Core Data API (iOS 13+), not NaviMus symbols; the hook uses the ObjC runtime only.
#pragma once

/// Installs the guard. Preconditions are checked; on any mismatch it logs and does nothing.
void FZInstallCloudKitGuard(void);
