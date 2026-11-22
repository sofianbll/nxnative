// The AppKit overlay uses Selene's 1920×1080 design units and native accessible controls.
#pragma once
#import "overlay_settings_mac.h"
#import "home_quit.h"
#import "home_quit_mac.h"
#import <ImageIO/ImageIO.h>

enum { OV_MAIN, OV_TAB, OV_ROW, OV_BACK, OV_FULL, OV_CONFIRM, OV_PRESET, OV_VALUE };
enum { OV_SESSION, OV_SETTINGS, OV_PROFILE, OV_FRIENDS, OV_ACHIEVEMENTS, OV_TAB_COUNT };

static NSString *ov_text(BOOL fr, NSString *en) {
    if (!fr) return en;
    return @{
        @"Keep holding for quick access":@"Maintenir pour l’accès rapide", @"Cancel":@"Annuler", @"Resume":@"Reprendre",
        @"Quit":@"Quitter", @"Return to Arcane":@"Retour à Arcane", @"Unsaved progress will be lost.":@"La progression non sauvegardée sera perdue.",
        @"Session":@"Session", @"Game settings":@"Réglages du jeu", @"Quick access":@"Accès rapide", @"Profile":@"Profil", @"Friends":@"Amis", @"Achievements":@"Succès",
        @"Choose":@"Choisir", @"Back":@"Retour", @"Full overlay":@"Overlay complet",
        @"Game running":@"Jeu en cours", @"The game continues while the overlay is open.":@"Le jeu continue pendant que l’overlay est ouvert.",
        @"Play time":@"Temps de jeu", @"Controllers":@"Manettes", @"Game volume":@"Volume du jeu", @"Multiplayer":@"Jouer à plusieurs",
        @"Performance HUD":@"HUD de performance", @"Off":@"Désactivé", @"Minimal FPS":@"FPS discret", @"Full":@"Complet",
        @"Position":@"Position", @"Size":@"Taille", @"Opacity":@"Opacité", @"For this game":@"Pour ce jeu", @"For all games":@"Partout",
        @"Top left":@"En haut à gauche", @"Top right":@"En haut à droite", @"Bottom left":@"En bas à gauche", @"Bottom right":@"En bas à droite",
        @"Small":@"Petit", @"Medium":@"Moyen", @"Large":@"Grand", @"No controllers connected":@"Aucune manette connectée",
        @"VPN connected":@"VPN connecté", @"VPN not detected":@"VPN non détecté", @"ZeroTier connected":@"ZeroTier connecté",
        @"Signed in":@"Compte connecté", @"Not signed in":@"Aucun compte connecté", @"LDN enabled":@"LDN activé", @"LDN disabled":@"LDN désactivé",
        @"LDN room active":@"Salon LDN actif", @"VPN not configured":@"VPN non configuré",
        @"Online play allowed":@"Jeu en ligne autorisé", @"Online play unavailable":@"Jeu en ligne indisponible",
        @"connected":@"connectées", @"Decrease":@"Diminuer", @"Increase":@"Augmenter",
        @"Player %d":@"Joueur %d", @"Not assigned":@"Sans joueur", @"Connected":@"Connectée",
        @"Presence":@"Présence", @"This week":@"Cette semaine", @"Online":@"En ligne", @"Offline":@"Hors ligne",
        @"In game":@"En jeu", @"Presence not shared":@"Présence non partagée", @"No friends online":@"Aucun ami en ligne",
        @"%lu online of %lu":@"%lu en ligne sur %lu", @"Profile unavailable":@"Profil indisponible", @"View in Arcane":@"Voir dans Arcane",
        @"Nextendo account":@"Compte Nextendo", @"Overall progress":@"Progression globale", @"Recently unlocked":@"Derniers succès débloqués",
        @"No achievements unlocked":@"Aucun succès débloqué", @"Local":@"Local", @"Unavailable":@"Indisponible"
    }[en] ?: en;
}
static NSString *ov_home_help(BOOL fr, BOOL overrides) {
    if (overrides) return fr ?
        @"Pour utiliser Home ici : Réglages Système → Manettes de jeu → Bouton principal → ajoute ce jeu" :
        @"To use Home here: System Settings → Game Controllers → Home Button → add this game";
    return fr ? @"Pour utiliser Home ici : Réglages Système → Manettes de jeu → Raccourcis de manette" :
        @"To use Home here: System Settings → Game Controllers → Controller Shortcuts";
}

@interface DmOverlay : HqScrim
@property (copy) void (^choose)(NSInteger, NSInteger);
@property (strong) NSDictionary *palette;
@property (strong) NSImage *backdrop;
@property BOOL quick;
@end
@implementation DmOverlay
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    if (self.backdrop) [self.backdrop drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];
    NSColor *scrim = self.palette[@"scrim"]; CGFloat a = scrim.alphaComponent;
    const CGFloat stops[] = {0, .40, .68, 1}, levels[] = {.06, .04, .46, .90};
    const CGFloat fullStops[] = {0, .55, 1}, fullLevels[] = {.50, .52, .80};
    NSMutableArray *colors = [NSMutableArray array];
    for (int i = 0; i < (self.quick ? 4 : 3); i++)
        [colors addObject:[scrim colorWithAlphaComponent:a * (self.quick ? levels[i] : fullLevels[i])]];
    NSGradient *g = [[NSGradient alloc] initWithColors:colors atLocations:self.quick ? stops : fullStops colorSpace:NSColorSpace.sRGBColorSpace];
    [g drawFromPoint:NSZeroPoint toPoint:NSMakePoint(0, NSHeight(self.bounds)) options:0];
}
- (void)activate:(NSButton *)sender { self.choose(sender.tag / 256, sender.tag % 256 - 8); }
@end

typedef struct { CGFloat k, w, h; } ov_layout;
static NSRect ov_rect(ov_layout l, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    return NSMakeRect(x * l.k, y * l.k, w * l.k, h * l.k);
}
static NSView *ov_box(NSView *parent, NSRect frame, NSColor *fill, NSColor *stroke, CGFloat radius, CGFloat line) {
    NSView *v = [[NSView alloc] initWithFrame:frame]; v.wantsLayer = YES;
    v.layer.backgroundColor = fill.CGColor; v.layer.borderColor = stroke.CGColor;
    v.layer.cornerRadius = radius; v.layer.borderWidth = line; [parent addSubview:v]; return v;
}
static NSTextField *ov_label(NSView *parent, NSRect frame, NSString *text, CGFloat size, NSFontWeight weight, NSColor *ink, NSTextAlignment alignment) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.frame = frame; label.font = [NSFont systemFontOfSize:size weight:weight]; label.textColor = ink;
    label.lineBreakMode = NSLineBreakByTruncatingTail; label.alignment = alignment; [parent addSubview:label]; return label;
}
static NSTextField *ov_fps_label(NSString *text) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.alignment = NSTextAlignmentCenter; label.drawsBackground = YES;
    label.backgroundColor = ov_color(0x14181fbf); label.textColor = NSColor.whiteColor;
    label.wantsLayer = YES; label.layer.masksToBounds = YES; return label;
}
static NSString *ov_fps_text(int preset, double fps, double ms, NSString *history) {
    if (fps <= 0) return @"— FPS";
    if (preset == 1) return [NSString stringWithFormat:@"%.0f FPS",fps];
    if (preset == 3 && history.length) return [NSString stringWithFormat:@"%.0f FPS  ·  %.1f ms  %@",fps,ms,history];
    return [NSString stringWithFormat:@"%.0f FPS  ·  %.1f ms",fps,ms];
}
static void ov_fps_layout(NSTextField *label, NSRect bounds, ov_hud hud) {
    CGFloat k = fmax(.55, fmin(NSWidth(bounds)/1920, NSHeight(bounds)/1080));
    label.font = [NSFont monospacedDigitSystemFontOfSize:(15 + 5*hud.size)*k weight:NSFontWeightSemibold];
    CGFloat w = label.intrinsicContentSize.width + 12*k, h = (28 + 5*hud.size)*k;
    CGFloat x = hud.position & 1 ? NSWidth(bounds)-64*k-w : 64*k;
    CGFloat y = hud.position & 2 ? 40*k : NSHeight(bounds)-40*k-h;
    label.frame = NSMakeRect(x,y,w,h);
    label.layer.cornerRadius = 8*k;
    label.alphaValue = ov_hud_opacity[hud.opacity]/100.0;
}
static NSButton *ov_button(DmOverlay *v, NSRect frame, NSString *text, NSString *symbol, CGFloat size, NSColor *ink,
                      NSColor *fill, NSColor *stroke, CGFloat radius, CGFloat line, NSInteger action, NSInteger index, BOOL focus) {
    NSButton *b = [NSButton buttonWithTitle:text target:v action:@selector(activate:)];
    b.frame = frame; b.bordered = NO; b.tag = action * 256 + index + 8; b.wantsLayer = YES;
    b.layer.backgroundColor = fill.CGColor; b.layer.borderColor = stroke.CGColor; b.layer.borderWidth = line; b.layer.cornerRadius = radius;
    b.attributedTitle = [[NSAttributedString alloc] initWithString:symbol ? @"" : text attributes:@{
        NSFontAttributeName:[NSFont systemFontOfSize:hq_fit(text, size, MAX(NSWidth(frame) - size * .6, size))],
        NSForegroundColorAttributeName:ink }];
    b.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    if (symbol) {
        b.image = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:text]
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightMedium scale:NSImageSymbolScaleSmall]];
        b.imagePosition = NSImageOnly; b.contentTintColor = ink;
    }
    b.accessibilityLabel = text; b.accessibilitySelected = focus;
    [v addSubview:b]; return b;
}

static NSArray *ov_items(BOOL fr) {
    return @[@"HUD", ov_text(fr, @"Game volume"), ov_text(fr, @"Controllers"), ov_text(fr, @"Multiplayer"), ov_text(fr, @"Quit")];
}
static NSArray *ov_presets(BOOL fr) {
    return @[ov_text(fr, @"Off"), ov_text(fr, @"Minimal FPS"), @"Standard", ov_text(fr, @"Full")];
}
static NSArray<NSNumber *> *ov_tabs(NSDictionary *social) {
    NSMutableArray *tabs = [NSMutableArray arrayWithObject:@(OV_SESSION)];
    for (int i = OV_PROFILE; i < OV_TAB_COUNT; i++) if (social[@(i)]) [tabs addObject:@(i)];
    [tabs addObject:@(OV_SETTINGS)];
    return tabs;
}

static NSString *ov_string(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] > 160) return nil;
    NSString *s = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length && [s rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound ? s : nil;
}
static NSDictionary *ov_social(NSData *data) {
    if (!data.length || data.length > 512*1024) return @{};
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *profile = [json[@"profile"] isKindOfClass:NSDictionary.class] ? json[@"profile"] : nil;
    if (profile) out[@(OV_PROFILE)] = profile;
    NSDictionary *friends = [json[@"friends"] isKindOfClass:NSDictionary.class] ? json[@"friends"] : nil;
    if (friends) {
        NSMutableArray *online=[NSMutableArray array], *offline=[NSMutableArray array];
        NSArray *list=[friends[@"items"] isKindOfClass:NSArray.class] ? friends[@"items"] : @[];
        BOOL shared = ![friends[@"shared"] isEqual:@NO];
        if (shared) for (id item in [list subarrayWithRange:NSMakeRange(0,MIN(list.count,100))]) {
            if (![item isKindOfClass:NSDictionary.class] || !ov_string(item[@"name"])) continue;
            NSString *state = ov_string(item[@"status"]);
            [([state isEqual:@"online"] || [state isEqual:@"playing"] ? online : offline) addObject:item];
        }
        out[@(OV_FRIENDS)] = @{@"items":[online arrayByAddingObjectsFromArray:offline],@"online":@(online.count),@"shared":@(shared)};
    }
    NSDictionary *achievements = [json[@"achievements"] isKindOfClass:NSDictionary.class] ? json[@"achievements"] : nil;
    if (achievements) out[@(OV_ACHIEVEMENTS)] = achievements;
    return out;
}
static NSInteger ov_amount(id value, NSInteger max) {
    if (![value isKindOfClass:NSNumber.class]) return 0;
    double n = [value doubleValue]; return isfinite(n) && n > 0 ? (NSInteger)fmin(n,max) : 0;
}
static NSString *ov_presence(BOOL fr, NSDictionary *person) {
    NSString *status=ov_string(person[@"status"]), *game=ov_string(person[@"game"]);
    if ([status isEqual:@"playing"]) return game ? [NSString stringWithFormat:@"%@ · %@",ov_text(fr,@"In game"),game] : ov_text(fr,@"In game");
    return ov_text(fr,[status isEqual:@"online"] ? @"Online" : [status isEqual:@"offline"] ? @"Offline" : @"Presence not shared");
}
static BOOL ov_online(NSDictionary *person) {
    NSString *status=ov_string(person[@"status"]); return [status isEqual:@"online"] || [status isEqual:@"playing"];
}
static void ov_avatar(NSView *v, NSRect frame, NSDictionary *person, NSColor *surface, NSColor *ink, CGFloat k) {
    NSString *name=ov_string(person[@"name"]), *color=ov_string(person[@"color"]), *encoded=person[@"avatar"];
    unsigned rgba=0; char tail;
    NSColor *ring = color.length==7 && [color rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"#0123456789abcdefABCDEF"] invertedSet]].location==NSNotFound &&
        sscanf(color.UTF8String,"#%6x%c",&rgba,&tail)==1 ? ov_color((rgba<<8)|255) : [ink colorWithAlphaComponent:.38];
    CGFloat size=NSWidth(frame);
    NSView *circle=ov_box(v,frame,surface,ring,size/2,MAX(k,size*.018)); circle.layer.masksToBounds=YES;
    NSImage *image=nil;
    if ([encoded isKindOfClass:NSString.class] && encoded.length<=131072) {
        NSData *bytes=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
        CGImageSourceRef source=bytes ? CGImageSourceCreateWithData((__bridge CFDataRef)bytes,NULL) : NULL;
        if (source) {
            CGImageRef cg=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{
                (id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(id)kCGImageSourceThumbnailMaxPixelSize:@384 });
            if (cg) { image=[[NSImage alloc] initWithCGImage:cg size:NSZeroSize]; CGImageRelease(cg); }
            CFRelease(source);
        }
    }
    if (image) {
        NSImageView *iv=[NSImageView imageViewWithImage:image];
        iv.frame=NSInsetRect(circle.bounds,size*.035,size*.035); iv.wantsLayer=YES; iv.layer.cornerRadius=NSWidth(iv.frame)/2;
        iv.layer.masksToBounds=YES; [circle addSubview:iv];
    } else {
        NSMutableString *initials=[NSMutableString string];
        for (NSString *part in [name componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
            if (part.length) [initials appendString:[part substringWithRange:[part rangeOfComposedCharacterSequenceAtIndex:0]].uppercaseString];
            if (initials.length>=2) break;
        }
        ov_label(circle,NSMakeRect(0,size*.30,size,size*.44),initials.length ? initials : @"—",size*.29,NSFontWeightLight,ink,NSTextAlignmentCenter);
    }
}

static NSView *ov_view(NSRect bounds, home_quit q, NSDictionary *d, NSDictionary *theme, void (^choose)(NSInteger, NSInteger)) {
    BOOL fr = [d[@"fr"] boolValue], quick = q.phase == HQ_QUICK;
    DmOverlay *v = [[DmOverlay alloc] initWithFrame:bounds];
    v.choose = choose; v.palette = theme; v.quick = quick; v.backdrop = d[@"background"];
    v.accessibilityElement = YES; v.accessibilityRole = NSAccessibilityGroupRole;
    v.accessibilityLabel = ov_text(fr, quick ? @"Quick access" : @"Full overlay");
    CGFloat k = MAX(.01, MIN(NSWidth(bounds) / 1920, NSHeight(bounds) / 1080));
    ov_layout l = {k, NSWidth(bounds)/k, NSHeight(bounds)/k};
    CGFloat cx = l.w / 2;
    NSColor *ink = theme[@"ink"], *focus = theme[@"focus"], *on = theme[@"onFocus"], *surface = theme[@"surface"];
    NSColor *muted = [ink colorWithAlphaComponent:ink.alphaComponent * .7], *border = [ink colorWithAlphaComponent:.22];
    NSColor *soft = [ink colorWithAlphaComponent:.10], *green = ov_color(0x3ddc84ff);
#define R(x,y,w,h) ov_rect(l,x,y,w,h)
#define C(x,y,w,h,text,size,weight,color) ov_label(v,R(x,y,w,h),text,size*k,weight,color,NSTextAlignmentCenter)
#define L(x,y,w,h,text,size,weight,color) ov_label(v,R(x,y,w,h),text,size*k,weight,color,NSTextAlignmentLeft)
#define T(s) ov_text(fr, s)
    NSString *quit = d[@"quitLabel"] ?: T(@"Quit"), *resume = d[@"resume"] ?: T(@"Resume");
    NSArray *items = ov_items(fr), *symbols = @[@"speedometer", @"speaker.wave.2.fill", @"gamecontroller.fill", @"person.3.fill", @"power"];
    int count = [d[@"canQuit"] boolValue] ? 5 : 4;
    CGFloat rail = cx - (count - 1) * 48;

    if (quick) {
        for (int i = 0; i < count; i++) {
            CGFloat x = rail + 96*i, y = l.h - 105;
            BOOL selected = i == q.selection; CGFloat radius = selected ? 38.5 : 35;
            NSString *label = i == HQ_POWER ? quit : items[i];
            ov_button(v, R(x-radius,y-radius,2*radius,2*radius), label, symbols[i], (i == HQ_NETWORK ? 26 : 31)*k, ink,
                      selected ? soft : nil, selected ? focus : nil, radius*k, selected ? 3*k : 0, OV_MAIN, i, selected);
            if (selected) {
                C(x-150,y-102,300,25,label,18,NSFontWeightSemibold,ink);
                NSString *detail = i == HQ_HUD ? ov_presets(fr)[[d[@"preset"] intValue]] : i == HQ_VOLUME ? d[@"volume"] : nil;
                C(x-150,y-77,300,22,detail,14,NSFontWeightRegular,muted);
            }
        }
        NSString *status = d[@"network"] ? [NSString stringWithFormat:@"%@ · %@ %@", d[@"session"], @"●", d[@"network"]] : d[@"session"];
        NSTextField *label = C(0,l.h-51,l.w,23,status,16,NSFontWeightRegular,muted);
        if ([d[@"vpnUp"] boolValue]) {
            NSMutableAttributedString *text = [label.attributedStringValue mutableCopy];
            NSRange dot = [status rangeOfString:@"●"];
            if (dot.location != NSNotFound) [text addAttribute:NSForegroundColorAttributeName value:green range:dot];
            label.attributedStringValue = text;
        }
    } else {
        const CGFloat widths[] = {112, 174, 91, 84, 102};
        NSArray *labels = @[T(@"Session"),T(@"Game settings"),T(@"Profile"),T(@"Friends"),T(@"Achievements")];
        NSArray *tabs = ov_tabs(d[@"social"]); CGFloat total = 0;
        for (NSNumber *tab in tabs) total += widths[tab.intValue]+6;
        CGFloat left = cx-total/2, tx = left;
        for (NSNumber *tab in tabs) {
            int i = tab.intValue;
            BOOL selected = i == q.tab;
            ov_button(v,R(tx,36,widths[i],38),labels[i],nil,20*k,selected ? on : ink,
                      selected ? focus : nil,nil,19*k,0,OV_TAB,i,selected);
            tx += widths[i] + 6;
        }
        for (int i = 0; i < 2; i++) {
            CGFloat x = i ? tx+4 : left-46;
            ov_box(v,R(x,45,36,20),ink,nil,6*k,0);
            C(x,46,36,18,i ? @"RB" : @"LB",12,NSFontWeightSemibold,on);
        }
        ov_label(v,R(l.w-264,37,200,37),d[@"clock"],28*k,NSFontWeightLight,ink,NSTextAlignmentRight);
        CGFloat x = cx - 848, y = (l.h-1080)/2 + 320;
        NSDictionary *tabData = d[@"social"][@(q.tab)];
        CGFloat tabWidth=1040;
        if (q.tab == OV_PROFILE) {
            ov_avatar(v,R(x,y,340,340),tabData,surface,ink,k);
            x+=392;
            NSString *name=ov_string(tabData[@"name"]);
            L(x,y,l.w-x-112,65,name ?: T(@"Profile unavailable"),44,NSFontWeightRegular,ink);
            if ([d[@"canArcane"] boolValue] && name)
                ov_button(v,R(x,y+176,245,56),T(@"View in Arcane"),nil,21*k,on,focus,border,28*k,k,OV_MAIN,0,YES);
            NSArray *keys=@[T(@"Nextendo account"),T(@"Presence"),T(@"Play time"),T(@"This week")];
            NSArray *values=@[ov_string(tabData[@"nextendo"]) ?: @"—",ov_presence(fr,tabData),ov_string(d[@"total"]) ?: @"—",ov_string(tabData[@"week"]) ?: @""];
            CGFloat fx=x;
            for (int i=0;i<4;i++) {
                if (![values[i] length]) continue;
                CGFloat col=i==1 ? 272 : 180;
                if (i) ov_box(v,R(fx-20,y+294,1,46),border,nil,0,0);
                L(fx,y+294,col-30,19,[keys[i] uppercaseString],12,NSFontWeightSemibold,muted);
                if (i==1) ov_box(v,R(fx,y+324,8,8),ov_online(tabData) ? green : muted,nil,4*k,0);
                L(fx+(i==1 ? 16 : 0),y+314,col-34,29,values[i],21,NSFontWeightSemibold,ink);
                fx+=col;
            }
        } else if (q.tab == OV_FRIENDS) {
            NSArray *friends=tabData[@"items"] ?: @[];
            BOOL shared=[tabData[@"shared"] boolValue];
            NSUInteger online=[tabData[@"online"] unsignedIntegerValue];
            L(x,y-74,600,64,labels[q.tab],44,NSFontWeightRegular,ink);
            NSString *summary=!shared ? T(@"Presence not shared") : online ?
                [NSString stringWithFormat:T(@"%lu online of %lu"),(unsigned long)online,(unsigned long)friends.count] : T(@"No friends online");
            if (!friends.count) {
                ov_box(v,R(x,y,tabWidth,78),surface,border,16*k,k);
                L(x+24,y+24,tabWidth-48,30,summary,21,NSFontWeightRegular,ink);
            } else {
                ov_label(v,R(x+600,y-57,tabWidth-600,32),summary,20*k,NSFontWeightRegular,muted,NSTextAlignmentRight);
                NSInteger first=MAX(0,q.selection-4);
                for (NSInteger i=first;i<MIN((NSInteger)friends.count,first+5);i++) {
                    NSDictionary *person=friends[i]; BOOL selected=q.selection==i;
                    CGFloat yy=y+(i-first)*92;
                    ov_box(v,R(x,yy,tabWidth,80),surface,selected ? focus : border,16*k,(selected ? 2 : 1)*k);
                    ov_avatar(v,R(x+18,yy+13,54,54),person,surface,ink,k);
                    L(x+92,yy+13,tabWidth-122,30,ov_string(person[@"name"]),23,NSFontWeightSemibold,ink);
                    ov_box(v,R(x+93,yy+52,8,8),ov_online(person) ? green : muted,nil,4*k,0);
                    L(x+109,yy+44,tabWidth-140,26,ov_presence(fr,person),17,NSFontWeightRegular,muted);
                    ov_button(v,R(x,yy,tabWidth,80),@"",nil,20*k,ink,nil,nil,16*k,0,OV_MAIN,i,selected).accessibilityLabel=
                        [NSString stringWithFormat:@"%@, %@",ov_string(person[@"name"]),ov_presence(fr,person)];
                }
            }
        } else if (q.tab == OV_ACHIEVEMENTS) {
            NSInteger total=ov_amount(tabData[@"total"],100000), done=ov_amount(tabData[@"unlocked"],total);
            NSArray *recent=[tabData[@"recent"] isKindOfClass:NSArray.class] ? tabData[@"recent"] : @[];
            L(x,y-74,tabWidth,64,labels[q.tab],44,NSFontWeightRegular,ink);
            ov_box(v,R(x,y,tabWidth,118),surface,border,16*k,k);
            L(x+24,y+20,400,28,T(@"Overall progress"),21,NSFontWeightSemibold,ink);
            NSString *progress=total ? [NSString stringWithFormat:@"%ld / %ld · %ld %%",(long)done,(long)total,(long)lround(100.0*done/total)] : @"—";
            ov_label(v,R(x+600,y+20,tabWidth-624,28),progress,21*k,NSFontWeightSemibold,ink,NSTextAlignmentRight);
            ov_box(v,R(x+24,y+75,tabWidth-48,8),soft,nil,4*k,0);
            if (done) ov_box(v,R(x+24,y+75,(tabWidth-48)*(CGFloat)done/total,8),focus,nil,4*k,0);
            L(x,y+149,tabWidth,32,T(@"Recently unlocked"),23,NSFontWeightSemibold,ink);
            int tile=0;
            for (id item in recent) {
                if (tile==4) break;
                NSString *title=ov_string(item); if (!title) continue;
                CGFloat xx=x+tile++*264;
                ov_box(v,R(xx,y+195,248,156),surface,border,16*k,k);
                NSImageView *icon=hq_glyph(@"trophy.fill",@"star",25*k,focus); icon.frame=R(xx+22,y+217,33,33);
                [v addSubview:icon];
                L(xx+22,y+273,204,45,title,19,NSFontWeightSemibold,ink);
            }
            if (!tile) {
                ov_box(v,R(x,y+195,tabWidth,76),surface,border,16*k,k);
                L(x+24,y+217,tabWidth-48,30,T(@"No achievements unlocked"),20,NSFontWeightRegular,muted);
            }
        } else if (q.tab == OV_SETTINGS) {
            CGFloat w=q.card<0 ? tabWidth : 352;
            L(x,y-74,tabWidth,64,T(@"Game settings"),44,NSFontWeightRegular,ink);
            NSString *network=d[@"network"], *local=network ? [NSString stringWithFormat:@"%@ · %@",T(@"Local"),
                [network isEqual:T(@"ZeroTier connected")] ? @"ZeroTier" : network] : (d[@"ldn"] ?: T(@"Unavailable"));
            NSArray *values=@[ov_presets(fr)[MIN(3,MAX(0,[d[@"preset"] intValue]))],d[@"volume"] ?: @"—",d[@"controllers"] ?: @"—",local];
            for (int i=0;i<HQ_POWER;i++) {
                CGFloat yy=y+i*84; BOOL selected=q.selection==i;
                ov_box(v,R(x,yy,w,72),surface,selected ? focus : border,16*k,(selected ? 2 : 1)*k);
                BOOL cycle=q.card<0 && i<HQ_PADS;
                L(x+24,yy+22,q.card<0 ? w*.50 : w-48,35,items[i],23,NSFontWeightRegular,ink);
                if (q.card<0) {
                    NSString *value=cycle ? values[i] : [NSString stringWithFormat:@"%@   ›",values[i]];
                    ov_label(v,R(x+w*.53,yy+22,w*.47-(cycle ? 60 : 24),35),value,21*k,NSFontWeightSemibold,muted,NSTextAlignmentRight);
                }
                ov_button(v,R(x,yy,w,72),@"",nil,20*k,ink,nil,nil,16*k,0,OV_MAIN,i,selected).accessibilityLabel=
                    [NSString stringWithFormat:@"%@, %@",items[i],values[i]];
                if (cycle) for (int next=0;next<=1;next++) {
                    CGFloat span=fmax(86,[values[i] sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:21 weight:NSFontWeightSemibold]}].width);
                    CGFloat ax=x+w-(next ? 54 : 107+span);
                    ov_button(v,R(ax,yy+12,36,48),next ? @"›" : @"‹",nil,26*k,ink,nil,nil,0,0,OV_VALUE,next ? i : -i-1,NO).accessibilityLabel=
                        [NSString stringWithFormat:@"%@ — %@",T(next ? @"Increase" : @"Decrease"),items[i]];
                }
            }
        } else {
            NSImage *cover = d[@"cover"];
            if (cover && cover.size.width > 0 && cover.size.height > 0) {
                NSView *frame = ov_box(v,R(x,y,340,340),surface,border,12*k,k);
                CGFloat scale = 340*k / MIN(cover.size.width,cover.size.height);
                CGFloat w = cover.size.width*scale, h = cover.size.height*scale;
                NSImageView *image = [NSImageView imageViewWithImage:cover];
                image.frame = NSMakeRect((340*k-w)/2,(340*k-h)/2,w,h);
                image.imageScaling = NSImageScaleAxesIndependently; frame.layer.masksToBounds = YES;
                [frame addSubview:image];
                x += 392;
            }
            ov_box(v,R(x,y+4,8,8),green,nil,4*k,0);
            L(x+16,y,l.w-x-64,19,T(@"Game running").uppercaseString,12,NSFontWeightSemibold,muted);
            L(x,y+25,l.w-x-64,60,d[@"title"],44,NSFontWeightRegular,ink);
            L(x,y+88,l.w-x-64,28,T(@"The game continues while the overlay is open."),18,NSFontWeightRegular,muted);
            NSArray *actions = d[@"actions"] ?: @[resume, quit]; CGFloat ax = x;
            for (NSUInteger i = 0; i < actions.count; i++) {
                BOOL selected = i == (NSUInteger)q.selection; NSString *title = actions[i];
                CGFloat width = fmin(300,fmax(200,[title sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:21]}].width + 68));
                CGFloat grow = selected ? 1.06 : 1;
                ov_button(v,R(ax-width*(grow-1)/2,y+176-27*(grow-1),width*grow,54*grow),title,nil,21*k,selected ? on : ink,
                          selected ? focus : [surface colorWithAlphaComponent:.76],border,27*k*grow,k,OV_MAIN,i,selected);
                ax += width + 16;
            }
            NSArray *labels = @[T(@"Session"),T(@"Play time"),T(@"Controllers"),@"Nextendo"];
            NSArray *values = @[d[@"session"] ?: @"",d[@"total"] ?: @"",d[@"controllers"] ?: @"",d[@"nextendo"] ?: @""];
            CGFloat fx = x;
            for (int i = 0; i < 4; i++) {
                NSString *val = values[i]; if (!val.length) continue;
                NSString *title = [labels[i] uppercaseString];
                CGFloat width = fmin(270,fmax([title sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12]}].width,
                    [val sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:21 weight:NSFontWeightSemibold]}].width) + 8);
                if (fx > x) { ov_box(v,R(fx,y+294,1,46),border,nil,0,0); fx += 28; }
                L(fx,y+294,width,19,title,12,NSFontWeightSemibold,muted);
                CGFloat dot = i==3 && [d[@"onlineAllowed"] boolValue] ? 16 : 0;
                if (dot) ov_box(v,R(fx,y+324,8,8),green,nil,4*k,0);
                L(fx+dot,y+314,i==3 ? l.w-fx-64-dot : width+4,29,val,21,NSFontWeightSemibold,ink);
                fx += width + 20;
            }
        }
    }

    if (q.card >= 0 && q.card < count && !q.confirm) {
        NSArray *pads = d[@"controllerRows"];
        NSArray *rows = q.card == HQ_HUD ? @[T(@"Position"),T(@"Size"),T(@"Opacity")] :
            q.card == HQ_VOLUME ? @[T(@"Game volume")] : q.card == HQ_PADS ? (pads ?: @[]) :
            @[d[@"ldn"] ?: T(@"LDN disabled"),d[@"network"] ?: T(@"VPN not configured")];
        if (!rows.count) rows = @[T(@"No controllers connected")];
        NSUInteger visible = MIN(rows.count, 8);
        CGFloat w = 520, h = q.card == HQ_HUD ? 292 : q.card == HQ_VOLUME ? 130 : 68+56*visible+(rows.count>visible ? 26 : 0);
        CGFloat x = quick ? fmax(30,fmin(rail+96*q.selection-w/2,l.w-w-30)) : cx-478;
        CGFloat y = quick ? l.h-230-h : (l.h-1080)/2+320;
        ov_box(v,R(x,y,w,h),surface,border,18*k,k);
        L(x+36,y+18,340,28,q.card == HQ_HUD ? T(@"Performance HUD") : items[q.card],21,NSFontWeightSemibold,ink);
        int first = 0;
        if (q.card == HQ_HUD) {
            NSString *scope = d[@"scope"] ?: T(@"For this game");
            ov_button(v,R(x+380,y+20,110,26),scope.uppercaseString,nil,12*k,ink,soft,q.row==4 ? focus : nil,13*k,k,OV_ROW,4,q.row==4);
            ov_box(v,R(x+10,y+62,w-20,52),q.row==0 ? soft : nil,q.row==0 ? focus : nil,12*k,2*k);
            NSArray *presets = ov_presets(fr);
            for (int i = 0; i < 4; i++) {
                BOOL selected = i == [d[@"preset"] intValue];
                ov_button(v,R(x+15+i*122.5,y+67,122,42),presets[i],nil,17*k,selected ? ov_color(0x111111ff) : muted,
                          selected ? ov_color(0x9ccbffff) : nil,nil,7*k,0,OV_PRESET,i,selected);
            }
            first = 1;
        } else if (q.card == HQ_VOLUME) {
            CGFloat fraction = fmax(0,fmin(1,[d[@"volume"] intValue]/100.0));
            ov_box(v,R(x+10,y+62,w-20,52),soft,focus,12*k,2*k);
            CGFloat track=x+100, width=234, cy=y+88;
            ov_box(v,R(track,cy-3,width,6),[ink colorWithAlphaComponent:.30],nil,3*k,0);
            if (fraction > 0) ov_box(v,R(track,cy-3,width*fraction,6),focus,nil,3*k,0);
            ov_box(v,R(track+width*fraction-8,cy-8,16,16),focus,nil,8*k,0);
            C(x+344,y+76,108,26,d[@"volume"],17,NSFontWeightSemibold,ink);
            for (int i=0; i<2; i++) {
                ov_button(v,R(x+(i ? 454 : 26),y+69,40,38),i ? @"▸" : @"◂",nil,20*k,ink,nil,nil,0,0,OV_ROW,i-1,NO);
                ((NSButton *)v.subviews.lastObject).accessibilityLabel = i ? T(@"Increase") : T(@"Decrease");
            }
            visible = 0;
        }
        for (NSUInteger i=0; i<visible; i++) {
            CGFloat ry = y+62+(first+i)*56;
            if (q.card == HQ_HUD) {
                NSInteger row = i+first; BOOL selected = row == q.row;
                NSArray *values = @[d[@"position"] ?: @"",d[@"size"] ?: @"",d[@"opacity"] ?: @""];
                if (selected) ov_box(v,R(x+10,ry,w-20,52),soft,focus,12*k,2*k);
                L(x+36,ry+15,235,24,rows[i],18,NSFontWeightRegular,ink);
                C(x+303,ry+15,174,24,values[i],17,NSFontWeightSemibold,ink);
                ov_button(v,R(x+274,ry+9,45,34),@"◂",nil,18*k,muted,nil,nil,0,0,OV_ROW,-row-1,NO);
                ((NSButton *)v.subviews.lastObject).accessibilityLabel = [NSString stringWithFormat:@"%@ — %@",T(@"Decrease"),rows[i]];
                ov_button(v,R(x+461,ry+9,45,34),@"▸",nil,18*k,muted,nil,nil,0,0,OV_ROW,row,NO);
                ((NSButton *)v.subviews.lastObject).accessibilityLabel = [NSString stringWithFormat:@"%@ — %@",T(@"Increase"),rows[i]];
            } else if (q.card == HQ_PADS && pads.count) {
                int player = [pads[i][@"player"] intValue];
                NSString *slot = player ? [NSString stringWithFormat:T(@"Player %d"),player] : T(@"Not assigned");
                L(x+36,ry+2,360,18,slot,13,NSFontWeightSemibold,muted);
                L(x+36,ry+21,335,26,pads[i][@"name"],18,NSFontWeightRegular,ink);
                ov_box(v,R(x+380,ry+27,8,8),green,nil,4*k,0);
                L(x+396,ry+22,100,23,T(@"Connected"),14,NSFontWeightRegular,muted);
            } else {
                BOOL active = q.card == HQ_NETWORK && [d[i==0 ? @"ldnActive" : @"vpnUp"] boolValue];
                if (q.card == HQ_NETWORK) ov_box(v,R(x+36,ry+18,8,8),active ? green : muted,nil,4*k,0);
                L(x+(q.card==HQ_NETWORK ? 54 : 36),ry+9,w-92,29,rows[i],18,NSFontWeightRegular,ink);
            }
        }
        if (q.card == HQ_PADS && rows.count > visible)
            L(x+36,y+h-30,w-72,22,([NSString stringWithFormat:@"+%lu",(unsigned long)(rows.count-visible)]),16,NSFontWeightSemibold,muted);
    }

    if (q.confirm) {
        // Keep the confirmation the only accessible choice until it is dismissed.
        for (NSView *child in v.subviews.copy) [child removeFromSuperview];
        CGFloat x=cx-300, y=l.h/2-119;
        ov_box(v,R(x,y,600,238),surface,border,24*k,k);
        C(x+24,y+32,552,48,d[@"quitTitle"],34,NSFontWeightSemibold,ink);
        C(x+30,y+90,540,30,d[@"quitNote"] ?: T(@"Unsaved progress will be lost."),20,NSFontWeightRegular,muted);
        for (int i = 0; i<2; i++) {
            BOOL selected = q.row == i;
            ov_button(v,R(x+78+i*228,y+151,216,54),i ? quit : (d[@"cancel"] ?: T(@"Cancel")),nil,21*k,
                      selected ? on : ink,selected ? focus : soft,border,27*k,k,OV_CONFIRM,i,selected);
        }
    }
    if (d[@"homeHelp"] && !q.confirm && q.card < 0)
        C(190,quick ? l.h-248 : l.h-135,l.w-380,23,d[@"homeHelp"],16,NSFontWeightRegular,muted);
    NSString *back = !quick && q.card < 0 && !q.tab && !q.confirm ? resume : T(@"Back");
    NSMutableArray *hints = [NSMutableArray arrayWithObject:@[@"B",back,@(OV_BACK)]];
    if (q.confirm || q.tab < OV_PROFILE || (q.tab==OV_PROFILE && [d[@"canArcane"] boolValue] && ov_string(d[@"social"][@(OV_PROFILE)][@"name"])))
        [hints addObject:@[@"A",T(@"Choose"),@(-1)]];
    if (quick && !q.confirm) [hints addObject:@[@"Y",T(@"Full overlay"),@(OV_FULL)]];
    CGFloat right = l.w-64;
    for (NSArray *hint in hints) {
        NSString *letter = hint[0], *label = hint[1]; NSInteger action = [hint[2] integerValue];
        CGFloat w = ceil([label sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:21]}].width) + 3;
        CGFloat x = action == OV_BACK ? 64 : right-w-42;
        if (action != OV_BACK) right = x-18;
        ov_box(v,R(x,l.h-80,32,32),ink,nil,16*k,0);
        C(x,l.h-74,32,20,letter,16,NSFontWeightSemibold,on);
        if (action >= 0) ov_button(v,R(x+36,l.h-82,w+8,36),label,nil,21*k,ink,nil,nil,0,0,action,0,NO);
        else L(x+42,l.h-77,w+8,28,label,21,NSFontWeightRegular,ink);
    }
#undef T
#undef L
#undef C
#undef R
    return v;
}
