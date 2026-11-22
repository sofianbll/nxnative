#import "../game_overlay_mac.h"
#import <CoreImage/CoreImage.h>
#include <assert.h>
#import "../front.h"

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
    assert(hud.preset == HUD_FPS && hud.local && hud.position == 2 && hud.scale == .2 && hud.opacity == .5);
    NSString *original=@"MTL_HUD_HIDE_METALFX_METRICS=1 MTL_HUD_OPACITY=0.5 MTL_HUD_ENABLED=1 MTL_HUD_ALIGNMENT=12 MTL_HUD_ELEMENTS=device,rosetta,layersize,memory,fps,frameinterval,frameintervalhistogram,metalcpu,gputimeline,shaders,framenumber,frameintervalgraph,presentdelay,gputime,thermal,layerscale,refreshrate,gamemode,edrheadroom,client";
    NSUInteger ignored;
    assert(ov_hud_import(original,&hud,&ignored) && !ignored);
    assert(hud.preset==HUD_CUSTOM && hud.elements==0x89c79aff && hud.options==(1u<<6) && hud.enabled && hud.position==2 && hud.opacity==.5);
    assert(ov_hud_import(@"MTL_HUD_SCALE=.3234 MTL_HUD_FUTURE=1 MTL_HUD_OPACITY=nan",&hud,&ignored) && ignored==2);
    assert(!ov_hud_import(@"MTL_HUD_CONFIG_FILE=/tmp/untrusted",&hud,&ignored) && ignored==1);
    assert(!ov_hud_import(@"not a config",&hud,&ignored) && !ignored);
    assert(hud.scale==.3234 && hud.opacity==.5);
    ov_hud copy=ov_hud_default;
    assert(ov_hud_import(ov_hud_export(hud),&copy,&ignored) && !ignored && [ov_hud_config(copy) isEqual:ov_hud_config(hud)]);
    NSData *plist=[NSPropertyListSerialization dataWithPropertyList:ov_hud_config(hud) format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    assert(ov_hud_import([[NSString alloc] initWithData:plist encoding:NSUTF8StringEncoding],&copy,&ignored) &&
        !ignored && [ov_hud_config(copy) isEqual:ov_hud_config(hud)]);
    ov_hud_save(store,@"game-a",hud);
    assert(ov_hud_load(store,@"game-b").preset == HUD_FPS);
    store = [[NSUserDefaults alloc] initWithSuiteName:domain];
    hud = ov_hud_load(store,@"game-a");
    assert(hud.preset==HUD_CUSTOM && hud.local && [ov_hud_config(copy) isEqual:ov_hud_config(hud)]);
    hud.local = NO; ov_hud_save(store,@"game-a",hud);
    assert(![store objectForKey:@"game-a"] && ov_hud_load(store,@"game-b").preset == HUD_CUSTOM && !ov_hud_load(store,@"game-b").local);
    [store setObject:@[@3,@2,@1,@4] forKey:@"game-a"];
    hud=ov_hud_load(store,@"game-a"); assert(hud.preset==HUD_FULL && hud.position==6 && fabs(hud.scale-.3)<1e-9 && hud.opacity==1);
    [store setObject:@[@3,@2,@1,@"bad"] forKey:@"game-a"];
    assert(ov_hud_load(store,@"game-a").preset == HUD_FPS);
    assert(!ov_fullscreen_load(store,@"game-a",NULL) && ov_fullscreen_load(store,@"game-a","1"));
    ov_fullscreen_save(store,@"game-a",YES);
    assert(ov_fullscreen_load(store,@"game-a","0") && !ov_fullscreen_load(store,@"game-b","0"));
    ov_fullscreen_save(store,@"game-a",NO);
    assert(!ov_fullscreen_load(store,@"game-a","1"));
    assert(!ov_home_swap_load(store,NULL) && ov_home_swap_load(store,"1"));
    [store setBool:YES forKey:@"home-swap"];
    assert(ov_home_swap_load(store,NULL) && !ov_home_swap_load(store,"0"));
    [store removePersistentDomainForName:domain];
    NSArray *native=@[@"",@"fps",@"device,rosetta,layersize,memory,fps,frameinterval,frameintervalgraph,gputime,gamemode,client",
        @"device,rosetta,layersize,memory,fps,frameinterval,metalcpu,shaders,frameintervalgraph,presentdelay,gputime,thermal,gamemode,client",
        @"device,rosetta,layersize,memory,fps,frameinterval,frameintervalhistogram,metalcpu,gputimeline,shaders,framenumber,frameintervalgraph,presentdelay,gputime,thermal,layerscale,refreshrate,gamemode,client"];
    for (int i=0;i<HUD_CUSTOM;i++) {
        hud=ov_hud_default; hud.options=2; ov_hud_select(&hud,i);
        NSDictionary *d=ov_hud_properties(hud);
        if (i==HUD_OFF) { assert([d isEqual:@{@"mode":@"disabled"}] && !hud.elements); continue; }
        assert([[NSSet setWithArray:[d[@"MTL_HUD_ELEMENTS"] componentsSeparatedByString:@","]] isEqual:
                [NSSet setWithArray:[native[i] componentsSeparatedByString:@","]]]);
        assert([d[@"mode"] isEqual:i==HUD_OFF ? @"disabled" : @"default"] && [d[@"MTL_HUD_ALIGNMENT"] isEqual:@12]);
        if (i==HUD_FPS) assert([d[@"MTL_HUD_ENCODER_TIMING_ENABLED"] isEqual:@0]);
    }
    // DM_METAL_HUD still enables Metal's HUD at launch; 0 leaves it to the saved choice
    unsetenv("MTL_HUD_ENABLED"); setenv("DM_METAL_HUD","0",1); front_hud_env(); assert(!getenv("MTL_HUD_ENABLED"));
    setenv("DM_METAL_HUD","1",1); front_hud_env(); assert(!strcmp(getenv("MTL_HUD_ENABLED"),"1"));
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

static NSBitmapImageRep *capture(NSString *out, NSString *name, NSRect bounds, NSImage *picture, NSView *overlay) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NSView *stage = [[NSView alloc] initWithFrame:bounds];
    window.contentView = stage;
    if (picture) {
        NSImageView *image = [NSImageView imageViewWithImage:picture]; image.frame = bounds;
        image.imageScaling = NSImageScaleAxesIndependently;
        [stage addSubview:image];
    }
    if (overlay) {
        for (NSView *child in overlay.subviews) assert(NSContainsRect(bounds,child.frame));
        [stage addSubview:overlay];
    }
    [stage layoutSubtreeIfNeeded]; [stage displayIfNeeded];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:NSWidth(bounds) pixelsHigh:NSHeight(bounds)
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    assert(rep.pixelsWide == 1600 && rep.pixelsHigh == 900);
    [stage cacheDisplayInRect:bounds toBitmapImageRep:rep];
    if (out) {
        NSString *path = [out stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
        assert([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
        printf("%s\n",path.UTF8String);
    }
    return rep;
}

static BOOL white_at(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSColor *pixel = [[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return pixel.redComponent > .9 && pixel.greenComponent > .9 && pixel.blueComponent > .9 && pixel.alphaComponent > .9;
}

static void avatars(NSString *out, NSRect bounds, NSDictionary *sample) {
    NSMutableDictionary *d = [sample mutableCopy];
    home_quit q = {0}; hq_open(&q,HQ_FULL); q.tab=OV_PROFILE;
    BOOL fills=YES;
    for (int wide=0; wide<2; wide++) {
        // The small square must grow; the wide image must show only its white center.
        NSImage *fixture = [NSImage imageWithSize:NSMakeSize(wide ? 360 : 36,wide ? 120 : 36) flipped:NO
            drawingHandler:^BOOL(NSRect rect) {
                [NSColor.redColor setFill]; NSRectFill(rect);
                [NSColor.whiteColor setFill]; NSRectFill(NSInsetRect(rect,wide ? 120 : 0,0));
                return YES;
            }];
        NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:fixture.TIFFRepresentation];
        NSString *avatar = [[bitmap representationUsingType:NSBitmapImageFileTypeJPEG properties:@{}] base64EncodedStringWithOptions:0];
        assert(avatar.length && avatar.length<=131072);
        d[@"social"] = ov_social([NSJSONSerialization dataWithJSONObject:@{
            @"profile":@{@"name":@"Test profile",@"avatar":avatar}
        } options:0 error:NULL]);
        NSView *overlay = ov_view(bounds,q,d,ov_theme(nil),^(NSInteger a,NSInteger i) {});
        NSBitmapImageRep *rep = capture(out,wide ? @"avatar-wide" : @"avatar-square",bounds,nil,overlay);
        // The frame spans x=93…376, y=267…550 in the 1600×900 capture.
        fills &= white_at(rep,235,408) && white_at(rep,235,275) && white_at(rep,101,408)
            && !white_at(rep,101,275) && !white_at(rep,95,408);
    }
    assert(fills && "personal portraits must fill a centered circular frame");
}
static void screens(NSString *out, NSString *assets, NSRect bounds, NSDictionary *sample) {
    NSImage *picture = backdrop(assets,NO), *blurred = backdrop(assets,YES);
    NSDictionary *theme = ov_theme(nil);
    void (^unused)(NSInteger,NSInteger) = ^(NSInteger a,NSInteger i) { (void)a; (void)i; };
    NSArray *quickNames = @[@"overlay-quick-hud",@"overlay-quick-volume",@"overlay-quick-controllers",@"overlay-quick-multiplayer",
        @"overlay-quick-display-windowed",@"overlay-quick-quit",@"overlay-quick-display-fullscreen",@"overlay-quick-hud-advanced",
        @"overlay-quick-hud-slider",@"overlay-quick-hud-pasted",@"overlay-quick-home-help"];
    for (int i=0; i<(int)quickNames.count; i++) {
        home_quit q = {0}; hq_open(&q,HQ_QUICK);
        q.selection = i<=HQ_POWER ? i : i==6 ? HQ_DISPLAY : HQ_HUD;
        if (q.selection<HQ_DISPLAY && i!=10) q.card = q.selection;
        q.confirm = i==HQ_POWER;
        NSMutableDictionary *d = [sample mutableCopy];
        d[@"fullscreen"]=@(i==6);
        if (i==7 || i==9) { q.advanced=1; q.row=i==9 ? HUD_PASTE : HUD_FIRST_OPTION+1; }
        if (i==8) { q.row=HUD_OPACITY_ROW; d[@"opacity"]=@.63; d[@"shoulders"]=@[@"L",@"R",@"ZL",@"ZR"]; }
        if (i==9) { d[@"preset"]=@(HUD_CUSTOM); d[@"hudNotice"]=@"Configuration collée · Ignorés : 1"; }
        if (i==10) d[@"homeHelp"] = ov_home_help(YES,YES);
        capture(out,quickNames[i],bounds,picture,ov_view(bounds,q,d,theme,unused));
    }
    NSArray *fullNames = @[@"overlay-full",@"overlay-full-settings",@"overlay-full-profile",@"overlay-full-friends",@"overlay-full-achievements",
        @"overlay-full-standalone",@"overlay-full-home-reversed"];
    for (NSUInteger i=0; i<fullNames.count; i++) {
        home_quit q = {0}; hq_open(&q,HQ_FULL); q.tab = i<OV_TAB_COUNT ? (int)i : OV_SESSION;
        NSMutableDictionary *d = [sample mutableCopy]; d[@"background"] = blurred;
        if (i==OV_TAB_COUNT+1) { q.tab=OV_SETTINGS; q.selection=HQ_HOME_SETTING; q.swap=1; }
        if (i==OV_TAB_COUNT) {
            [d removeObjectsForKeys:@[@"cover",@"total",@"social"]];
            d[@"actions"] = @[@"Reprendre",@"Quitter"];
        }
        capture(out,fullNames[i],bounds,nil,ov_view(bounds,q,d,theme,unused));
    }
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
        capture(out,[@"overlay-full-" stringByAppendingString:item[1]],bounds,nil,ov_view(bounds,q,d,theme,unused));
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
            @"preset":@1, @"position":@2, @"scale":@.2, @"opacity":@.5, @"scope":@"Pour ce jeu", @"hudEnabled":@YES, @"hudElements":@0x10,
            @"quitTitle":@"Quitter Pokémon Legends: Z-A ?", @"social":social, @"canArcane":@YES} mutableCopy];
        for (int full=0; full<2; full++) {
            home_quit q = {0}; hq_open(&q,full ? HQ_FULL : HQ_QUICK);
            if (!full) { q.card = HQ_HUD; q.row=HUD_ADVANCED_ROW; }
            __block NSInteger action = -1, index = -1;
            NSView *view = ov_view(bounds,q,d,ov_theme(nil),^(NSInteger a,NSInteger i) { action=a; index=i; });
            assert(view.isAccessibilityElement && view.subviews.count > 15);
            int chosen = 0;
            for (NSView *child in view.subviews) if ([child isKindOfClass:NSButton.class]) {
                NSButton *button = (NSButton *)child;
                assert(button.accessibilityLabel.length && NSContainsRect(bounds,child.frame));
                if ([button.accessibilityLabel isEqualToString:full ? @"Reprendre" : @"Avancé"] && button.accessibilitySelected) {
                    [button performClick:nil]; chosen++;
                }
            }
            assert(chosen == 1 && action == (full ? OV_MAIN : OV_HUD_PAGE) && index == (full ? 0 : 1));
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
        home_quit sliderState={0}; hq_open(&sliderState,HQ_QUICK); sliderState.card=HQ_HUD; sliderState.row=HUD_OPACITY_ROW;
        NSView *sliderView=ov_view(bounds,sliderState,d,ov_theme(nil),picked);
        for (NSView *child in sliderView.subviews) if ([child isKindOfClass:DmHudSlider.class] && [child.accessibilityLabel isEqual:@"Opacité"]) {
            DmHudSlider *slider=(DmHudSlider *)child;
            slider.doubleValue=.6312;
            slider.trackingMouse=YES;
            [slider sendAction:slider.action to:slider.target];
            assert([slider.valueLabel.stringValue isEqual:@"63 %"]);
        }
        assert(used==OV_SLIDE && row==HUD_OPACITY_ROW*10001+6312);
        for (int mode=0;mode<2;mode++) {
            home_quit q={0}; hq_open(&q,HQ_QUICK); q.selection=HQ_DISPLAY;
            d[@"fullscreen"]=@(mode);
            NSView *view=ov_view(bounds,q,d,ov_theme(nil),picked);
            for (NSView *child in view.subviews)
                if ([child.accessibilityLabel isEqual:mode ? @"Fenêtre" : @"Plein écran"]) [(NSButton *)child performClick:nil];
            assert(used==OV_MAIN && row==HQ_DISPLAY);
            used=-1;
        }
        full.tab=OV_PROFILE;
        NSView *profile=ov_view(bounds,full,d,ov_theme(nil),picked);
        for (NSView *child in profile.subviews)
            if ([child.accessibilityLabel isEqual:@"Voir dans Arcane"]) [(NSButton *)child performClick:nil];
        assert(used==OV_MAIN && row==0);
        avatars(out ? @(out) : nil,bounds,d);
        if (out && assets) {
            d[@"cover"] = [[NSImage alloc] initWithContentsOfFile:[@(assets) stringByAppendingPathComponent:@"cover.png"]];
            assert(d[@"cover"]);
            screens(@(out),@(assets),bounds,d);
        }
        puts("Overlay AppKit, accessible actions, theme, keyboard bindings and HUD persistence: OK");
    }
}
