#import "../screen_mac.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSArray<NSScreen *> *screens = NSScreen.screens;
        assert(!screen_for_uuid(NULL, screens));
        assert(!screen_for_uuid("", screens));
        assert(!screen_for_uuid("not-a-uuid", screens));
        assert(!screen_for_uuid("\xff", screens));
        assert(!screen_for_uuid("0", screens));
        assert(!screen_for_uuid("00000000-0000-0000-0000-000000000000", screens));
        for (NSScreen *screen in screens) {
            CGDirectDisplayID id = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(id);
            assert(uuid);
            NSString *value = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
            CFRelease(uuid);
            assert(screen_for_uuid(value.lowercaseString.UTF8String, screens) == screen);
            assert(!screen_for_uuid([[@" " stringByAppendingString:value] UTF8String], screens));
            assert(!screen_for_uuid(value.UTF8String, @[]));
        }
        printf("screen UUID resolution: %lu connected displays checked\n", (unsigned long)screens.count);
    }
}
