// The launch palette is never written to defaults. Only HUD choices are shared by the game hosts.
#pragma once
#import <Cocoa/Cocoa.h>
#import <math.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

static NSColor *ov_color(unsigned rgba) {
    return [NSColor colorWithSRGBRed:(rgba >> 24) / 255.0 green:((rgba >> 16) & 255) / 255.0
                               blue:((rgba >> 8) & 255) / 255.0 alpha:(rgba & 255) / 255.0];
}
static double ov_luminance(double rgb[3]) {
    const double w[] = {.2126, .7152, .0722}; double n = 0;
    for (int i = 0; i < 3; i++) n += w[i] * (rgb[i] <= .04045 ? rgb[i] / 12.92 : pow((rgb[i] + .055) / 1.055, 2.4));
    return n;
}
static double ov_composite(NSColor *c, double bg[3], double out[3]) {
    double v[3] = {c.redComponent, c.greenComponent, c.blueComponent}, a = c.alphaComponent;
    for (int i = 0; i < 3; i++) out[i] = v[i] * a + bg[i] * (1 - a);
    return ov_luminance(out);
}
static BOOL ov_contrast(NSColor *foreground, NSColor *background) {
    // The two extremes bound any game picture under these translucent surfaces.
    double lo[3] = {0, 0, 0}, hi[3] = {1, 1, 1}, bg[3], fg[3];
    double b0 = ov_composite(background, lo, bg), f0 = ov_composite(foreground, bg, fg);
    double b1 = ov_composite(background, hi, bg), f1 = ov_composite(foreground, bg, fg);
    return (f0 + .05) / (b1 + .05) >= 4.5 || (b0 + .05) / (f1 + .05) >= 4.5;
}
static NSDictionary *ov_theme(NSString *raw) {
    NSDictionary *fallback = @{@"ink":ov_color(0xffffffff), @"surface":ov_color(0x14181ff5),
        @"scrim":ov_color(0x000000ff), @"focus":ov_color(0xffffffff), @"onFocus":ov_color(0x111111ff)};
    if (!raw.length || raw.length > 512) return fallback;
    NSScanner *s = [NSScanner scannerWithString:raw];
    s.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" \n\r\t"];
    s.caseSensitive = YES;
    NSMutableDictionary *parsed = [NSMutableDictionary dictionary];
    if (![s scanString:@"{" intoString:NULL]) return fallback;
    for (int i = 0; i < 5; i++) {
        NSString *key;
        if (i && ![s scanString:@"," intoString:NULL]) return fallback;
        if (![s scanString:@"\"" intoString:NULL]) return fallback;
        s.charactersToBeSkipped = nil;
        if (![s scanUpToString:@"\"" intoString:&key] || !fallback[key] || parsed[key] ||
            ![s scanString:@"\"" intoString:NULL]) return fallback;
        s.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" \n\r\t"];
        if (![s scanString:@":" intoString:NULL] || ![s scanString:@"\"#" intoString:NULL]) return fallback;
        s.charactersToBeSkipped = nil;
        NSString *hex;
        if (![s scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] intoString:&hex] ||
            hex.length != 8 || ![s scanString:@"\"" intoString:NULL]) return fallback;
        parsed[key] = ov_color((unsigned)strtoul(hex.UTF8String, NULL, 16));
        s.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" \n\r\t"];
    }
    if (![s scanString:@"}" intoString:NULL] || !s.atEnd || !ov_contrast(parsed[@"ink"], parsed[@"surface"]) ||
        !ov_contrast(parsed[@"onFocus"], parsed[@"focus"]) || !ov_contrast(parsed[@"focus"], parsed[@"surface"]) ||
        !ov_contrast(parsed[@"ink"], [parsed[@"scrim"] colorWithAlphaComponent:[parsed[@"scrim"] alphaComponent] * .90]))
        return fallback;
    return parsed;
}

typedef struct { int preset, position, size, opacity; BOOL local; } ov_hud;
static const ov_hud ov_hud_default = {1, 1, 0, 2, YES};
static const int ov_hud_opacity[] = {25, 35, 50, 75, 100};
static ov_hud ov_hud_preset(int preset, BOOL local) {
    return (ov_hud){preset, 1, preset > 1 ? 1 : 0, preset > 1 ? 3 : 2, local};
}
static ov_hud ov_hud_load(NSUserDefaults *store, NSString *game) {
    NSArray *values = [store arrayForKey:game]; BOOL local = values.count == 4;
    if (!local) values = [store arrayForKey:@"global"];
    if (values.count != 4) return ov_hud_default;
    int n[4], max[] = {3, 3, 2, 4};
    for (int i = 0; i < 4; i++) {
        if (![values[i] isKindOfClass:NSNumber.class]) return ov_hud_default;
        double v = [values[i] doubleValue];
        if (!isfinite(v) || v < 0 || v > max[i] || floor(v) != v) return ov_hud_default;
        n[i] = (int)v;
    }
    return (ov_hud){n[0], n[1], n[2], n[3], local};
}
static void ov_hud_save(NSUserDefaults *store, NSString *game, ov_hud hud) {
    [store setObject:@[@(hud.preset), @(hud.position), @(hud.size), @(hud.opacity)] forKey:hud.local ? game : @"global"];
    if (!hud.local) [store removeObjectForKey:game];
}

// Physical macOS function keys only; 0 disables the keyboard shortcut, not Home.
static void ov_keys(const char *text, unsigned short keys[2]) {
    const unsigned short codes[] = {122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111};
    keys[0] = codes[8]; keys[1] = codes[9];
    if (text && !strcmp(text, "0")) { keys[0] = keys[1] = USHRT_MAX; return; }
    int a, b; char end, canonical[16];
    if (!text || strlen(text) > 7 || sscanf(text, "F%d,F%d%c", &a, &b, &end) != 2 ||
        a < 1 || a > 12 || b < 1 || b > 12 || a == b) return;
    snprintf(canonical, sizeof canonical, "F%d,F%d", a, b);
    if (!strcmp(canonical, text)) { keys[0] = codes[a - 1]; keys[1] = codes[b - 1]; }
}
