// The launch palette is never written to defaults. Only HUD choices are shared by the game hosts.
#pragma once
#import <Cocoa/Cocoa.h>
#import <math.h>
#include <limits.h>
#include <stdint.h>
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

enum { HUD_OFF, HUD_FPS, HUD_DEFAULT, HUD_RICH, HUD_FULL, HUD_CUSTOM };
enum { HUD_PRESET_ROW, HUD_OPACITY_ROW, HUD_SCALE_ROW, HUD_POSITION_ROW, HUD_ADVANCED_ROW };
typedef struct {
    int preset, position;
    double scale, opacity;
    uint32_t elements, options;
    BOOL enabled, local;
} ov_hud;
static const ov_hud ov_hud_default = {HUD_FPS, 2, .2, .5, 0x10, 1u<<6, YES, YES};
// Metric Presets and bit flags from libMTLHud on macOS 27.2.1. The SDK man page's
// "Lite" is a launch alias for Default, not an additional preset in the Mac menu.
static const uint32_t ov_hud_presets[] = {0, 0x10, 0x8102803f, 0x810788bf, 0x81c79aff};
static const struct { const char *key, *en, *fr; uint32_t bit; } ov_hud_metrics[] = {
    {"device","Metal Device","Appareil Metal",0x1}, {"rosetta","Rosetta Info","Infos Rosetta",0x2},
    {"layersize","Layer Size and Composition","Taille et composition du calque",0x4},
    {"layerscale","Layer Scale and Pixel Format","Échelle et format des pixels",0x400000},
    {"memory","Memory","Mémoire",0x8}, {"refreshrate","Screen Refresh Rate","Fréquence de l’écran",0x800000},
    {"edrheadroom","EDR Headroom","Marge EDR",0x8000000}, {"thermal","Thermal State","État thermique",0x40000},
    {"gamemode","Game Mode","Mode Jeu",0x1000000}, {"fps","FPS","FPS",0x10}, {"fpsgraph","FPS Graph","Graphique FPS",0x80000},
    {"framenumber","Frame Number","Numéro d’image",0x1000}, {"gputime","GPU Time","Temps GPU",0x20000},
    {"presentdelay","Present Delay","Délai de présentation",0x10000}, {"frameinterval","Frame Interval","Intervalle d’image",0x20},
    {"frameintervalgraph","Frame Interval Graph","Graphique des intervalles",0x8000},
    {"frameintervalhistogram","Frame Interval Histogram","Histogramme des intervalles",0x40},
    {"metalcpu","Command Buffer and Encoder Count","Tampons et encodeurs",0x80},
    {"shaders","Shader Compiler","Compilation des shaders",0x800}, {"disk","Disk Usage","Activité du disque",0x2000},
    {"cmdbufgputimeline","Command Buffer GPU Timeline","Chronologie des tampons GPU",0x4000000},
    {"gputimeline","Encoder Time and GPU Timeline","Chronologie des encodeurs GPU",0x200},
    {"toplabeledcommandbuffers","Top Labeled Command Buffers","Tampons les plus coûteux",0x100000},
    {"toplabeledencoders","Top Labeled Encoders","Encodeurs les plus coûteux",0x200000},
    {"statereporter","State Reporters","Rapports d’état",0x2000000},
    {"client","Client Metrics","Métriques du client",0x80000000},
    {"energy","Energy Report","Rapport énergétique",0x400}, {"qrcode","QR Code","Code QR",0x4000},
};
static const struct { const char *key, *en, *fr; } ov_hud_options[] = {
    {"MTL_HUD_LOG_ENABLED","Logging","Journalisation"},
    {"MTL_HUD_ENCODER_TIMING_ENABLED","Encoder GPU Time Tracking","Suivi GPU des encodeurs"},
    {"MTL_HUD_LOG_SHADER_ENABLED","Shader Compiler Logging","Journal des shaders"},
    {"MTL_HUD_INSIGHTS_ENABLED","Performance Insights","Conseils de performance"},
    {"MTL_HUD_SHOW_METRICS_RANGE","Show Metrics Value Range","Plage de valeurs"},
    {"MTL_HUD_SHOW_ZERO_METRICS","Show Metrics with 0 Value","Métriques à zéro"},
    {"MTL_HUD_HIDE_METALFX_METRICS","Hide MetalFX Metrics","Masquer les métriques MetalFX"},
};
enum { HUD_METRICS = sizeof ov_hud_metrics / sizeof *ov_hud_metrics,
       HUD_OPTIONS = sizeof ov_hud_options / sizeof *ov_hud_options,
       HUD_SCOPE = 0, HUD_PASTE, HUD_COPY, HUD_ENABLE, HUD_FIRST_OPTION, HUD_FIRST_METRIC = HUD_FIRST_OPTION + HUD_OPTIONS,
       HUD_ADVANCED_COUNT = HUD_FIRST_METRIC + HUD_METRICS };
static const int ov_hud_align[] = {10,14,12,26,30,28,18,22,20};
static NSString *const ov_hud_align_names[] = {@"topleft",@"topcenter",@"topright",@"centerleft",@"centered",@"centerright",@"bottomleft",@"bottomcenter",@"bottomright"};
static double ov_hud_unit(double n, double min) { return fmax(min,fmin(1,n)); }
static int ov_hud_cycle(int value, int step, int count) { return (value + step + count) % count; }
static void ov_hud_select(ov_hud *hud, int preset) {
    hud->preset = preset; hud->enabled = preset != HUD_OFF;
    hud->elements = ov_hud_presets[preset];
    if (preset == HUD_FPS) hud->options &= ~2u;  // no encoder tracking in an FPS-only layout
}
static NSString *ov_hud_elements(uint32_t mask) {
    NSMutableArray *names = [NSMutableArray array];
    for (int i=0; i<HUD_METRICS; i++) if (mask & ov_hud_metrics[i].bit) [names addObject:@(ov_hud_metrics[i].key)];
    return [names componentsJoinedByString:@","];
}
static NSDictionary *ov_hud_config(ov_hud hud) {
    NSMutableDictionary *d = [@{@"MTL_HUD_ENABLED":@(hud.enabled), @"MTL_HUD_ALIGNMENT":@(ov_hud_align[hud.position]),
        @"MTL_HUD_ELEMENTS":ov_hud_elements(hud.elements), @"MTL_HUD_SCALE":@(hud.scale), @"MTL_HUD_OPACITY":@(hud.opacity)} mutableCopy];
    for (int i=0; i<HUD_OPTIONS; i++) d[@(ov_hud_options[i].key)] = @((hud.options >> i) & 1u);
    return d;
}
static NSDictionary *ov_hud_properties(ov_hud hud) {
    if (!hud.enabled) return @{@"mode":@"disabled"};
    NSMutableDictionary *d = [ov_hud_config(hud) mutableCopy];
    d[@"mode"] = @"default";
    d[@"logging"] = hud.options & 1u ? @"default" : @"disabled";
    if (!hud.elements) d[@"MTL_HUD_ELEMENTS"]=@0;
    return d;
}
static NSString *ov_hud_export(ov_hud hud) {
    NSDictionary *d=ov_hud_config(hud); NSMutableArray *parts=[NSMutableArray array];
    for (NSString *key in [d.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [parts addObject:[NSString stringWithFormat:@"%@=%@",key,d[key]]];
    return [parts componentsJoinedByString:@" "];
}
static NSNumber *ov_hud_number(id value) {
    if ([value isKindOfClass:NSNumber.class]) return isfinite([value doubleValue]) ? value : nil;
    if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
    NSScanner *s=[NSScanner scannerWithString:value]; double n;
    s.charactersToBeSkipped=nil;
    return [s scanDouble:&n] && s.atEnd && isfinite(n) ? @(n) : nil;
}
static BOOL ov_hud_import(NSString *text, ov_hud *hud, NSUInteger *ignored) {
    *ignored=0;
    if (!text.length || text.length > 16384) return NO;
    text=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    if ([text hasPrefix:@"<"]) {
        id plist=[NSPropertyListSerialization propertyListWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 format:NULL error:NULL];
        if (![plist isKindOfClass:NSDictionary.class]) return NO;
        [values addEntriesFromDictionary:plist];
    } else {
        for (NSString *word in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
            if (![word hasPrefix:@"MTL_HUD_"]) continue;
            NSRange eq=[word rangeOfString:@"="]; if (eq.location==NSNotFound) continue;
            NSString *v=[word substringFromIndex:eq.location+1];
            if (v.length>=2 && (([v hasPrefix:@"\""] && [v hasSuffix:@"\""]) || ([v hasPrefix:@"'"] && [v hasSuffix:@"'"])))
                v=[v substringWithRange:NSMakeRange(1,v.length-2)];
            values[[word substringToIndex:eq.location]]=v;
        }
    }
    ov_hud next=*hud; BOOL applied=NO;
    for (NSString *key in values) {
        id v=values[key]; NSNumber *num=ov_hud_number(v); double n=num.doubleValue;
        if ([key isEqual:@"MTL_HUD_ELEMENTS"] && ([v isKindOfClass:NSString.class] || num)) {
            NSString *list=[v isKindOfClass:NSString.class] ? [v lowercaseString] : num.stringValue;
            NSUInteger preset=[@[@"off",@"fps",@"default",@"rich",@"full",@"lite"] indexOfObject:list];
            uint32_t mask=0; BOOL valid=!list.length || [list isEqual:@"0"];
            if (num && n>0 && n<=UINT32_MAX && n==floor(n)) {
                uint32_t supported=0;
                for (int i=0;i<HUD_METRICS;i++) supported|=ov_hud_metrics[i].bit;
                mask=(uint32_t)n & supported; valid=YES;
                if ((uint32_t)n!=mask) (*ignored)++;
            } else if (preset!=NSNotFound && preset>HUD_OFF) { mask=ov_hud_presets[preset==5 ? HUD_DEFAULT : preset]; valid=YES; }
            else if (!valid) for (NSString *name in [list componentsSeparatedByString:@","]) {
                BOOL found=NO;
                for (int i=0; i<HUD_METRICS; i++) if ([name isEqual:@(ov_hud_metrics[i].key)]) {
                    mask|=ov_hud_metrics[i].bit; valid=found=YES; break;
                }
                if (!found) (*ignored)++;
            }
            if (valid) { next.elements=mask; applied=YES; }
            continue;
        }
        if ([key isEqual:@"MTL_HUD_ALIGNMENT"]) {
            NSArray *shorts=@[@"tl",@"tc",@"tr",@"cl",@"c",@"cr",@"bl",@"bc",@"br"];
            for (int i=0;i<9;i++) if ((num && n==ov_hud_align[i]) || [v isEqual:ov_hud_align_names[i]] || [v isEqual:shorts[i]]) {
                next.position=i; applied=YES; goto handled;
            }
        } else if (num && [key isEqual:@"MTL_HUD_ENABLED"] && n==floor(n)) { next.enabled=n!=0; applied=YES; continue; }
        else if (num && [key isEqual:@"MTL_HUD_OPACITY"]) { next.opacity=ov_hud_unit(n,0); applied=YES; continue; }
        else if (num && [key isEqual:@"MTL_HUD_SCALE"]) { next.scale=ov_hud_unit(n,.1); applied=YES; continue; }
        else if (num && (n==0 || n==1)) for (int i=0;i<HUD_OPTIONS;i++) if ([key isEqual:@(ov_hud_options[i].key)]) {
            next.options=(next.options & ~(1u<<i)) | ((unsigned)n<<i); applied=YES; goto handled;
        }
        (*ignored)++;
    handled:;
    }
    if (applied) { next.preset=HUD_CUSTOM; *hud=next; }
    return applied;
}
static ov_hud ov_hud_load(NSUserDefaults *store, NSString *game) {
    id value=[store objectForKey:game]; BOOL local=value!=nil;
    if (!local) value=[store objectForKey:@"global"];
    ov_hud hud=ov_hud_default;
    if ([value isKindOfClass:NSDictionary.class]) {
        NSNumber *preset=ov_hud_number(value[@"preset"]); NSUInteger ignored=0;
        NSString *config=[value[@"config"] isKindOfClass:NSString.class] ? value[@"config"] : nil;
        if (preset && preset.doubleValue==preset.intValue && preset.intValue>=HUD_OFF && preset.intValue<=HUD_CUSTOM &&
            ov_hud_import(config,&hud,&ignored) && !ignored) { hud.preset=preset.intValue; hud.local=local; return hud; }
    } else if ([value isKindOfClass:NSArray.class] && [value count]==4) {
        int n[4], max[]={3,3,2,4};
        for (int i=0;i<4;i++) {
            NSNumber *num=ov_hud_number(value[i]); double d=num.doubleValue;
            if (!num || d<0 || d>max[i] || d!=floor(d)) return hud;
            n[i]=(int)d;
        }
        ov_hud_select(&hud,((int[]){HUD_OFF,HUD_FPS,HUD_DEFAULT,HUD_FULL})[n[0]]);
        hud.position=((int[]){0,2,6,8})[n[1]]; hud.scale=.2+.1*n[2];
        hud.opacity=((double[]){.25,.35,.5,.75,1})[n[3]]; hud.local=local;
        return hud;
    }
    return ov_hud_default;
}
static void ov_hud_save(NSUserDefaults *store, NSString *game, ov_hud hud) {
    [store setObject:@{@"preset":@(hud.preset),@"config":ov_hud_export(hud)} forKey:hud.local ? game : @"global"];
    if (!hud.local) [store removeObjectForKey:game];
}
static BOOL ov_fullscreen_load(NSUserDefaults *store, NSString *game, const char *env) {
    NSNumber *saved=[store objectForKey:[game stringByAppendingString:@"-fullscreen"]];
    return [saved isKindOfClass:NSNumber.class] ? saved.boolValue : env && strcmp(env,"0");
}
static void ov_fullscreen_save(NSUserDefaults *store, NSString *game, BOOL fullscreen) {
    [store setBool:fullscreen forKey:[game stringByAppendingString:@"-fullscreen"]];
}
static BOOL ov_home_swap_load(NSUserDefaults *store, const char *env) {
    return env ? !strcmp(env,"1") : [store boolForKey:@"home-swap"];
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
