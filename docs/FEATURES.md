# FEATURES

One entry per shipped feature (added by that feature's PR). Each entry records:
- what it changes for the user
- the hooked NaviMus symbols (demangled + mangled)
- how each symbol was verified (tool + output)
- the fail-safe behaviour
- what was tested, and **what was NOT tested**

Status vocabulary: **builds** / **passes CI** / **verified on device (by the user)**.

## Phase 1: no-op tweak + pipeline

- **User-visible:** none, beyond the app icon. The cyan icon replaces Arpeggi's, and white is registered as an alternate (the picker arrives with the Frozio settings panel in Phase 2).
- **Hooks:** none.
- **Version gate:** requires CFBundleShortVersionString `1.6.1`, CFBundleVersion `173`, and main-executable LC_UUID `EF406BF6-6FAE-3B23-BA21-963FFBF19DB8`. Otherwise Frozio does nothing.
- **Status:** not yet built.
