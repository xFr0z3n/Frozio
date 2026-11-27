// FZDebugRemote: debug-only control port for scripts/fzr (see FZDebugRemote.m).
#pragma once
#ifdef FROZIO_DEBUG
/// Listens on port 7357 when the app was launched with -FZRemoteToken <token>; otherwise does nothing.
void FZInstallDebugRemote(void);
#endif
