// Frozio logger.
// Debug builds (FROZIO_DEBUG=1): every line goes to os_log (subsystem "com.frozio.tweak") AND to
//   Documents/Frozio/frozio.log, which the debug IPA exposes in the Files app (On My iPhone > Frozio)
//   because the user has no Mac / Console.app.
// Release builds: every call compiles out entirely (arguments are not evaluated).
// Format strings are NSString formats (%@, %s, %d …), not os_log's %{public}@.
#pragma once
#import <Foundation/Foundation.h>

#ifdef FROZIO_DEBUG
void FZLogWrite(BOOL isError, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
/// Path of the current log file (Documents/Frozio/frozio.log).
NSString *FZLogFilePath(void);
#define FZLog(fmt, ...)      FZLogWrite(NO,  @fmt, ##__VA_ARGS__)
#define FZLogError(fmt, ...) FZLogWrite(YES, @fmt, ##__VA_ARGS__)
#else
#define FZLog(fmt, ...)      do { } while (0)
#define FZLogError(fmt, ...) do { } while (0)
#endif
