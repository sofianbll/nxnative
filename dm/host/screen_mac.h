#import <Cocoa/Cocoa.h>

// The display number is session-local; Core Graphics supplies the persistent UUID.
static NSScreen *screen_for_uuid(const char *value, NSArray<NSScreen *> *screens) {
    if (!value || !*value) return nil;
    NSString *wanted = [NSString stringWithUTF8String:value];
    if (!wanted) return nil;
    for (NSScreen *screen in screens) {
        CGDirectDisplayID id = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if (!id) continue;
        CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(id);
        if (!uuid) continue;
        NSString *actual = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
        CFRelease(uuid);
        if (actual && [actual caseInsensitiveCompare:wanted] == NSOrderedSame) return screen;
    }
    return nil;
}
