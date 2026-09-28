#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <errno.h>
#include "WindowSpaceMove.h"

static uint64_t parseID(const char *value, uint64_t maximum) {
    if (!value[0]) return 0;
    for (const char *p = value; *p; p++) if (*p < '0' || *p > '9') return 0;
    errno = 0;
    char *end;
    unsigned long long number = strtoull(value, &end, 10);
    return errno || *end || number > maximum ? 0 : number;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) { fprintf(stderr, "Usage: space-mover WINDOW_ID SPACE_ID\n"); return 2; }
        uint64_t window = parseID(argv[1], UINT32_MAX), space = parseID(argv[2], UINT64_MAX);
        if (!window || !space) { fprintf(stderr, "Invalid window or Space ID\n"); return 2; }
        [NSApplication sharedApplication];
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_GLOBAL);
        int (*connection)(void) = dlsym(RTLD_DEFAULT, "SLSMainConnectionID");
        CFArrayRef (*copySpaces)(int, int, CFArrayRef) = dlsym(RTLD_DEFAULT, "SLSCopySpacesForWindows");
        if (!connection || !copySpaces || !WSMoveBridgedIsAvailable()) {
            fprintf(stderr, "Native Space movement unavailable on this macOS\n"); return 3;
        }
        NSArray *windows = @[@(window)];
        CFArrayRef initial = copySpaces(connection(), 7, (__bridge CFArrayRef)windows);
        BOOL eligible = initial && CFArrayGetCount(initial) == 1;
        if (initial) CFRelease(initial);
        if (!eligible) { fprintf(stderr, "Window must belong to exactly one Space\n"); return 4; }
        if (!WSMoveBridged((uint32_t)window, space)) {
            fprintf(stderr, "Native Space movement refused\n"); return 5;
        }
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
        do {
            CFArrayRef actual = copySpaces(connection(), 7, (__bridge CFArrayRef)windows);
            BOOL confirmed = actual && CFArrayGetCount(actual) == 1 &&
                [(__bridge NSNumber *)CFArrayGetValueAtIndex(actual, 0) unsignedLongLongValue] == space;
            if (actual) CFRelease(actual);
            if (confirmed) { puts("confirmed"); return 0; }
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.025]];
        } while ([deadline timeIntervalSinceNow] > 0);
        fprintf(stderr, "macOS did not confirm the window on the requested Space\n");
        return 6;
    }
}
