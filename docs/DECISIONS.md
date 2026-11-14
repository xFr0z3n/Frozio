# DECISIONS

The user's decisions that steer Frozio, newest last. They override FROZIO_PROMPT.md wherever the two differ.

| Date | Topic | Decision |
|---|---|---|
| 2026-11-14 | Licence / code reuse | Frozio is GPL-3.0. Reuse code from GPL sources only: taurus, spoti.pw ≤ v0.21.1, amperfy. Current spoti.pw (PolyForm Strict) contributes values and behaviour, never code. See `LICENSES.md` |
| 2026-11-14 | UI strategy | (a)+(b): hook the hosting-controller boundary for theming/injection; Frozio-owned views for new UI; Swift patches only as a last resort, pinned by the version gate |
| 2026-11-14 | Look | spoti.pw **redesign** look only (iOS 26 glass, material fallback on iOS 17–25); native-look rows are out of scope |
| 2026-11-14 | Signing | The user signs with their own external signer; CI produces unsigned IPAs, and CI signing is optional |
| 2026-11-14 | Bundle | Display name **Frozio**; cyan icon is the default, white is the alternate; bundle ID unchanged |
| 2026-11-14 | Extensions | A Frozio widget extension (Live Activity) may be added to the IPA |
| 2026-11-14 | Dropped | F60 lossless local swap-in / Soulseek |
| 2026-11-14 | Hooking runtime | ObjC runtime (`method_setImplementation`) by default; **fishhook** only when a C function must be rebound; Frozio's own Swift vtable/witness-table patcher (data-only) only where a feature can't be done otherwise. No ElleKit/Substrate/Orion: inline code patching doesn't work on a stock-signed app |
| 2026-11-14 | Gated features | Every spoti.pw Plus-gated feature ships **1:1 and ungated**: Workshop, Web Player, Visualizer, AutoMix, audio effects + AutoEq, listening stats, Sing, lyrics shaders, lock-screen styles, Ambient |
| 2026-11-14 | Web Player backend | Relay runs on the user's own domain + Raspberry Pi 5 |
