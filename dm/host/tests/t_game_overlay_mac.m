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

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        settings();
        assert(([ov_tabs(nil) isEqual:@[@(OV_SESSION),@(OV_SETTINGS)]]));
        assert(([ov_tabs(@{@(OV_FRIENDS):@"Friends"}) isEqual:@[@(OV_SESSION),@(OV_FRIENDS),@(OV_SETTINGS)]]));
        home_quit small = {0}; hq_open(&small,HQ_FULL);
        NSRect smallBounds = NSMakeRect(0,0,640,360);
        NSView *smallView = ov_view(smallBounds,small,@{@"actions":@[@"Resume",@"Quit"]},ov_theme(nil),^(NSInteger a,NSInteger i) { (void)a; (void)i; });
        for (NSView *child in smallView.subviews) if ([child isKindOfClass:NSButton.class]) {
            assert(NSContainsRect(smallBounds,child.frame));
            assert(![child.accessibilityLabel isEqualToString:@"Profile"]);
        }
        const char *out = getenv("DM_OVERLAY_TEST_SCREENS"), *assets = getenv("DM_OVERLAY_TEST_ASSETS");
        NSRect bounds = NSMakeRect(0,0,1600,900);
        for (int full=0; full<2; full++) {
            home_quit q = {0}; hq_open(&q,full ? HQ_FULL : HQ_QUICK);
            if (!full) q.card = HQ_HUD;
            NSMutableDictionary *d = [@{@"fr":@YES, @"title":@"Pokémon Legends: Z-A", @"session":@"42 min", @"total":@"10 h 47 min",
                @"controllers":@"2 connectées", @"nextendo":@"Koya · en ligne", @"onlineAllowed":@YES, @"network":@"ZeroTier connecté", @"vpnUp":@YES,
                @"clock":@"21:42", @"canQuit":@YES, @"actions":@[@"Reprendre",@"Retour à Arcane",@"Quitter"],
                @"preset":@1, @"position":@"En haut à droite", @"size":@"Petit", @"opacity":@"50 %", @"scope":@"Pour ce jeu",
                @"quitTitle":@"Quitter ?"} mutableCopy];
            if (out && assets) {
                d[@"background"] = backdrop(@(assets),full);
                d[@"cover"] = [[NSImage alloc] initWithContentsOfFile:[@(assets) stringByAppendingPathComponent:@"cover.png"]];
                if (full) d[@"social"] = @{@(OV_PROFILE):@"Koya",@(OV_FRIENDS):@"1 ami",@(OV_ACHIEVEMENTS):@"3 succès"};
            }
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
            if (!full && out && assets) {
                NSTextField *fps = ov_fps_label(@"60 FPS");
                fps.frame = NSMakeRect(1494,33,53,23); fps.alphaValue=.5;
                fps.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold]; fps.layer.cornerRadius=7;
                [view addSubview:fps];
            }
            if (out && assets) {
                NSWindow *window = [[NSWindow alloc] initWithContentRect:bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
                window.contentView = view; [view layoutSubtreeIfNeeded]; [view displayIfNeeded];
                NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:bounds];
                [view cacheDisplayInRect:bounds toBitmapImageRep:rep];
                NSString *path = [@(out) stringByAppendingPathComponent:full ? @"overlay-full.png" : @"overlay-quick.png"];
                assert([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
                printf("%s\n",path.UTF8String);
            }
            q.confirm = 1; q.row = 0;
            view = ov_view(bounds,q,d,ov_theme(nil),^(NSInteger a,NSInteger i) { action=a; index=i; });
            chosen = 0;
            for (NSView *child in view.subviews) if ([child isKindOfClass:NSButton.class] && ((NSButton *)child).accessibilitySelected) {
                assert([child.accessibilityLabel isEqualToString:@"Annuler"]);
                [(NSButton *)child performClick:nil]; chosen++;
            }
            assert(chosen == 1 && action == OV_CONFIRM && index == 0);
        }
        puts("Overlay AppKit, accessible actions, theme, keyboard bindings and HUD persistence: OK");
    }
}
