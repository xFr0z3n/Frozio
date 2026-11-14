// Frozio logger. Debug builds (FROZIO_DEBUG=1) log through os_log under subsystem
// "com.frozio.tweak"; release builds compile every call out entirely.
#pragma once

#ifdef FROZIO_DEBUG
#import <os/log.h>

static inline os_log_t FZLogHandle(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.frozio.tweak", "general"); });
    return log;
}

#define FZLog(fmt, ...)      os_log(FZLogHandle(), "[Frozio] " fmt, ##__VA_ARGS__)
#define FZLogError(fmt, ...) os_log_error(FZLogHandle(), "[Frozio] " fmt, ##__VA_ARGS__)
#else
#define FZLog(fmt, ...)      do { } while (0)
#define FZLogError(fmt, ...) do { } while (0)
#endif
