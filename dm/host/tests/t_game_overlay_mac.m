#import "../game_overlay_mac.h"
#import <CoreImage/CoreImage.h>
#include <assert.h>

static void settings(void) {
    NSDictionary *fallback = ov_theme(nil);
    NSString *valid = @"{\"ink\":\"#FFFFFFFF\", \"surface\":\"#101010F5\", \"scrim\":\"#000000FF\", \"focus\":\"#EEEEEEFF\", \"onFocus\":\"#111111FF\"}";
    assert(![ov_theme(valid) isEqual:fallback] && [ov_theme(valid)[@"focus"] isEqual:ov_color(0xeeeeeeff)]);
    for (NSString *bad in @[@"{}", @"[]", [valid stringByAppendingString:@"a"],
        [valid stringByReplacingOccurrencesOfString:@"onFocus" withString:@"ink"],
        [valid stringByReplacingOccurrencesOfString:@"#EEEEEEFF" withString:@"#EEEEEE1F"],
        [valid stringByReplacingOccurrencesOfString:@"#EEEEEEFF" withString:@"#ZZZZZZFF"],
        [valid stringByReplacingOccurrencesOfString:@"#EEEEEEFF" withString:@"#FFFFFF"],
        [valid stringByReplacingOccurrencesOfString:@"#111111FF" withString:@"#FFFFFF00"]])
        assert([ov_theme(bad) isEqual:fallback]);
    unsigned short keys[2];
    ov_keys(NULL,keys); assert(keys[0] == 101 && keys[1] == 109);
    ov_keys("F1,F12",keys); assert(keys[0] == 122 && keys[1] == 111);
    ov_keys("F3,F3",keys); assert(keys[0] == 101 && keys[1] == 109);
    ov_keys("0",keys); assert(keys[0] == USHRT_MAX && keys[1] == USHRT_MAX);
    NSString *domain = [@"org.nxnative.overlay.test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:domain];
    ov_hud hud = ov_hud_load(store,@"game-a");
    assert(hud.preset == 1 && hud.local && hud.position == 1 && hud.size == 0 && hud.opacity == 2);
    hud = (ov_hud){3,2,1,4,YES}; ov_hud_save(store,@"game-a",hud);
    assert(ov_hud_load(store,@"game-b").preset == 1);
    store = [[NSUserDefaults alloc] initWithSuiteName:domain];
    hud = ov_hud_load(store,@"game-a");
    assert(hud.preset == 3 && hud.position == 2 && hud.size == 1 && hud.opacity == 4 && hud.local);
    hud.local = NO; ov_hud_save(store,@"game-a",hud);
    assert(![store objectForKey:@"game-a"] && ov_hud_load(store,@"game-b").preset == 3 && !ov_hud_load(store,@"game-b").local);
    [store setObject:@[@3,@2,@1,@"bad"] forKey:@"game-a"];
    assert(ov_hud_load(store,@"game-a").preset == 1);
    [store removePersistentDomainForName:domain];
}

static NSImage *backdrop(NSString *dir, BOOL blur) {
    CIImage *image = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"bg.jpg"]]];
    assert(image);
    image = [image imageByApplyingTransform:CGAffineTransformMakeScale(1008/NSHeight(image.extent),1008/NSHeight(image.extent))];
    CGRect rect = CGRectMake(0,0,1600,900);
    image = [image imageByCroppingToRect:rect];
    if (blur) {
        image = [image imageByApplyingTransform:CGAffineTransformMake(1.06,0,0,1.06,-48,-27)];
        image = [[[image imageByClampingToExtent] imageByApplyingFilter:@"CIGaussianBlur"
            withInputParameters:@{kCIInputRadiusKey:@16.67}] imageByCroppingToRect:rect];
    }
    CGImageRef cg = [[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}] createCGImage:image fromRect:rect];
    assert(cg); NSImage *out = [[NSImage alloc] initWithCGImage:cg size:rect.size]; CGImageRelease(cg);
    return out;
}

static void capture(NSString *out, NSString *name, NSRect bounds, NSImage *picture, NSView *overlay, int preset) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NSView *stage = [[NSView alloc] initWithFrame:bounds];
    window.contentView = stage;
    if (picture) {
        NSImageView *image = [NSImageView imageViewWithImage:picture]; image.frame = bounds;
        image.imageScaling = NSImageScaleAxesIndependently;
        [stage addSubview:image];
    }
    if (preset) {
        NSTextField *fps = ov_fps_label(ov_fps_text(preset,60,16.7,@"▃▂▆▃▄▂▃▃"));
        ov_fps_layout(fps,bounds,ov_hud_preset(preset,YES));
        assert(NSContainsRect(bounds,fps.frame));
        [stage addSubview:fps];
    }
    if (overlay) {
        for (NSView *child in overlay.subviews) assert(NSContainsRect(bounds,child.frame));
        [stage addSubview:overlay];
    }
    [stage layoutSubtreeIfNeeded]; [stage displayIfNeeded];
    NSBitmapImageRep *rep = [stage bitmapImageRepForCachingDisplayInRect:bounds];
    assert(rep.pixelsWide == 1600 && rep.pixelsHigh == 900);
    [stage cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSString *path = [out stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    assert([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
    printf("%s\n",path.UTF8String);
}
static void screens(NSString *out, NSString *assets, NSRect bounds, NSDictionary *sample) {
    NSImage *picture = backdrop(assets,NO), *blurred = backdrop(assets,YES);
    NSDictionary *theme = ov_theme(nil);
    void (^unused)(NSInteger,NSInteger) = ^(NSInteger a,NSInteger i) { (void)a; (void)i; };
    NSArray *quickNames = @[@"overlay-quick",@"overlay-quick-volume",@"overlay-quick-controllers",@"overlay-quick-multiplayer",
        @"overlay-quick-quit",@"overlay-quick-hud-standard",@"overlay-quick-hud-full",@"overlay-quick-home-help"];
    for (NSUInteger i=0; i<quickNames.count; i++) {
        home_quit q = {0}; hq_open(&q,HQ_QUICK);
        q.selection = i<=HQ_POWER ? (int)i : HQ_HUD;
        if (i<7) q.card = q.selection;
        q.confirm = i==HQ_POWER;
        int preset = i==5 ? 2 : i==6 ? 3 : 1;
        NSMutableDictionary *d = [sample mutableCopy];
        ov_hud hud = ov_hud_preset(preset,YES);
        d[@"preset"] = @(preset); d[@"size"] = ov_text(YES,hud.size ? @"Medium" : @"Small");
        d[@"opacity"] = [NSString stringWithFormat:@"%d %%",ov_hud_opacity[hud.opacity]];
        if (i==7) d[@"homeHelp"] = ov_home_help(YES,YES);
        capture(out,quickNames[i],bounds,picture,ov_view(bounds,q,d,theme,unused),preset);
    }
    NSArray *fullNames = @[@"overlay-full",@"overlay-full-settings",@"overlay-full-profile",@"overlay-full-friends",@"overlay-full-achievements",
        @"overlay-full-standalone"];
    for (NSUInteger i=0; i<fullNames.count; i++) {
        home_quit q = {0}; hq_open(&q,HQ_FULL); q.tab = i<OV_TAB_COUNT ? (int)i : OV_SESSION;
        NSMutableDictionary *d = [sample mutableCopy]; d[@"background"] = blurred;
        if (i==OV_TAB_COUNT) {
            [d removeObjectsForKeys:@[@"cover",@"total",@"social"]];
            d[@"actions"] = @[@"Reprendre",@"Quitter"];
        }
        capture(out,fullNames[i],bounds,nil,ov_view(bounds,q,d,theme,unused),0);
    }
    capture(out,@"hud-minimal",bounds,picture,nil,1);
    capture(out,@"hud-standard",bounds,picture,nil,2);
    NSDictionary *empty=ov_social([@"{\"profile\":{},\"friends\":{\"items\":[]},\"achievements\":{}}" dataUsingEncoding:NSUTF8StringEncoding]);
    for (NSArray *item in @[@[@(OV_PROFILE),@"profile-empty"],@[@(OV_FRIENDS),@"friends-empty"],
        @[@(OV_FRIENDS),@"friends-private"],@[@(OV_ACHIEVEMENTS),@"achievements-empty"],@[@(OV_SETTINGS),@"settings-empty"]]) {
        home_quit q={0}; hq_open(&q,HQ_FULL); q.tab=[item[0] intValue];
        NSMutableDictionary *d=[sample mutableCopy]; d[@"background"]=blurred; d[@"social"]=empty;
        d[@"canArcane"]=@NO;
        [d removeObjectsForKeys:@[@"total",@"controllerRows",@"network"]];
        d[@"controllers"]=@"0 connectée"; d[@"ldn"]=@"LDN désactivé"; d[@"volume"]=@"100 %";
        if ([item[1] isEqual:@"friends-private"])
            d[@"social"]=ov_social([@"{\"friends\":{\"shared\":false}}" dataUsingEncoding:NSUTF8StringEncoding]);
        capture(out,[@"overlay-full-" stringByAppendingString:item[1]],bounds,nil,ov_view(bounds,q,d,theme,unused),0);
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        settings();
        assert(([ov_tabs(nil) isEqual:@[@(OV_SESSION),@(OV_SETTINGS)]]));
        assert(([ov_tabs(@{@(OV_FRIENDS):@"Friends"}) isEqual:@[@(OV_SESSION),@(OV_FRIENDS),@(OV_SETTINGS)]]));
        assert(!ov_social([@"[]" dataUsingEncoding:NSUTF8StringEncoding]).count);
        assert(![ov_social([@"{\"achievements\":null}" dataUsingEncoding:NSUTF8StringEncoding]) objectForKey:@(OV_ACHIEVEMENTS)]);
        NSDictionary *social=ov_social([NSJSONSerialization dataWithJSONObject:@{
            @"profile":@{@"name":@"Koya Mori",@"nextendo":@"Koya",@"status":@"online",@"week":@"2 h 14 min",@"color":@"#9CCBFF"},
            @"friends":@{@"items":@[
                @{@"name":@"Milo",@"status":@"offline"},@{@"name":@"Lina",@"status":@"playing",@"game":@"Pokémon Legends: Z-A",@"color":@"#AFA7FA"},
                @{@"name":@"Camille",@"status":@"online",@"color":@"#75DBAC"},@{@"name":@"Noa",@"status":@"offline"},@{@"name":@"Sacha",@"status":@"offline"}]},
            @"achievements":@{@"unlocked":@12,@"total":@50,@"recent":@[@"Premiers pas",@"Explorateur d’Illumis",@"Premier partenaire"]}
        } options:0 error:NULL]);
        assert([social[@(OV_FRIENDS)][@"online"] intValue]==2);
        assert([social[@(OV_FRIENDS)][@"items"][0][@"name"] isEqual:@"Lina"]);
        home_quit small = {0}; hq_open(&small,HQ_FULL);
        NSRect smallBounds = NSMakeRect(0,0,640,360);
        NSView *smallView = ov_view(smallBounds,small,@{@"actions":@[@"Resume",@"Quit"]},ov_theme(nil),^(NSInteger a,NSInteger i) { (void)a; (void)i; });
        for (NSView *child in smallView.subviews) if ([child isKindOfClass:NSButton.class]) {
            assert(NSContainsRect(smallBounds,child.frame));
            assert((![@[@"Profile",@"Friends",@"Achievements",@"Return to Arcane"] containsObject:child.accessibilityLabel]));
        }
        const char *out = getenv("DM_OVERLAY_TEST_SCREENS"), *assets = getenv("DM_OVERLAY_TEST_ASSETS");
        NSRect bounds = NSMakeRect(0,0,1600,900);
        NSMutableDictionary *d = [@{@"fr":@YES, @"title":@"Pokémon Legends: Z-A", @"session":@"42 min", @"total":@"10 h 47 min",
            @"controllers":@"2 connectées", @"nextendo":@"Koya · en ligne", @"onlineAllowed":@YES, @"network":@"ZeroTier connecté", @"vpnUp":@YES,
            @"controllerRows":@[@{@"player":@1,@"name":@"Nintendo Switch Pro Controller"},@{@"player":@2,@"name":@"DualSense Wireless Controller"}],
            @"ldn":@"Salon LDN actif", @"ldnActive":@YES, @"volume":@"65 %",
            @"clock":@"21:42", @"canQuit":@YES, @"actions":@[@"Reprendre",@"Retour à Arcane",@"Quitter"],
            @"preset":@1, @"position":@"En haut à droite", @"size":@"Petit", @"opacity":@"50 %", @"scope":@"Pour ce jeu",
            @"quitTitle":@"Quitter Pokémon Legends: Z-A ?", @"social":social, @"canArcane":@YES} mutableCopy];
        for (int full=0; full<2; full++) {
            home_quit q = {0}; hq_open(&q,full ? HQ_FULL : HQ_QUICK);
            if (!full) q.card = HQ_HUD;
            __block NSInteger action = -1, index = -1;
            NSView *view = ov_view(bounds,q,d,ov_theme(nil),^(NSInteger a,NSInteger i) { action=a; index=i; });
            assert(view.isAccessibilityElement && view.subviews.count > 15);
            int chosen = 0;
            for (NSView *child in view.subviews) if ([child isKindOfClass:NSButton.class]) {
                NSButton *button = (NSButton *)child;
                assert(button.accessibilityLabel.length && NSContainsRect(bounds,child.frame));
                if ([button.accessibilityLabel isEqualToString:full ? @"Reprendre" : @"FPS discret"] && button.accessibilitySelected) {
                    [button performClick:nil]; chosen++;
                }
            }
            assert(chosen == 1 && action == (full ? OV_MAIN : OV_PRESET) && index == (full ? 0 : 1));
            q.confirm = 1; q.row = 0;
            view = ov_view(bounds,q,d,ov_theme(nil),^(NSInteger a,NSInteger i) { action=a; index=i; });
            chosen = 0;
            for (NSView *child in view.subviews) if ([child isKindOfClass:NSButton.class] && ((NSButton *)child).accessibilitySelected) {
                assert([child.accessibilityLabel isEqualToString:@"Annuler"]);
                [(NSButton *)child performClick:nil]; chosen++;
            }
            assert(chosen == 1 && action == OV_CONFIRM && index == 0);
        }
        home_quit full = {0}; hq_open(&full,HQ_FULL); full.tab=OV_SETTINGS;
        __block NSInteger used=-1, row=-1;
        void (^picked)(NSInteger,NSInteger)=^(NSInteger a,NSInteger i) { used=a; row=i; };
        NSView *settingsView=ov_view(bounds,full,d,ov_theme(nil),picked);
        for (NSView *child in settingsView.subviews) if ([child isKindOfClass:NSButton.class]) {
            assert(![child.accessibilityLabel isEqual:@"Quitter"]);
            if ([child.accessibilityLabel isEqual:@"Augmenter — HUD"]) [(NSButton *)child performClick:nil];
        }
        assert(used==OV_VALUE && row==HQ_HUD);
        full.tab=OV_PROFILE;
        NSView *profile=ov_view(bounds,full,d,ov_theme(nil),picked);
        for (NSView *child in profile.subviews)
            if ([child.accessibilityLabel isEqual:@"Voir dans Arcane"]) [(NSButton *)child performClick:nil];
        assert(used==OV_MAIN && row==0);
        if (out && assets) {
            d[@"cover"] = [[NSImage alloc] initWithContentsOfFile:[@(assets) stringByAppendingPathComponent:@"cover.png"]];
            assert(d[@"cover"]);
            screens(@(out),@(assets),bounds,d);
        }
        puts("Overlay AppKit, accessible actions, theme, keyboard bindings and HUD persistence: OK");
    }
}
