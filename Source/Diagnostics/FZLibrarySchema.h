// Debug-only: writes the layout of NaviMus's library store to frozio.log, for the rebuilt redesign screens
// (docs/REDESIGN_PLAN.md, step R0a). The store is SwiftData (SQLite) under
// Application Support/Arpeggi/<database id>/database/ (folder case 5 in the 1.6.1 binary).
//
// It logs file names, tables, columns with their declared types, and row counts. Never a row's content.
// Opened read-only (SQLITE_OPEN_READONLY), so NaviMus's store is never written.
#pragma once

#ifdef FROZIO_DEBUG
void FZLogLibrarySchema(void);
#endif
