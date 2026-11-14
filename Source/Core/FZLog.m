#import "FZLog.h"

#ifdef FROZIO_DEBUG
#import <os/log.h>

static const unsigned long long kFZLogMaxBytes = 1024 * 1024; // rotate to frozio.log.1 at 1 MB

static os_log_t FZLogHandle(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.frozio.tweak", "general"); });
    return log;
}

static dispatch_queue_t FZLogQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.frozio.log", DISPATCH_QUEUE_SERIAL); });
    return q;
}

NSString *FZLogFilePath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        if (!docs) return;
        NSString *dir = [docs stringByAppendingPathComponent:@"Frozio"];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        path = [dir stringByAppendingPathComponent:@"frozio.log"];
    });
    return path;
}

static void FZLogAppendToFile(NSString *line) {
    NSString *path = FZLogFilePath();
    if (!path) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (attrs && attrs.fileSize > kFZLogMaxBytes) {
        NSString *old = [path stringByAppendingString:@".1"];
        [fm removeItemAtPath:old error:nil];
        [fm moveItemAtPath:path toPath:old error:nil];
    }
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) return;
    @try {
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (__unused NSException *e) {
        // a full disk or a revoked file must never take the app down
    }
    [h closeFile];
}

void FZLogWrite(BOOL isError, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    if (isError) os_log_error(FZLogHandle(), "[Frozio] %{public}@", msg);
    else         os_log(FZLogHandle(), "[Frozio] %{public}@", msg);

    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"%@ %@ %@\n",
                      [df stringFromDate:NSDate.date], isError ? @"ERR" : @"   ", msg];
    dispatch_async(FZLogQueue(), ^{ FZLogAppendToFile(line); });
}
#endif
