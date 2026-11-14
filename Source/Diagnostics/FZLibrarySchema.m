#import "Diagnostics/FZLibrarySchema.h"

#ifdef FROZIO_DEBUG
#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "Core/FZLog.h"

static BOOL isSQLite(NSString *path) {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [file readDataOfLength:16];
    [file closeFile];
    return head.length == 16 && memcmp(head.bytes, "SQLite format 3", 16) == 0;
}

static NSString *text(sqlite3_stmt *statement, int column) {
    const unsigned char *value = sqlite3_column_text(statement, column);
    return value ? @((const char *)value) : @"";
}

static void logSchema(NSString *path, NSString *shown) {
    sqlite3 *db = NULL;
    NSString *uri = [@"file:" stringByAppendingString:path];
    if (sqlite3_open_v2(uri.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL) != SQLITE_OK) {
        FZLogError("schema: can't open %@: %s", shown, db ? sqlite3_errmsg(db) : "?");
        sqlite3_close(db);
        return;
    }
    NSMutableArray<NSString *> *tables = [NSMutableArray array];
    sqlite3_stmt *list = NULL;
    if (sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name", -1, &list, NULL) == SQLITE_OK) {
        while (sqlite3_step(list) == SQLITE_ROW) [tables addObject:text(list, 0)];
    }
    sqlite3_finalize(list);
    FZLog("schema: %@: %lu tables", shown, (unsigned long)tables.count);

    for (NSString *table in tables) {
        // Names come from sqlite_master; quoted as identifiers all the same.
        NSString *quoted = [NSString stringWithFormat:@"\"%@\"", [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
        NSMutableArray<NSString *> *columns = [NSMutableArray array];
        sqlite3_stmt *info = NULL;
        NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info(%@)", quoted];
        if (sqlite3_prepare_v2(db, pragma.UTF8String, -1, &info, NULL) == SQLITE_OK) {
            while (sqlite3_step(info) == SQLITE_ROW) [columns addObject:[NSString stringWithFormat:@"%@ %@", text(info, 1), text(info, 2)]];
        }
        sqlite3_finalize(info);
        long long rows = -1;
        sqlite3_stmt *count = NULL;
        NSString *countSQL = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@", quoted];
        if (sqlite3_prepare_v2(db, countSQL.UTF8String, -1, &count, NULL) == SQLITE_OK && sqlite3_step(count) == SQLITE_ROW) {
            rows = sqlite3_column_int64(count, 0);
        }
        sqlite3_finalize(count);
        FZLog("schema: %@ (%lld rows): %@", table, rows, [columns componentsJoinedByString:@", "]);
    }
    sqlite3_close(db);
}

void FZLogLibrarySchema(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *root = [support stringByAppendingPathComponent:@"Arpeggi"];
    NSUInteger found = 0;
    NSDirectoryEnumerator<NSString *> *walk = [fm enumeratorAtPath:root];
    for (NSString *relative in walk) {
        if (walk.level > 4) { [walk skipDescendants]; continue; }
        NSString *name = relative.lastPathComponent;
        if ([name hasSuffix:@"-wal"] || [name hasSuffix:@"-shm"] || [relative hasPrefix:@"Caches"]) continue;
        if ([relative containsString:@"/lyrics/"] || [relative containsString:@"/cover_art/"] || [relative containsString:@"_songs/"]) continue;
        NSString *path = [root stringByAppendingPathComponent:relative];
        if (![walk.fileAttributes.fileType isEqualToString:NSFileTypeRegular] || !isSQLite(path)) continue;
        found++;
        logSchema(path, [@"Arpeggi/" stringByAppendingString:relative]);
    }
    if (!found) FZLog("schema: no SQLite store under Application Support/Arpeggi");
}
#endif
