#import "DebugLog.h"
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>

static NSString *const kIPDebugLogPath = @"/var/jb/var/mobile/Library/iPatcher/tweak.log";

void IPDebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    if (!message.length) return;

    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                      [NSDate.date description],
                      message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return;

    int fd = open(kIPDebugLogPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    (void)write(fd, data.bytes, data.length);
    close(fd);
}
