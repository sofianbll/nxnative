// The AppKit overlay uses Selene's 1920×1080 design units and native accessible controls.
#pragma once
#import "overlay_settings_mac.h"
#import "home_quit.h"
#import "home_quit_mac.h"

enum { OV_MAIN, OV_TAB, OV_ROW, OV_BACK, OV_FULL, OV_CONFIRM, OV_PRESET };
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
        @"connected":@"connectées", @"Decrease":@"Diminuer", @"Increase":@"Augmenter"
    }[en] ?: en;
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
- (void)activate:(NSButton *)sender { self.choose(sender.tag / 64, sender.tag % 64 - 8); }
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
static void ov_button(DmOverlay *v, NSRect frame, NSString *text, NSString *symbol, CGFloat size, NSColor *ink,
                      NSColor *fill, NSColor *stroke, CGFloat radius, CGFloat line, NSInteger action, NSInteger index, BOOL focus) {
    NSButton *b = [NSButton buttonWithTitle:text target:v action:@selector(activate:)];
    b.frame = frame; b.bordered = NO; b.tag = action * 64 + index + 8; b.wantsLayer = YES;
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
    [v addSubview:b];
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
        if (q.tab >= OV_PROFILE) {
            L(x,y-56,800,51,labels[q.tab],38,NSFontWeightRegular,ink);
            NSTextField *detail = [NSTextField wrappingLabelWithString:d[@"social"][@(q.tab)] ?: @""];
            detail.frame = R(x,y,l.w-x-112,450); detail.font = [NSFont systemFontOfSize:23*k]; detail.textColor = ink;
            detail.maximumNumberOfLines = 14; [v addSubview:detail];
        } else if (q.tab == OV_SETTINGS) {
            L(x,y-56,500,51,T(@"Game settings"),38,NSFontWeightRegular,ink);
            for (int i = 0; i < count; i++)
                ov_button(v,R(x,y+i*64,318,54),i==HQ_POWER ? quit : items[i],nil,21*k,q.selection==i ? on : ink,
                          q.selection==i ? focus : surface,border,27*k,k,OV_MAIN,i,q.selection==i);
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
        NSArray *rows = q.card == HQ_HUD ? @[T(@"Position"),T(@"Size"),T(@"Opacity")] :
            q.card == HQ_VOLUME ? @[T(@"Game volume")] : q.card == HQ_PADS ?
            (d[@"controllerNames"] ?: @[]) : @[d[@"ldn"] ?: T(@"LDN disabled"),d[@"network"] ?: T(@"VPN not configured")];
        if (!rows.count) rows = @[T(@"No controllers connected")];
        CGFloat w = 520, h = q.card == HQ_HUD ? 292 : 68+56*rows.count;
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
            ov_box(v,R(x+36,y+44,w-72,5),soft,nil,2.5*k,0);
            if (fraction > 0) ov_box(v,R(x+36,y+44,(w-72)*fraction,5),focus,nil,2.5*k,0);
        }
        for (NSUInteger i=0; i<rows.count; i++) {
            CGFloat ry = y+62+(first+i)*56;
            if (q.card == HQ_HUD || q.card == HQ_VOLUME) {
                NSInteger row = i+first; BOOL selected = row == q.row;
                NSArray *values = q.card == HQ_HUD ? @[d[@"position"] ?: @"",d[@"size"] ?: @"",d[@"opacity"] ?: @""] : @[d[@"volume"] ?: @""];
                if (selected) ov_box(v,R(x+10,ry,w-20,52),soft,focus,12*k,2*k);
                L(x+36,ry+15,235,24,rows[i],18,NSFontWeightRegular,ink);
                C(x+303,ry+15,174,24,values[i],17,NSFontWeightSemibold,ink);
                ov_button(v,R(x+274,ry+9,45,34),@"◂",nil,18*k,muted,nil,nil,0,0,OV_ROW,-row-1,NO);
                ((NSButton *)v.subviews.lastObject).accessibilityLabel = [NSString stringWithFormat:@"%@ — %@",T(@"Decrease"),rows[i]];
                ov_button(v,R(x+461,ry+9,45,34),@"▸",nil,18*k,muted,nil,nil,0,0,OV_ROW,row,NO);
                ((NSButton *)v.subviews.lastObject).accessibilityLabel = [NSString stringWithFormat:@"%@ — %@",T(@"Increase"),rows[i]];
            } else L(x+36,ry+9,w-72,29,rows[i],18,NSFontWeightRegular,ink);
        }
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
    if (d[@"homeHelp"] && !q.confirm)
        C(190,quick ? l.h-222 : l.h-135,l.w-380,26,d[@"homeHelp"],16,NSFontWeightRegular,muted);
    NSString *back = !quick && q.card < 0 && !q.tab && !q.confirm ? resume : T(@"Back");
    NSMutableArray *hints = [NSMutableArray arrayWithArray:@[@[@"B",back,@(OV_BACK)],@[@"A",T(@"Choose"),@(-1)]]];
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
