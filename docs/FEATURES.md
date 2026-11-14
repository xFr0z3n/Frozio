# FEATURES

One entry per shipped feature (added by that feature's PR). Each entry records:
- what it changes for the user
- the hooked NaviMus symbols (demangled + mangled)
- how each symbol was verified (tool + output)
- the fail-safe behaviour
- what was tested, and **what was NOT tested**

Status vocabulary: **builds** / **passes CI** / **verified on device (by the user)**.

## Phase 1: no-op tweak + pipeline

- **User-visible:** only the home-screen look. The app is named **Frozio** (CI input `display_name`), and the cyan icon replaces Arpeggi's. White is registered as an alternate icon; its picker arrives with the Frozio settings panel in Phase 2.
- **Hooks:** none in NaviMus. One fix on a system class: the CloudKit guard, below.
- **Version gate:** requires CFBundleShortVersionString `1.6.1`, CFBundleVersion `173`, and main-executable LC_UUID `EF406BF6-6FAE-3B23-BA21-963FFBF19DB8`. Otherwise Frozio does nothing.
- **Signing:** done by the user's own signer. CI signing is optional and only runs when all 5 secrets are set.
- **Status:** **builds** and **passes CI** (run 43548694887, artifact `Frozio-NaviMus-1.6.1-r6-debug-unsigned.ipa`, draft release "Frozio build 6"). **Not verified on device.**
- **Device history:** build r3 crashed at launch on iOS 17.5.1 (`Library not loaded: @rpath/Frozio.dylib … unloadable mach-o file type 10`). CI had injected the dSYM's DWARF file (MH_DSYM) instead of the dylib. It's fixed in r5, and CI now asserts `MH_DYLIB` before and after injection.
- **CI verified:**
  - `cryptid=0`
  - the bundle is 1.6.1 (173)
  - `@rpath/Frozio.dylib` is in the main binary's load commands, and `LC_RPATH @executable_path/Frameworks` is present
  - `Frozio.dylib` is arm64-only and links no substrate, ElleKit or libhooker
  - the icon files are written, and `CFBundleIconName` is removed in favour of `CFBundleAlternateIcons.White`
- **Not tested:**
  - installing and launching on a device
  - the version-gate log line at runtime
  - the icon showing on the home screen
  - how external signers handle the alternate icon and the entitlements (CarPlay, Siri, KVS)

### On-device checklist (user)

1. Sign `Frozio-NaviMus-1.6.1-r6-debug-unsigned.ipa` with your signer and install it. Expect the **cyan** icon labelled **Frozio** on the home screen.
2. Launch. In Console.app (device connected, filter `subsystem:com.frozio.tweak`), expect `[Frozio] loaded v0.1.0` and `[Frozio] version gate PASS: 1.6.1 (173) uuid EF406BF6-…`.
3. Log in to your Navidrome server. Expect a one-time login, because the keychain starts empty.
4. Browse Library, Album, Artist and Playlist screens, and search.
5. Play a song, lock the phone, and confirm audio keeps playing. Check the lock-screen controls.
6. Change a NaviMus setting, force-quit, relaunch, and confirm it persisted.
7. Report anything that differs from the stock app. Note: CarPlay, Siri, and iCloud settings sync depend on what your signer's profile grants.

## Fix: CloudKit guard (`Source/Fixes/FZCloudKitGuard.m`)

- **What it changes for the user:** a re-signed NaviMus no longer crashes once a server is added. The library cache stays on the device, as in the App Store build.
- **Root cause:** crash `Arpeggi-2026-11-14-034741.ips` (iOS 17.5.1, team 2LV8B87L2J). It's re-sign-induced, and the **stock IPA re-signed the same way crashes identically**:
  - SwiftData → `-[NSPersistentContainer(CoreDataSPI) load:]` → `-[NSPersistentCloudKitContainer _loadStoreDescriptions:withCompletionHandler:]`.
  - Then `-[NSCloudKitMirroringDelegate initWithCloudKitContainerOptions:]` → `CKFetchAPSEnvironmentFromServerOrEntitlements` throws → `abort()`.
  - The App Store entitlements have `com.apple.developer.icloud-container-identifiers = []`, so SwiftData's `.automatic` CloudKit setting never mirrors there. The signer's profile adds iCloud containers but no `aps-environment`.
  - The exact exception text isn't in the report; the cause is inferred from the backtrace.
- **Hooked symbols:** Apple public API, not NaviMus:
  - `-[NSPersistentStoreDescription cloudKitContainerOptions]` (`@16@0:8`) → returns `nil`
  - `-[NSPersistentStoreDescription setCloudKitContainerOptions:]` (`v24@0:8@16`) → stores `nil`
- **Mechanism:** `method_setImplementation`, ObjC runtime only. No hooking library is added.
- **Verification:** at runtime, the class and both selectors must exist and the type encodings must match. Otherwise it logs and skips.
- **Fail-safe:** the guard only installs after the version gate passes and the setting is on.
- **Setting:** `fz.cloudKitGuard`, default **on**.
- **Tested:** builds and passes CI (run 43548694887).
- **Not tested:** on device; that SwiftData reads the description through these accessors and not the ivar; the iCloud settings sync (KVS, separate from CloudKit) under the user's profile.
