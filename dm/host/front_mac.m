// Mac front end: with DM_WINDOW=1 open a window (CAMetalLayer, for the graphics backend to present frames) + keyboard and controllers → dm_input; the guest runs on a large-stack thread instead and the main thread belongs to AppKit.
// Without DM_WINDOW: run the guest on the current thread with the default application task role (front_role.h).
// The window is fullscreen-capable (the green button and ⌃⌘F); DM_FULLSCREEN=1 starts it that way. ⌘Q quits; Home opens the session overlay.
// Cheats (hle_cheats.c): the Cheats menu's rows toggle, reload (⌘R) and open the cheats folder; its first item "Show Cheats
// Window" (⌘⇧C, or DM_CHEATS_WINDOW=1 at launch) opens a Cheats panel beside the game: sections, search, the master switch,
// safe mode, values, details and the import of cheat files (see the code below).
// Key map (Nintendo layout): WASD left stick, arrow keys D-pad (with Shift held: the right stick, for the camera), J=A K=B U=X I=Y, Q=L E=R, Z=ZL C=ZR, F=press left stick G=press right stick, Return=+ Tab=−, Space=shake the controller.
// Controllers: face buttons as on the iPhone, by position (right A, bottom B, top X, left Y) or on a Nintendo pad by its labels (pad_apple.h), shoulders L R, triggers ZL ZR, Menu + Options −, both sticks and their presses.
// Each controller is a player of its own (local co-op): the first one connected is player 1, together with the keyboard, the next player 2, and so on up to 8 (pad_slots.h);
// DM_PAD_MERGE=1 merges every controller into player 1 instead, DM_KBD_PLAYER=own makes the keyboard player 1 on its own, with the controllers from player 2 on.
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <GameController/GameController.h>
#include "dm.h"
#include "front_role.h"
#include "dm_input.h"
#include "front.h"
#include "hle.h"
#include "pad_slots.h"
#include "haptics_apple.h"
#include "motion_apple.h"
#include "motion_pro_mac.h"
#include "pad_jc1_mac.h"
#include "pad_apple.h"
#include "pad_hid_mac.h"
#include "pad_switch2_apple.h"
static int s2pad_player(s2_pad *d);   // the Switch 2 pads' player slots (below, beside the raw HID pads')
static void s2pad_read(s2_pad *d);
static void (*g_merge_sink)(const dm_haptic_state *);   // DM_PAD_MERGE: where player 1's rumble goes, the pads last used (merge_rumble_to): NULL for GameController's
static void merge_rumble_to(void (*sink)(const dm_haptic_state *));
#include "game_overlay_mac.h"
#include "net_socket.h"
#include "nextendo_account.h"
#include "ctrl_prompt.h"
#include "user_select_mac.h"
#include <signal.h>
#include <math.h>
#include <net/if.h>
#include <stdatomic.h>
#include <sys/stat.h>

static CAMetalLayer *g_layer;
static uint64_t g_btn;
static int g_w, g_a, g_s, g_d;
static int g_rl, g_ru, g_rr, g_rd;   // arrow keys pressed with Shift held: the right stick (each goes back up as it went down, whatever Shift does meanwhile)
static int g_input_on = 1;   // main thread: the game window is key, so its keyboard, mouse and controllers reach the game (input_release / input_resume)

void *front_metal_layer(void) { return (__bridge void *)g_layer; }
static _Atomic int g_screen_fps;   // the window's screen's maximumFramesPerSecond, kept up to date when the window moves to another screen
int front_screen_max_fps(void) { return g_screen_fps; }
static _Atomic CGDirectDisplayID g_screen_id;   // the window's screen (screen_refresh); 0 until the window is up, then the main display stands in
int front_display_pixels(int *w, int *h) {
    CGDirectDisplayID id = g_screen_id; CGDisplayModeRef m = CGDisplayCopyDisplayMode(id ? id : CGMainDisplayID()); if (!m) return 0;
    int a = (int)CGDisplayModeGetPixelWidth(m), b = (int)CGDisplayModeGetPixelHeight(m); CGDisplayModeRelease(m);
    if (a <= 0 || b <= 0) return 0;
    *w = a; *h = b; return 1;
}
static _Atomic int g_screen_variable_refresh;
int front_screen_variable_refresh(void) { return g_screen_variable_refresh; }
static void screen_refresh(NSScreen *screen) {   // main thread: refresh capabilities of the current screen and mode, including a mode change without moving the window
    if (!screen) return;
    g_screen_fps = (int)screen.maximumFramesPerSecond;
    g_screen_id = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    g_screen_variable_refresh = screen.minimumRefreshInterval > 0 && screen.maximumRefreshInterval > screen.minimumRefreshInterval;
}
static _Atomic int g_fullscreen;   // the window is in fullscreen (set when it has entered and when it has left)
// The software keyboard input box is up (front_text_input). The game window is not key then, which is not a focus change the game should see: on hardware the inline keyboard is drawn inside
// the game, which keeps its focus, and ShowKeyboard's applet sends its own out-of-focus / in-focus pair (DM_APPLET). Monster Hunter Rise dropped the hunter's name after the round trip and asked again. Main thread only
static int g_text_box;
int front_fullscreen(void) { return g_fullscreen; }   // nvn_mtl.m link_latency: frame latency 2 in variable-refresh fullscreen
// The screen's refresh rate matched to the game's frame rate in fullscreen (front_screen_match, from PR #79; DM_SCREEN_MATCH=0 turns it off). 60 fps on a 144 Hz screen cannot be paced
// evenly: the display link counts a tick on the refresh nearest each 1/60 s slot (nvn_mtl.m link_range), so frames stay up 2 and 3 refreshes in turn (13.9 / 20.8 ms) and Apple's HUD shows
// the frame interval jumping between them. In fullscreen, a screen whose rate is not a multiple of the game's switches to the mode of the same size with the highest rate that is (144 → 120 Hz
// for 60 and 30 fps), for this app only: macOS switches it back when the host quits, crashes included, and leaving fullscreen or that screen switches it back at once. A window keeps the
// screen's rate, because the switch changes the whole screen for every app and most external screens go black for a second or more. A screen with no such mode keeps the virtual ticks.
// A variable-refresh screen (ProMotion) in fullscreen switches to a fixed-rate mode of the same size at a multiple of the game's rate (120 → 60 Hz for 60 and 30 fps), though its own
// rate is a multiple: there the display link at 60 Hz missed its targets (every present a 120 Hz refresh late and every other tick skipped, 40 fps on an M5 Pro at frame latency 2;
// 1 → 2 → 3 vsync steps at latency 1, issue #347), and the fixed 60 Hz mode held 60.0 fps at latency 1 (docs/reference/frame-rate.md). A screen with no such mode keeps its rate, and
// the 120 Hz link paces it (nvn_mtl.m link_vrr_120)
static NSWindow *g_win; static _Atomic int g_match_want;   // the game's window; the frame rate to match (0 = not known yet), written by the present thread only
static CGDirectDisplayID g_match_id; static CGDisplayModeRef g_match_orig; static int g_match_orig_vrr;   // main thread: the screen this host switched, its own mode (NULL = none switched) and whether that mode is variable-refresh
static double mode_hz(CGDisplayModeRef m) { double hz = CGDisplayModeGetRefreshRate(m); return hz > 0 ? hz : 0; }   // 0 = not known (older built-in screens report none)
static int hz_multiple(double hz, int fps) { double k = round(hz / fps); return k >= 1 && fabs(hz / fps - k) < 0.01; }   // 59.94 Hz counts as 60
static CGError screen_set_mode(CGDirectDisplayID id, CGDisplayModeRef m) {   // for this app only (kCGConfigureForAppOnly)
    CGDisplayConfigRef cfg; CGError r = CGBeginDisplayConfiguration(&cfg);
    if (r != kCGErrorSuccess) return r;
    r = CGConfigureDisplayWithDisplayMode(cfg, id, m, NULL);
    if (r != kCGErrorSuccess) { CGCancelDisplayConfiguration(cfg); return r; }
    return CGCompleteDisplayConfiguration(cfg, kCGConfigureForAppOnly);
}
static void screen_match_restore(int on_it) {   // main thread: the screen this host switched gets its own mode again; on_it: the window is on that screen
    double hz = mode_hz(g_match_orig); CGError r = screen_set_mode(g_match_id, g_match_orig);
    LOG("front end: screen %s %.0f Hz", r == kCGErrorSuccess ? "back at" : "could not be switched back to", hz);
    if (r == kCGErrorSuccess && on_it) { if (hz > 0) g_screen_fps = (int)round(hz); g_screen_variable_refresh = g_match_orig_vrr; }   // the screen observer may not show the mode yet
    CGDisplayModeRelease(g_match_orig); g_match_orig = NULL;
}
static void screen_match_apply(void) {   // main thread: on a new frame rate, on entering and leaving fullscreen and on a move to another screen
    static int off = -1; if (off < 0) { const char *e = getenv("DM_SCREEN_MATCH"); off = e && !strcmp(e, "0"); if (off) LOG("front end: the screen keeps its refresh rate in fullscreen too (DM_SCREEN_MATCH=0)"); }
    NSScreen *scr = g_win.screen; int want = g_match_want, full = (g_win.styleMask & NSWindowStyleMaskFullScreen) != 0;
    CGDirectDisplayID id = scr ? [scr.deviceDescription[@"NSScreenNumber"] unsignedIntValue] : kCGNullDirectDisplay;
    if (g_match_orig && (!full || id != g_match_id)) screen_match_restore(id == g_match_id);
    if (off || !full || want <= 0 || !scr) return;
    CGDisplayModeRef cur = CGDisplayCopyDisplayMode(id);
    if (!cur) return;
    double hz = mode_hz(cur);
    // the current mode is variable-refresh: the screen's own mode as screen_refresh saw it; one this host switched to as it chose it (the screen observer may lag), so a
    // fixed mode is never left for the variable one at a rate it already matches
    int vrr = !g_match_orig ? g_screen_variable_refresh : CGDisplayModeGetIODisplayModeID(cur) == CGDisplayModeGetIODisplayModeID(g_match_orig) ? g_match_orig_vrr : 0;
    if (!vrr && (hz <= 0 || hz_multiple(hz, want))) {   // already a multiple, or not known
        if (g_match_orig && hz > 0) g_screen_fps = (int)round(hz);   // the screen this host switched: its rate from the mode, which maximumFramesPerSecond (the screen observer) may not show yet
        CGDisplayModeRelease(cur); return;
    }
    size_t w = CGDisplayModeGetWidth(cur), h = CGDisplayModeGetHeight(cur), pw = CGDisplayModeGetPixelWidth(cur), ph = CGDisplayModeGetPixelHeight(cur);
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(id, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES});
    CGDisplayModeRef pick = NULL; double pick_hz = 0;
    for (CFIndex i = 0; modes && i < CFArrayGetCount(modes); i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i); double r = mode_hz(m);
        if (CGDisplayModeGetWidth(m) != w || CGDisplayModeGetHeight(m) != h || CGDisplayModeGetPixelWidth(m) != pw || CGDisplayModeGetPixelHeight(m) != ph || !CGDisplayModeIsUsableForDesktopGUI(m)) continue;
        // on a variable-refresh screen only a fixed-rate mode: not the current one, nor one at its rate (the variable mode at the screen's top rate)
        if (vrr && (CGDisplayModeGetIODisplayModeID(m) == CGDisplayModeGetIODisplayModeID(cur) || (hz > 0 && fabs(r - hz) < 0.5))) continue;
        if (hz_multiple(r, want) && r > pick_hz) { pick = m; pick_hz = r; }
    }
    if (!pick && vrr && (hz <= 0 || hz_multiple(hz, want))) LOG("front end: variable-refresh screen at %.0f Hz has no fixed-rate mode of this size at a multiple of %d Hz: it keeps its rate", hz, want);
    else if (!pick) LOG("front end: screen at %.0f Hz has no mode of this size at a multiple of %d Hz: frames are paced on the nearest refreshes", hz, want);
    else {
        CGError r = screen_set_mode(id, pick);
        LOG("front end: %sscreen at %.0f Hz %s %s%.0f Hz for %d fps in fullscreen (DM_SCREEN_MATCH=0 keeps it)", vrr ? "variable-refresh " : "", hz, r == kCGErrorSuccess ? "switched to" : "could not be switched to", vrr ? "fixed " : "", pick_hz, want);
        if (r == kCGErrorSuccess) {
            if (!g_match_orig) { g_match_orig = CGDisplayModeRetain(cur); g_match_id = id; g_match_orig_vrr = vrr; }
            g_screen_fps = (int)round(pick_hz);   // the screen observer may not show the new mode yet: its rate, and whether it is variable (back to the screen's own mode: as that was)
            g_screen_variable_refresh = CGDisplayModeGetIODisplayModeID(pick) == CGDisplayModeGetIODisplayModeID(g_match_orig) ? g_match_orig_vrr : vrr ? 0 : g_screen_variable_refresh;
        }
    }
    if (modes) CFRelease(modes);
    CGDisplayModeRelease(cur);
}
void front_screen_match(int fps) {
    if (!g_layer || g_match_want == fps) return;   // no window (a windowless run's main thread runs the guest), or the rate as before
    g_match_want = fps; dispatch_async(dispatch_get_main_queue(), ^{ screen_match_apply(); });
}
// The pointer hides on game input while it is over the picture of the active game window (issue #675): AppKit shows it again when the mouse moves, input_release when
// the window loses focus. The title bar, other windows and other apps keep theirs; the mouse is the touch screen (DmGameView), and moving it shows the pointer
static void cursor_hide_for_input(void) {
    if (!g_win.isKeyWindow || !NSApp.isActive) return;
    NSView *v = g_win.contentView;
    if (NSPointInRect([v convertPoint:g_win.mouseLocationOutsideOfEventStream fromView:nil], v.bounds)) [NSCursor setHiddenUntilMouseMoves:YES];
}
static void push(void) {
    int32_t lx = (g_d - g_a) * 32767, ly = (g_w - g_s) * 32767;
    int32_t rx = (g_rr - g_rl) * 32767, ry = (g_ru - g_rd) * 32767;
    dm_input_set(g_btn, lx, ly, rx, ry);
}
static int key_bit(unsigned short code) {
    switch (code) {
        case 38: return 0;  case 40: return 1;  case 32: return 2;  case 34: return 3;    // J K U I → A B X Y
        case 3: return 4;   case 5: return 5;                                            // F G → press stick
        case 12: return 6;  case 14: return 7;  case 6: return 8;   case 8: return 9;    // Q E Z C → L R ZL ZR
        case 36: return 10; case 48: return 11;                                          // Return Tab → + −
        case 123: return 12; case 126: return 13; case 124: return 14; case 125: return 15; // ← ↑ → ↓
    }
    return -1;
}
// fn held with a letter: the arrow and function keys carry the same modifier flag, so the key must be a letter for this to be a Globe shortcut
static int fn_shortcut(NSEvent *e) {
    NSString *s = e.charactersIgnoringModifiers;
    return (e.modifierFlags & NSEventModifierFlagFunction) && s.length == 1 && [[NSCharacterSet letterCharacterSet] characterIsMember:[s characterAtIndex:0]];
}
static ctrl_prompt g_cp; static int g_cp_confirm, g_cp_cancel;   // the controller applet's prompt (front_ctrl_support) and a key pressed in it since its last step
static int cp_poll(void);
static int hq_menu_key(unsigned short code, int down);
static NSMutableIndexSet *g_ov_keys_down;
static _Atomic int g_ov_display_motion_blocked;
static void on_key(NSEvent *e, int down) {
    if (!g_input_on) return;
    unsigned short c = e.keyCode;
    if (!down) [g_ov_keys_down removeIndex:c];
    if (cp_blocks_input(g_cp.phase)) {   // the prompt has the keyboard: Return or J (A) is done, Escape or K (B) closes it, no key reaches the game
        if (down && g_cp.phase == CP_OPEN) { if (c == 53 || c == 40) g_cp_cancel = 1; else if (c == 36 || c == 38) g_cp_confirm = 1; cp_poll(); }
        return;
    }
    if (hq_menu_key(c, down)) return;
    switch (c) { case 13: g_w = down; break; case 0: g_a = down; break; case 1: g_s = down; break; case 2: g_d = down; break; }
    // An arrow key pressed with Shift held is the right stick until it is released; without Shift, the D-pad. The keyboard had no right stick: a 3D game's camera
    // could be turned only with a controller (Donkey Kong Bananza)
    int *rs = c == 123 ? &g_rl : c == 126 ? &g_ru : c == 124 ? &g_rr : c == 125 ? &g_rd : NULL;
    if (rs && (down ? (e.modifierFlags & NSEventModifierFlagShift) != 0 : *rs)) { *rs = down; push(); return; }
    int b = key_bit(c);
    uint64_t m = b >= 0 ? 1ull << b : c == 49 ? DM_BTN_SHAKE : 0;   // Space: shaken while held
    g_btn = down ? (g_btn | m) : (g_btn & ~m);
    if (down && (m || c == 13 || c == 0 || c == 1 || c == 2)) cursor_hide_for_input();   // a key the game takes (WASD: the left stick)
    push();
}

// Physical controllers (GameController) go to dm_pad_set_player, mapped as the iPhone's (DmGamepad.m read_pad, same layout); player 1's is ORed with the keyboard, a stick takes
// whichever is deflected more (hle_hid.c). DM_KEYS uses player 1's path, so player 1's controller touched during a script takes it over.
// Players: every controller with an extended gamepad profile holds a slot (pad_slots.h: player 1 first, a reconnected controller gets its player back), and hle_hid.c reports
// player n on its own npad while the slot is held (dm_pad_players). A one-player game that supports only No1 / Handheld still sees every controller as player 1 (hle_hid.c).
// With DM_PAD_MERGE=1 every controller is player 1, as before (the last one moved wins; when the last one goes away its buttons and sticks are released)
static pad_slots g_slots;
static GCController *g_held[DM_PLAYERS];   // the controller of each slot, kept alive while it holds it (the slot table keys on its pointer)
static int g_merge, g_kbd_own;
static home_quit g_hq;
static int g_hq_arcane, g_hq_pulse = -1, g_ov_menu_player = -1;
static int32_t pad_axis(float v) { return (int32_t)(fmaxf(-1.f, fminf(1.f, v)) * DM_STICK_MAX); }
// A controller's state for player p, GameController or raw HID: a pressed button or a stick past 15% hides the pointer (cursor_hide_for_input), a resting stick's drift does not
static void pad_set(int p, uint64_t m, int32_t lx, int32_t ly, int32_t rx, int32_t ry) {
    if (hq_captures_menu(&g_hq)) {
        if (g_hq.phase == HQ_HOLDING && g_hq.trigger == HQ_PLUS && g_ov_menu_player < 0 && (m & DM_BTN_PLUS))
            g_ov_menu_player = p;   // Menu itself can be the player's first press to join
        m &= ~DM_BTN_PLUS;
        if (p == g_hq_pulse) m |= DM_BTN_PLUS;
    }
    const int32_t dead = DM_STICK_MAX * 15 / 100;
    if (m || abs(lx) > dead || abs(ly) > dead || abs(rx) > dead || abs(ry) > dead) cursor_hide_for_input();
    dm_pad_set_player(p, m, lx, ly, rx, ry);
}
static void hq_poll(void);
static void hq_close(void);
static void hq_home_preference(GCController *c);
static int g_press_to_join;   // DM_PAD_PRESS_TO_JOIN=1, below pad_read
static int pad_join(const void *owner, const char *name);
static const char *pad_name(GCController *c);
static void pads_motion_changed(GCController *gone);
// GameController's controllers that the host reads from their HID reports instead, so they stay unread here: identical pads (pad_hid_mac.h) and original Joy-Cons (pad_jc1_mac.h)
static int pad_gc_unread(GCController *c) { return hidpad_gc_unread(c) || jc1_gc_unread(c); }
static void pad_read(GCExtendedGamepad *g) {
    if (!g_input_on || (g_merge && jc1_gc_unread(g.controller))) return;
    hq_poll(); if (hq_blocks_input(g_hq.phase)) return;
    int p = g_merge ? 0 : pad_slot_of(&g_slots, (__bridge const void *)g.controller);
    if (p < 0 && (!g_press_to_join || pad_gc_unread(g.controller))) return;   // a controller read from its HID reports: GameController's controller of it stays unread
    uint64_t m = dm_pad_face(g);   // by position, a Nintendo pad by its labels
    #define K(btn, bit) if (btn.isPressed) m |= bit
    K(g.leftShoulder, DM_BTN_L); K(g.rightShoulder, DM_BTN_R);
    // Work around nonzero resting values (Xbox LT about 0.06 with isPressed true): digital Switch triggers actuate above 25% (PR #2504).
    if (g.leftTrigger.value > 0.25f) m |= DM_BTN_ZL;
    if (g.rightTrigger.value > 0.25f) m |= DM_BTN_ZR;
    K(g.buttonMenu, DM_BTN_PLUS); K(g.buttonOptions, DM_BTN_MINUS); K(g.leftThumbstickButton, DM_BTN_LS); K(g.rightThumbstickButton, DM_BTN_RS);   // nil on pads without them: not pressed
    K(g.dpad.left, DM_BTN_LEFT); K(g.dpad.up, DM_BTN_UP); K(g.dpad.right, DM_BTN_RIGHT); K(g.dpad.down, DM_BTN_DOWN);
    #undef K
    if (p < 0) {   // DM_PAD_PRESS_TO_JOIN=1: it joins at its first button
        GCController *c = g.controller; if (!m || (p = pad_join((__bridge const void *)c, pad_name(c))) < 0) return;
        g_held[p] = c; dm_motion_attach_gated(c,p,&g_ov_display_motion_blocked); pads_motion_changed(nil);
    }
    if (cp_poll()) return;   // the controller applet's prompt has the controllers (front_ctrl_support)
    if (m) merge_rumble_to(NULL);   // DM_PAD_MERGE: a button on this controller takes player 1's rumble back from a Switch 2 pad or Joy-Cons read from HID
    dm_haptics_apple_controller(p, g.controller);
    pad_set(p, m, pad_axis(g.leftThumbstick.xAxis.value), pad_axis(g.leftThumbstick.yAxis.value), pad_axis(g.rightThumbstick.xAxis.value), pad_axis(g.rightThumbstick.yAxis.value));
}
// Request Home for the game overlay without reserving the system's Capture gesture.
// macOS 27 respects the claim when the Home button setting for apps lets the app decide (hq_log_setting names it in the log)
static void pad_keep_system_buttons(GCController *c) {
    hq_home_preference(c);
    GCControllerButtonInput *home = c.extendedGamepad.buttonHome ?: c.physicalInputProfile.buttons[GCInputButtonHome];
    home.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL down) { (void)b; (void)v; (void)down; if (g_input_on) hq_poll(); };
}
static const char *pad_name(GCController *c) { return c.vendorName.UTF8String ?: "?"; }
static void npad_name(int p, char *out, size_t cap) { uint32_t id = dm_player_npad(p); if (id == 0x20) snprintf(out, cap, "handheld"); else snprintf(out, cap, "%u", id); }
// The players' raw HID motion source follows the controllers (gone: one just removed, still listed): a Pro Controller's or a DualShock 4's, each model counted on its own
// (motion_pro_mac.h)
static void pads_motion_changed(GCController *gone) {
    int count[PRO_MODELS] = {0}, player[PRO_MODELS];
    for (int m = 0; m < PRO_MODELS; m++) player[m] = -1;
    for (GCController *c in GCController.controllers) {
        int m = c != gone && c.extendedGamepad ? pro_model_of_category(c.productCategory.UTF8String) : -1;
        if (m >= 0) { count[m]++; player[m] = g_merge ? 0 : pad_slot_of(&g_slots, (__bridge const void *)c); }
    }
    dm_motion_pro_players(count, player);
}
static void pro_devices_changed(void) { pads_motion_changed(nil); }
// DM_PAD_PRESS_TO_JOIN=1: a controller is no player until one of its buttons is pressed, then it is the lowest player free, as a console's "press a button" screen.
// Whatever the port, the order of connection or the link (Bluetooth has no port), and for identical pads too: so the players pick their own order. Not with DM_PAD_MERGE
// A raw HID pad joins this way without the setting too (hidpad_first_press), and then takes its slot as a connecting controller does (pad_slot_take)
static int pad_join(const void *owner, const char *name) {
    int p = g_press_to_join ? pad_slot_take_lowest(&g_slots, owner, name) : pad_slot_take(&g_slots, owner, name); char nb[16];
    if (p < 0) { LOG("controller '%s': a button pressed, but all %d players are taken", name, DM_PLAYERS); return -1; }
    npad_name(p, nb, sizeof nb); LOG("controller '%s': a button pressed: player %d (npad %s)", name, p + 1, nb);
    dm_pad_players(pad_slot_mask(&g_slots));
    return p;
}
// DM_PAD_MERGE: whether a controller still plays player 1 (gone: one just removed, not counted), a GameController one or a raw HID pad (pad_hid_mac.h)
static int merge_pads_left(GCController *gone) {
    if (g_hidpads || g_jc1_pads || dm_switch2_pads()) return 1;
    for (GCController *c in GCController.controllers) if (c.extendedGamepad && c != gone) return 1;
    return 0;
}
// Called at start and on every connect / disconnect (gone: the controller that was just removed, nil on a connect)
static void pads_changed(GCController *gone) {
    if (gone && g_hq.phase == HQ_HOLDING) hq_close();   // disconnection is not a tap
    for (GCController *c in GCController.controllers)
        if (c != gone && !c.extendedGamepad && !jc1_gc_unread(c)) pad_keep_system_buttons(c);
    if (g_merge) {
        int any = 0;
        for (GCController *c in GCController.controllers) if (jc1_gc_unread(c)) pad_keep_system_buttons(c);   // read from HID (pad_jc1_mac.h), a lone Joy-Con's too (no extended gamepad profile)
        for (GCController *c in GCController.controllers) if (c.extendedGamepad && c != gone) {
            if (jc1_gc_unread(c)) { c.extendedGamepad.valueChangedHandler = nil; continue; }
            any = 1; pad_keep_system_buttons(c); c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)el; pad_read(g); };
            dm_motion_attach_gated(c,0,&g_ov_display_motion_blocked);   // every controller is player 1: the last one moved drives its six-axis sensor
            pad_read(c.extendedGamepad);
        }
        if (gone) dm_motion_detach(gone, 0);
        if (!any) { if (!g_hidpads && !g_jc1_pads && !dm_switch2_pads()) dm_pad_set(0, 0, 0, 0, 0); dm_haptics_apple_controller(0, nil); }   // a raw HID pad still plays player 1 (pad_hid_mac.h)
        pads_motion_changed(gone);
        return;
    }
    hidpad_twins_eval(gone); hidpad_twins_release();   // identical pads (pad_hid_mac.h): those GameController lists them all of again go back to it first
    NSArray<GCController *> *now = GCController.controllers; char nb[16];
    for (GCController *c in now) if (c != gone && jc1_gc_unread(c)) pad_keep_system_buttons(c);   // read from HID (pad_jc1_mac.h), a lone Joy-Con's too (no extended gamepad profile)
    for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p] && (g_held[p] == gone || ![now containsObject:g_held[p]] || pad_gc_unread(g_held[p]))) {
        npad_name(p, nb, sizeof nb); LOG("controller '%s' disconnected: player %d (npad %s) is free", pad_name(g_held[p]), p + 1, nb);
        g_held[p].extendedGamepad.valueChangedHandler = nil;
        dm_motion_detach(g_held[p], p);
        dm_haptics_apple_controller(p, nil);
        pad_slot_free(&g_slots, (__bridge const void *)g_held[p]); g_held[p] = nil;
        dm_pad_set_player(p, 0, 0, 0, 0, 0);   // nothing stays pressed
    }
    for (GCController *c in now) if (c.extendedGamepad && c != gone && pad_slot_of(&g_slots, (__bridge const void *)c) < 0) {
        if (pad_gc_unread(c)) { pad_keep_system_buttons(c); c.extendedGamepad.valueChangedHandler = nil; continue; }   // read from IOKit; Home and Capture stay out of macOS's hands
        if (g_press_to_join) {   // a player at its first button (pad_read)
            pad_keep_system_buttons(c);
            if (!c.extendedGamepad.valueChangedHandler) LOG("controller '%s' connected: press a button to play (DM_PAD_PRESS_TO_JOIN)", pad_name(c));
            c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)el; pad_read(g); };
            continue;
        }
        int p = pad_slot_take(&g_slots, (__bridge const void *)c, pad_name(c));
        if (p < 0) { LOG("controller '%s' connected: all %d players are taken, not used", pad_name(c), DM_PLAYERS); continue; }
        g_held[p] = c; pad_keep_system_buttons(c);
        c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)el; pad_read(g); };
        dm_motion_attach_gated(c,p,&g_ov_display_motion_blocked);
        npad_name(p, nb, sizeof nb); LOG("controller '%s' connected: player %d (npad %s)%s", pad_name(c), p + 1, nb, c.motion.hasRotationRate ? ", with motion (gyro)" : "");
        pad_read(c.extendedGamepad);
    }
    hidpad_twins_take(gone);   // the pads of a model GameController lists fewer of, a player each
    dm_pad_players(pad_slot_mask(&g_slots));
    pads_motion_changed(gone);
    cp_poll();   // a controller came or went while the controller applet's prompt is up
}
// Display sleep: macOS counts keyboard and mouse input as user activity, not a controller's, so in controller-only play the display dims and locks; the latency
// activity in front_run keeps the system awake, not the display. While the game window is key the display stays awake (NSActivityIdleDisplaySleepDisabled);
// losing focus or being minimized lets it sleep again. An explicit lock or sleep is not held off, and no input is synthesized
static id g_display_activity;
static void display_awake(int on) {
    if (on && !g_display_activity)
        g_display_activity = [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityIdleDisplaySleepDisabled reason:@"NxNative active game window"];
    else if (!on && g_display_activity) { [NSProcessInfo.processInfo endActivity:g_display_activity]; g_display_activity = nil; }
}
// Focus: a window that is no longer key sees no key-up, mouse-up or controller release, so whatever is held when it loses focus (another app, the text box, minimized) would
// stay pressed in the game. The front end releases only what it pressed itself: scripted buttons and sticks have their own path, and the touch is also DM_KEYS / DM_CTL's (hle_hid.c).
// Out of focus a controller's changes are ignored, so back in focus each controller is read as it is now (a button still held, a stick still deflected)
static int g_mouse_down;   // the mouse holds the touch (DmGameView)
// Nothing the controllers pressed stays pressed (focus lost, the Home quit prompt open)
static void pads_release(void) {
    if (g_merge) { if (merge_pads_left(nil)) dm_pad_set(0, 0, 0, 0, 0); return; }
    for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p]) dm_pad_set_player(p, 0, 0, 0, 0, 0);
    for (hid_pad *d = g_hidpads; d; d = d->next) { int p = pad_slot_of(&g_slots, d); if (p >= 0) dm_pad_set_player(p, 0, 0, 0, 0, 0); }
    for (s2_pad *d = dm_switch2_pads(); d; d = d->next) { int p = s2pad_player(d); if (p >= 0) { dm_pad_set_player(p, 0, 0, 0, 0, 0); dm_joy_set(p, 0, 0, 0, 0); dm_joy_set(p, 1, 0, 0, 0); } }
    for (jc1_pad *d = g_jc1_pads; d; d = d->next) { int p = jc1pad_player(d); if (p >= 0) { dm_pad_set_player(p, 0, 0, 0, 0, 0); dm_joy_set(p, 0, 0, 0, 0); dm_joy_set(p, 1, 0, 0, 0); } }
}
static void hidpad_motion_clear(void) {   // the gyro of identical Pro Controllers read from IOKit (pad_hid_mac.h)
    for (hid_pad *d = g_hidpads; d; d = d->next) { int p = hidpad_full(d) ? pad_slot_of(&g_slots, d) : -1; if (p >= 0) dm_motion_clear_hid(p); }
}
// Each controller read as it is now (focus back, the Home quit prompt closed)
static void pads_reread(void) {
    if (g_merge) { for (GCController *c in GCController.controllers) if (c.extendedGamepad) pad_read(c.extendedGamepad); }
    else for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p].extendedGamepad) pad_read(g_held[p].extendedGamepad);
    for (hid_pad *d = g_hidpads; d; d = d->next) hidpad_read(d);
    for (s2_pad *d = dm_switch2_pads(); d; d = d->next) s2pad_read(d);
    for (jc1_pad *d = g_jc1_pads; d; d = d->next) jc1pad_read(d);
}
static void keys_touch_release(void) {
    g_btn = 0; g_w = g_a = g_s = g_d = 0; g_rl = g_ru = g_rr = g_rd = 0; push();
    if (g_mouse_down) { g_mouse_down = 0; dm_touch_set(NULL, 0); }
}
static void input_release(void) {
    g_input_on = 0;
    hq_close();   // the prompt or the hold indicator, if one is up: the Games app the system opens for Home takes the focus too
    [NSCursor setHiddenUntilMouseMoves:NO];
    display_awake(0);
    dm_motion_pro_active(0); hidpad_motion_clear();
    dm_switch2_active(0); dm_jc1_active(0);
    keys_touch_release();
    pads_release();
}
static void input_resume(void) {
    display_awake(1);
    g_input_on = 1;
    dm_motion_pro_active(!g_ov_display_motion_blocked);
    dm_switch2_active(1); dm_jc1_active(1);
    for (GCController *c in GCController.controllers) hq_home_preference(c);
    pads_reread();
    hq_poll();
}
// Raw HID gamepads (pad_hid_mac.h): a player slot each, as a GameController controller, named by the device's product name. Identical pads that GameController lists
// fewer of are read the same way, an identical Pro Controller from its report 0x30.
// A HID device that declares a GamePad or Joystick collection only claims to be a controller: a keyboard and mouse receiver can declare one and never send a report through it
// (a Keychron Link, 3434:d030, GitHub issue #1657), and nothing in its descriptor tells it from a pad at rest. So a raw HID pad is a player from its first button press, not
// from its connection, with or without DM_PAD_PRESS_TO_JOIN: a device that never presses takes no player from a real controller. An identical pad (twin) is a model
// GameController lists, so it is a player at its connection unless the setting is on
static int hidpad_first_press(const hid_pad *d) { return !g_merge && (g_press_to_join || !d->twin); }
static int hidpad_player(const hid_pad *d) { return g_merge ? 0 : pad_slot_of(&g_slots, d); }
// A pad of Nintendo's protocol (pad_hid_mac.h) shows its player on its lights, and its player's rumble goes to it once it answers
static void hidpad_show_player(hid_pad *d, int p, uint64_t m) {
    hidpad_lights(d, p);
    if (!hidpad_rumbles(d)) return;
    if (g_merge) { if (m) merge_rumble_to(dm_hidpad_rumble); return; }
    if (d->sink != p + 1) { d->sink = p + 1; dm_haptics_apple_set_sink(p, dm_hidpad_rumble); }   // its rumble goes over HID, not to a Core Haptics engine
}
static void hidpad_read(hid_pad *d) {
    hq_poll();
    if (!g_input_on || hq_blocks_input(g_hq.phase)) return;
    int p = hidpad_player(d), full = hidpad_full(d);
    uint64_t m = full ? d->pro_m : pad_hid_buttons(&d->st);
    if (p < 0 && (!hidpad_first_press(d) || !m || (p = pad_join(d, d->name)) < 0)) return;   // joins at its first button
    hidpad_show_player(d, p, m);
    if (cp_poll()) return;   // the controller applet's prompt has the controllers
    if (full) { pad_set(p, m, d->pro_s[0], d->pro_s[1], d->pro_s[2], d->pro_s[3]); return; }
    int32_t s[4]; pad_hid_sticks(&d->st, s);
    pad_set(p, m, s[0], s[1], s[2], s[3]);
}
static void hidpad_attach(hid_pad *d) {
    if (hidpad_first_press(d)) { LOG("controller '%s' (HID) connected: press a button to play%s", d->name, g_press_to_join ? " (DM_PAD_PRESS_TO_JOIN)" : ""); hidpad_read(d); return; }
    int p = g_merge ? 0 : pad_slot_take(&g_slots, d, d->name); char nb[16];
    if (p < 0) { LOG("controller '%s' (HID) connected: all %d players are taken, not used", d->name, DM_PLAYERS); return; }
    npad_name(p, nb, sizeof nb); LOG("controller '%s' (HID) connected: player %d (npad %s)", d->name, p + 1, nb);
    if (!g_merge) dm_pad_players(pad_slot_mask(&g_slots));   // merged, every controller is player 1, as pads_changed has it
    hidpad_read(d);
}
static void hidpad_motion(hid_pad *d, const float acc[3], const float rot[3], uint64_t ns) {
    int p = g_input_on && !g_merge && !g_ov_display_motion_blocked ? pad_slot_of(&g_slots, d) : -1; if (p < 0) return;
    dm_motion_set_hid(p, acc, rot, ns);
}
static void hidpad_models_changed(void) { pads_changed(nil); }
static void hidpad_quit_changed(int interrupted) {
    if (interrupted && g_hq.phase == HQ_HOLDING) hq_close();   // report mode switched or pad disconnected, not a tap
    if (g_input_on) hq_poll();
}
static void hidpad_detach(hid_pad *d) {   // d is already off g_hidpads
    uint32_t q = hidpad_quit_buttons(d);
    if (g_hq.phase == HQ_HOLDING) hq_close();
    if (q) hidpad_quit_changed(0);
    if (g_merge) {   // as pads_changed: released when the last controller goes away
        LOG("controller '%s' (HID) disconnected", d->name);
        int rumbles = 0; for (hid_pad *o = g_hidpads; o; o = o->next) rumbles |= hidpad_rumbles(o);
        if (!rumbles && g_merge_sink == dm_hidpad_rumble) merge_rumble_to(NULL);
        if (!merge_pads_left(nil)) dm_pad_set(0, 0, 0, 0, 0);
        return;
    }
    int p = pad_slot_free(&g_slots, d); char nb[16]; if (p < 0) return;
    if (hidpad_full(d)) dm_motion_clear_hid(p);
    if (d->sink) { d->sink = 0; dm_haptics_apple_set_sink(p, NULL); }
    npad_name(p, nb, sizeof nb); LOG("controller '%s' (HID) disconnected: player %d (npad %s) is free", d->name, p + 1, nb);
    dm_pad_set_player(p, 0, 0, 0, 0, 0);   // nothing stays pressed
    dm_pad_players(pad_slot_mask(&g_slots));
    cp_poll();   // one controller fewer to wait for, or one player fewer
}
// Switch 2 controllers over Bluetooth LE (pad_switch2_apple.h): a pad is a player's controller, as a GameController one or a raw HID pad
static int s2pad_player(s2_pad *d) { return g_merge ? 0 : pad_slot_of(&g_slots, d); }
// DM_PAD_MERGE: player 1's rumble follows the controller last used, as pad_read hands it to a GameController one
static void merge_rumble_to(void (*sink)(const dm_haptic_state *)) {
    if (!g_merge || g_merge_sink == sink) return;
    g_merge_sink = sink; dm_haptics_apple_set_sink(0, sink);
}
static int s2pad_blocked(void) { return !g_input_on || hq_blocks_input(g_hq.phase) || cp_blocks_input(g_cp.phase); }   // no input to the game (focus lost, the Home or controller prompt up): its Joy-Con states are not sent (pad_switch2_apple.m)
static void s2pad_read(s2_pad *d) {
    hq_poll();   // Home and the prompt's A and B come from these pads too
    if (!g_input_on || hq_blocks_input(g_hq.phase)) return;
    int p = s2pad_player(d);
    uint64_t m; int32_t s[4]; if (!s2_pad_input(&d->st, &m, s)) return;
    if (p < 0) {   // DM_PAD_PRESS_TO_JOIN=1: joins at its first button
        if (!g_press_to_join || !m || (p = pad_join(d, d->name)) < 0) return;
        dm_haptics_apple_set_sink(p, dm_switch2_rumble);   // its rumble goes over Bluetooth, not to a Core Haptics engine
    }
    if (cp_poll()) return;   // the controller applet's prompt has the controllers
    if (m) merge_rumble_to(dm_switch2_rumble);
    pad_set(p, m, s[0], s[1], s[2], s[3]);
}
static int s2pad_attach(s2_pad *d) {   // 1: kept (a player, or waiting for its first button press); 0: no free player (pad_switch2_apple.h)
    if (g_press_to_join && !g_merge) { LOG("controller '%s' (Bluetooth) connected: press a button to play (DM_PAD_PRESS_TO_JOIN)", d->name); cp_poll(); return 1; }
    int p = g_merge ? 0 : pad_slot_take(&g_slots, d, d->name); char nb[16];
    if (p < 0) { LOG("controller '%s' (Bluetooth) connected: all %d players are taken, not used", d->name, DM_PLAYERS); return 0; }
    npad_name(p, nb, sizeof nb); LOG("controller '%s' (Bluetooth) connected: player %d (npad %s)", d->name, p + 1, nb);
    if (!g_merge) { dm_pad_players(pad_slot_mask(&g_slots)); dm_haptics_apple_set_sink(p, dm_switch2_rumble); }   // its rumble goes over Bluetooth, not to a Core Haptics engine
    cp_poll();   // one controller fewer to wait for
    return 1;
}
static void s2pad_detach(s2_pad *d) {   // d is already off g_s2pads
    if (g_hq.phase == HQ_HOLDING) hq_close();
    if (g_merge) {
        LOG("controller '%s' (Bluetooth) disconnected", d->name);
        if (!dm_switch2_pads() && g_merge_sink == dm_switch2_rumble) merge_rumble_to(NULL);
        if (!merge_pads_left(nil)) dm_pad_set(0, 0, 0, 0, 0);
        return;
    }
    int p = pad_slot_free(&g_slots, d); char nb[16]; if (p < 0) { cp_poll(); return; }   // one that had not joined: one fewer waiting
    dm_haptics_apple_set_sink(p, NULL);
    npad_name(p, nb, sizeof nb); LOG("controller '%s' (Bluetooth) disconnected: player %d (npad %s) is free", d->name, p + 1, nb);
    dm_pad_set_player(p, 0, 0, 0, 0, 0);
    dm_pad_players(pad_slot_mask(&g_slots));
    cp_poll();   // one player fewer
}
// Original Joy-Cons read from their HID reports (pad_jc1_mac.h): a pad is one Joy-Con or a left and a right one, a player from its first button press as a raw HID pad
// (hidpad_first_press: with or without DM_PAD_PRESS_TO_JOIN), whose rumble goes to the Joy-Cons themselves
static int jc1pad_player(jc1_pad *d) { return g_merge ? 0 : pad_slot_of(&g_slots, d); }
static int jc1pad_blocked(void) { return s2pad_blocked(); }
static void jc1pad_read(jc1_pad *d) {
    hq_poll();   // Home and the prompt's A and B come from these pads too
    if (!g_input_on || hq_blocks_input(g_hq.phase)) return;
    int p = jc1pad_player(d);
    uint64_t m; int32_t s[4]; if (!jc1_pad_state(d, &m, s)) return;
    if (p < 0) {   // joins at its first button
        if (!m || (p = pad_join(d, d->name)) < 0) return;
        dm_haptics_apple_set_sink(p, dm_jc1_rumble);
    }
    if (cp_poll()) return;   // the controller applet's prompt has the controllers
    if (m) merge_rumble_to(dm_jc1_rumble);
    pad_set(p, m, s[0], s[1], s[2], s[3]);
}
static void jc1pad_attach(jc1_pad *d) {
    if (g_merge) LOG("controller '%s' (HID) connected: player 1 (DM_PAD_MERGE)", d->name);
    else { LOG("controller '%s' (HID) connected: press a button to play", d->name); cp_poll(); }   // one more controller waiting to join
    jc1pad_read(d);
}
static void jc1pad_detach(jc1_pad *d) {   // d is already off g_jc1_pads
    if (g_hq.phase == HQ_HOLDING) hq_close();
    if (g_merge) {
        LOG("controller '%s' (HID) disconnected", d->name);
        if (!g_jc1_pads && g_merge_sink == dm_jc1_rumble) merge_rumble_to(NULL);
        if (!merge_pads_left(nil)) dm_pad_set(0, 0, 0, 0, 0);
        return;
    }
    int p = pad_slot_free(&g_slots, d); char nb[16]; if (p < 0) { cp_poll(); return; }   // one that had not joined: one fewer waiting
    dm_haptics_apple_set_sink(p, NULL);
    npad_name(p, nb, sizeof nb); LOG("controller '%s' (HID) disconnected: player %d (npad %s) is free", d->name, p + 1, nb);
    dm_pad_set_player(p, 0, 0, 0, 0, 0);
    dm_pad_players(pad_slot_mask(&g_slots));
    cp_poll();   // one player fewer
}
static void jc1_models_changed(void) { pads_changed(nil); }
static NSTimer *g_hq_timer;
static NSView *g_hq_hold, *g_hq_view;
static NSVisualEffectView *g_hq_blur;
static CAShapeLayer *g_hq_ring;
static BOOL g_ov_fr;
static BOOL g_ov_home_seen, g_ov_home_system, g_ov_help_once, g_ov_help_visible;
static double g_ov_started;
static NSString *g_ov_game, *g_ov_vpn;
static NSImage *g_ov_cover;
static NSDictionary *g_ov_theme;
static NSDictionary *g_ov_social;
static NSUserDefaults *g_hud_store;
static ov_hud g_hud;
static BOOL g_hud_live;   // Metal's HUD was enabled before the first device, so its properties change live
static NSString *g_hud_notice;
static NSArray *g_ov_shoulders;
static int g_bg_fs_transition;
static int g_ov_volume = 100;
static unsigned g_hq_pulse_serial;
static unsigned short g_ov_keys[2];
static char g_hq_text[HQ_TEXTS][256];
static void bg_enter(void);
static void hq_show(void);

// Metal's HUD reads MTL_HUD_ENABLED when the process makes its first device: a launch with the HUD off cannot turn it on live (the card says so)
static BOOL hud_forced(void) { return getenv("DM_METAL_HUD") && atoi(getenv("DM_METAL_HUD")); }
static void hud_apply(void) {
    if (g_hud_live) g_layer.developerHUDProperties = ov_hud_properties(g_hud);
}
static NSString *ov_env(const char *name) {
    const char *text = getenv(name);
    return text && strlen(text) < 4096 && *text ? [NSString stringWithUTF8String:text] : nil;
}
static NSDictionary *ov_load_data(NSString *path) {
    if (![path isAbsolutePath]) return nil;
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK);
    if (fd<0) return nil;
    struct stat st;
    NSMutableData *data=nil;
    if (!fstat(fd,&st) && S_ISREG(st.st_mode) && st.st_uid==getuid() && !(st.st_mode&022) && st.st_size>0 && st.st_size<=512*1024) {
        data=[NSMutableData dataWithLength:(NSUInteger)st.st_size];
        size_t pos=0;
        while (pos<data.length) {
            ssize_t n=read(fd,(char *)data.mutableBytes+pos,data.length-pos);
            if (n<0 && errno==EINTR) continue;
            if (n<=0) { data=nil; break; }
            pos+=(size_t)n;
        }
    }
    close(fd);
    return ov_social(data);
}
static void hq_start(void) {
    g_hq.disabled = !hq_enabled(getenv("DM_HOME_MENU"));
    g_hq.no_hold = !hq_enabled(getenv("DM_HOME_QUIT"));
    const char *menu_hold = getenv("DM_OVERLAY_MENU_HOLD");
    g_hq.menu_hold = menu_hold && !strcmp(menu_hold, "1");
    g_hq_arcane = hq_menu_enabled(getenv("DM_HOME_MENU_LAUNCHER"), getenv("DM_HOME_MENU"));
    g_ov_fr = [NSLocale.preferredLanguages.firstObject hasPrefix:@"fr"];
    g_ov_keys_down = [NSMutableIndexSet new];
    ov_keys(getenv("DM_OVERLAY_KEYS"), g_ov_keys);
    g_ov_theme = ov_theme(ov_env("DM_OVERLAY_THEME_V1"));
    g_ov_social = ov_load_data(ov_env("DM_OVERLAY_DATA"));
    g_ov_started = CACurrentMediaTime();
    g_ov_game = [@"game-" stringByAppendingString:@(DM_GAME_ID)];
    g_hud_store = [[NSUserDefaults alloc] initWithSuiteName:@"org.nxnative.overlay"];
    g_hud = ov_hud_load(g_hud_store, g_ov_game);
    g_hq.swap = ov_home_swap_load(g_hud_store,getenv("DM_OVERLAY_HOME_SWAP"));
    if (!hud_forced()) hud_apply();   // DM_METAL_HUD=1 keeps Apple's own look until the card is used
    NSString *cover = ov_env("DM_OVERLAY_COVER");
    if ([cover isAbsolutePath]) {
        NSDictionary *file = [NSFileManager.defaultManager attributesOfItemAtPath:cover error:NULL];
        if ([file[NSFileType] isEqual:NSFileTypeRegular] && [file[NSFileSize] unsignedLongLongValue] <= 16*1024*1024)
            g_ov_cover = [[NSImage alloc] initWithContentsOfFile:cover];
    }
    char title[256]; snprintf(title, sizeof title, "Quit %s?", DM_GAME_NAME);
    if (g_ov_fr) snprintf(title, sizeof title, "Quitter %s ?", DM_GAME_NAME);
    const char *def[HQ_TEXTS] = {ov_text(g_ov_fr,@"Keep holding for quick access").UTF8String, title,
        ov_text(g_ov_fr,@"Unsaved progress will be lost.").UTF8String, ov_text(g_ov_fr,@"Quit").UTF8String, ov_text(g_ov_fr,@"Cancel").UTF8String,
        ov_text(g_ov_fr,@"Resume").UTF8String, ov_text(g_ov_fr,@"Return to Arcane").UTF8String, DM_GAME_NAME};
    const char *text = getenv("DM_HOME_QUIT_TEXT");   // a front end's, in the player's language: one line per text, in home_quit.h's order
    for (int i = 0; i < HQ_TEXTS; i++) {
        hq_text_line(text, i, def[i], g_hq_text[i], sizeof g_hq_text[i]);
        // Older launchers' hold text names the removed two-second quit gesture.
        if (i == HQ_TEXT_HOLD) snprintf(g_hq_text[i], sizeof g_hq_text[i], "%s", def[i]);
        if (![[NSString alloc] initWithUTF8String:g_hq_text[i]]) snprintf(g_hq_text[i], sizeof g_hq_text[i], "%s", def[i]);
    }
    LOG("front end: game overlay %s, quick hold %s, launcher return %s", g_hq.disabled ? "off" : "on",
        g_hq.no_hold ? "off" : "on", g_hq_arcane ? "on" : "off");
}
// The Home button setting for apps (macOS 27), once, when the first controller is there (GameController reads it only while one is connected): "system" in the log
// explains a hold that does nothing, since the system keeps Home whatever the host asks. A front end reads the setting itself (GCControllerHomeButtonSettingsManager)
static void hq_home_preference(GCController *c) {
    GCControllerButtonInput *home = c.physicalInputProfile.buttons[GCInputButtonHome];
    if (g_hq.disabled || (!home && !c.extendedGamepad.buttonHome)) return;
#if defined(__MAC_27_0)
    if (@available(macOS 27.0, *)) {
        static long last = -2;
        GCControllerHomeButtonSettingCustomizationStatus by = GCControllerHomeButtonSettingCustomizationDefault; NSError *err = nil;
        GCControllerHomeButtonSettingsManager *settings = [GCControllerHomeButtonSettingsManager new];
        GCControllerHomeButtonSettingInAppAction v = [settings readControllerHomeButtonInAppAction:&by withError:&err];
        home.preferredSystemGestureState = v == GCControllerHomeButtonSettingInAppActionDefer ? GCSystemGestureStateDisabled : GCSystemGestureStateEnabled;
        g_ov_home_system = v == GCControllerHomeButtonSettingInAppActionDefault &&
            [settings readControllerHomeButtonSystemActionWithError:NULL] != GCControllerHomeButtonSettingSystemActionDisabled;
        if (last != (long)v)
            LOG("front end: Home button in apps: %s (%s)%s%s", hq_in_app_name((long)v), by == GCControllerHomeButtonSettingCustomizationUser ? "set by the player" : "the system's default",
                err ? ", " : "", err ? err.localizedDescription.UTF8String : "");
        last = (long)v;
        return;
    }
#endif
    home.preferredSystemGestureState = GCSystemGestureStateDisabled;
    c.extendedGamepad.buttonHome.preferredSystemGestureState = GCSystemGestureStateDisabled;
}
static unsigned hq_pad_bits(uint64_t m, const int32_t s[4]) {
    return (m & DM_BTN_Y ? HQ_Y : 0) | (m & DM_BTN_PLUS ? HQ_PLUS : 0) |
        (m & DM_BTN_L ? HQ_L : 0) | (m & DM_BTN_R ? HQ_R : 0) |
        (m & DM_BTN_ZL ? HQ_ZL : 0) | (m & DM_BTN_ZR ? HQ_ZR : 0) |
        (m & DM_BTN_LEFT ? HQ_LEFT : 0) | (m & DM_BTN_RIGHT ? HQ_RIGHT : 0) |
        (m & DM_BTN_UP ? HQ_UP : 0) | (m & DM_BTN_DOWN ? HQ_DOWN : 0) | hq_stick_bits(s) |
        (m & ~(DM_BTN_Y|DM_BTN_PLUS|DM_BTN_LEFT|DM_BTN_RIGHT|DM_BTN_UP|DM_BTN_DOWN|DM_BTN_L|DM_BTN_R) ? HQ_OTHER : 0);
}
static unsigned hq_buttons(int *menu_player) {
    unsigned bits = 0; *menu_player = -1;
    for (GCController *c in GCController.controllers) {
        GCExtendedGamepad *g = c.extendedGamepad;
        GCControllerButtonInput *home = g.buttonHome ?: c.physicalInputProfile.buttons[GCInputButtonHome];
        if (home.isPressed) bits |= HQ_HOME;
        if (!g || (g_merge ? jc1_gc_unread(c) : pad_gc_unread(c))) continue;
        if (g.buttonMenu.isPressed) { bits |= HQ_PLUS; *menu_player = g_merge ? 0 : pad_slot_of(&g_slots,(__bridge const void *)c); }
        int32_t s[4] = {pad_axis(g.leftThumbstick.xAxis.value), pad_axis(g.leftThumbstick.yAxis.value),
                        pad_axis(g.rightThumbstick.xAxis.value), pad_axis(g.rightThumbstick.yAxis.value)};
        unsigned padBits = (g.buttonA.isPressed ? HQ_A : 0) | (g.buttonB.isPressed ? HQ_B : 0) | (g.buttonY.isPressed ? HQ_Y : 0) |
            (g.leftShoulder.isPressed ? HQ_L : 0) | (g.rightShoulder.isPressed ? HQ_R : 0) |
            (g.leftTrigger.value>.25f ? HQ_ZL : 0) | (g.rightTrigger.value>.25f ? HQ_ZR : 0) |
            (g.dpad.left.isPressed ? HQ_LEFT : 0) | (g.dpad.right.isPressed ? HQ_RIGHT : 0) |
            (g.dpad.up.isPressed ? HQ_UP : 0) | (g.dpad.down.isPressed ? HQ_DOWN : 0) | hq_stick_bits(s) |
            (g.buttonX.isPressed || g.buttonOptions.isPressed ||
             g.leftThumbstickButton.isPressed || g.rightThumbstickButton.isPressed ? HQ_OTHER : 0);
        bits |= padBits;
        if (padBits || home.isPressed || g.buttonMenu.isPressed) {
            NSString *kind=[NSString stringWithFormat:@"%@ %@",c.productCategory,c.vendorName];
            g_ov_shoulders=([kind containsString:@"Dual"] || [kind containsString:@"PlayStation"]) ? @[@"L1",@"R1",@"L2",@"R2"] :
                ([kind containsString:@"Nintendo"] || [kind containsString:@"Switch"] || [kind containsString:@"Joy-Con"]) ? @[@"L",@"R",@"ZL",@"ZR"] :
                @[@"LB",@"RB",@"LT",@"RT"];
        }
    }
    for (s2_pad *d = dm_switch2_pads(); d; d = d->next) {
        int a=0,b=0; s2_pad_ab(&d->st,&a,&b);
        bits |= (a ? HQ_A : 0) | (b ? HQ_B : 0) | (s2_pad_home(&d->st) ? HQ_HOME : 0);
        uint64_t m; int32_t s[4];
        unsigned local=0;
        if (s2_pad_input(&d->st,&m,s)) { bits |= local=hq_pad_bits(m,s); if (m & DM_BTN_PLUS) *menu_player = s2pad_player(d); }
        if (local || a || b || s2_pad_home(&d->st)) g_ov_shoulders=@[@"L",@"R",@"ZL",@"ZR"];
        // A pair's Pro-style mapping drops the rail buttons that its native Joy-Con path still sends.
        if ((d->st.left.have && (d->st.left.r.buttons & (S2_SL_L|S2_SR_L))) ||
            (d->st.right.have && (d->st.right.r.buttons & (S2_SL_R|S2_SR_R)))) bits |= HQ_OTHER;
    }
    for (jc1_pad *d = g_jc1_pads; d; d = d->next) {
        int a=0,b=0; jc1_pad_ab(d,&a,&b);
        bits |= (a ? HQ_A : 0) | (b ? HQ_B : 0) | (jc1_pad_home(d) ? HQ_HOME : 0);
        uint64_t m; int32_t s[4];
        unsigned local=0;
        if (jc1_pad_state(d,&m,s)) { bits |= local=hq_pad_bits(m,s); if (m & DM_BTN_PLUS) *menu_player = jc1pad_player(d); }
        if (local || a || b || jc1_pad_home(d)) g_ov_shoulders=@[@"L",@"R",@"ZL",@"ZR"];
        for (int i = 0; i < 2; i++)
            if (d->side[i] && d->side[i]->have && (d->side[i]->buttons & (DM_BTN_LSL|DM_BTN_LSR|DM_BTN_RSL|DM_BTN_RSR))) bits |= HQ_OTHER;
    }
    for (hid_pad *d = g_hidpads; d; d = d->next) {
        uint32_t q = hidpad_quit_buttons(d);
        bits |= (q & HIDPAD_QUIT_HOME ? HQ_HOME : 0) | (q & HIDPAD_QUIT_A ? HQ_A : 0) | (q & HIDPAD_QUIT_B ? HQ_B : 0);
        int up=0,down=0, full=hidpad_full(d); int32_t s[4];
        pad_hid_sticks(&d->st,s);
        uint64_t m = full ? d->pro_m : pad_hid_buttons(&d->st);
        if (d->st.layout != PAD_HID_NINTENDO && !full) bits |= (m & DM_BTN_A ? HQ_A : 0) | (m & DM_BTN_B ? HQ_B : 0);
        hidpad_menu_dirs(d,&up,&down,DM_STICK_MAX*HQ_STICK);
        bits |= hq_pad_bits(m,full ? d->pro_s : s) | (up ? HQ_UP : 0) | (down ? HQ_DOWN : 0);
        if ((m || q) && (full || d->st.layout == PAD_HID_NINTENDO)) g_ov_shoulders=@[@"L",@"R",@"ZL",@"ZR"];
        if (m & DM_BTN_PLUS) *menu_player = hidpad_player(d);
    }
    return bits;
}
static void hq_fade(NSView *v, int in) {
    if (!v) return;
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) { if (!in) [v removeFromSuperview]; return; }
    if (in) v.alphaValue = 0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) { ctx.duration = 0.18; v.animator.alphaValue = in ? 1 : 0; }
                        completionHandler:^{ if (!in) [v removeFromSuperview]; }];
}
static void hq_tick(void) {
    hq_phase p = g_hq.phase;
    int want = g_input_on && (p == HQ_HOLDING || hq_visible(p) || p == HQ_SETTLE);
    if (want && !g_hq_timer) g_hq_timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *t) { (void)t; hq_poll(); }];
    if (!want && g_hq_timer) { [g_hq_timer invalidate]; g_hq_timer = nil; }
}
static void hq_hide_hold(void) { [g_hq_hold removeFromSuperview]; g_hq_hold = nil; g_hq_ring = nil; }
static int hq_count(void) {
    if (g_hq.tab == OV_PROFILE) return g_hq_arcane && ov_string(g_ov_social[@(OV_PROFILE)][@"name"]) != nil;
    if (g_hq.tab == OV_FRIENDS) return (int)[g_ov_social[@(OV_FRIENDS)][@"items"] count];
    if (g_hq.tab == OV_ACHIEVEMENTS) return 0;
    if (g_hq.tab == OV_SETTINGS) return HQ_HOME_SETTING+1;
    return g_hq.phase == HQ_QUICK ? HQ_POWER + !g_hq.no_hold : 1 + g_hq_arcane + !g_hq.no_hold;
}
static void hq_action(NSInteger action, NSInteger index);
static void hq_hide(void) {
    [g_hq_view removeFromSuperview]; g_hq_view = nil;
    [g_hq_blur removeFromSuperview]; g_hq_blur = nil;
}
static void hq_show(void) {
    if (!hq_visible(g_hq.phase)) return;
    NSView *cv = g_win.contentView;
    if (g_hq.phase == HQ_FULL && !g_hq_blur) {
        g_hq_blur = [[NSVisualEffectView alloc] initWithFrame:cv.bounds];
        g_hq_blur.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        g_hq_blur.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        g_hq_blur.material = NSVisualEffectMaterialHUDWindow;
        g_hq_blur.state = NSVisualEffectStateActive;
        g_hq_blur.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        [cv addSubview:g_hq_blur];
    } else if (g_hq.phase != HQ_FULL) {
        [g_hq_blur removeFromSuperview]; g_hq_blur = nil;
    }
    NSMutableArray *pads = [NSMutableArray array];
    void (^pad)(NSString *, int) = ^(NSString *name, int slot) {
        [pads addObject:@{@"name":name ?: @"Controller",@"player":@(slot+1)}];
    };
    for (GCController *c in GCController.controllers)
        if (c.extendedGamepad && !pad_gc_unread(c)) pad(c.vendorName,g_merge ? 0 : pad_slot_of(&g_slots,(__bridge const void *)c));
    for (hid_pad *p = g_hidpads; p; p = p->next) if (hidpad_player(p) >= 0) pad(@(p->name),hidpad_player(p));
    for (jc1_pad *p = g_jc1_pads; p; p = p->next) if (jc1pad_player(p) >= 0) pad(@(p->name),jc1pad_player(p));
    for (s2_pad *p = dm_switch2_pads(); p; p = p->next) pad(@(p->name),s2pad_player(p));
    [pads sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        int x=[a[@"player"] intValue] ?: INT_MAX, y=[b[@"player"] intValue] ?: INT_MAX;
        return x<y ? NSOrderedAscending : x>y ? NSOrderedDescending : [a[@"name"] compare:b[@"name"]];
    }];
    BOOL fr = g_ov_fr;
    NSMutableArray *actions = [NSMutableArray arrayWithObject:@(g_hq_text[HQ_TEXT_RESUME])];
    if (g_hq_arcane) [actions addObject:@(g_hq_text[HQ_TEXT_CONSOLE])];
    if (!g_hq.no_hold) [actions addObject:@(g_hq_text[HQ_TEXT_QUIT])];
    BOOL ldnActive = dm_net_in_local_room();
    long minutes = (long)((CACurrentMediaTime()-g_ov_started)/60);
    NSString *session = minutes >= 60 ? [NSString stringWithFormat:@"%ld h %ld min",minutes/60,minutes%60] :
        [NSString stringWithFormat:@"%ld min",minutes];
    NSMutableDictionary *d = [@{@"fr":@(fr), @"title":@(g_hq_text[HQ_TEXT_MENU_TITLE]), @"session":session,
        @"clock":[NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle],
        @"controllers":[NSString stringWithFormat:@"%lu %@",(unsigned long)pads.count,ov_text(fr,@"connected")],
        @"controllerRows":pads, @"actions":actions, @"canQuit":@(!g_hq.no_hold),
        @"resume":@(g_hq_text[HQ_TEXT_RESUME]), @"quitTitle":@(g_hq_text[HQ_TEXT_TITLE]), @"quitLabel":@(g_hq_text[HQ_TEXT_QUIT]),
        @"quitNote":@(g_hq_text[HQ_TEXT_NOTE]), @"cancel":@(g_hq_text[HQ_TEXT_CANCEL]), @"preset":@(g_hud.preset), @"hudLater":@(g_hud.enabled && !g_hud_live),
        @"position":@(g_hud.position), @"scale":@(g_hud.scale), @"opacity":@(g_hud.opacity),
        @"hudOptions":@(g_hud.options), @"hudElements":@(g_hud.elements), @"hudEnabled":@(g_hud.enabled),
        @"fullscreen":@((g_win.styleMask & NSWindowStyleMaskFullScreen)!=0),
        @"scope":ov_text(fr,g_hud.local ? @"For this game" : @"For all games"),
        @"volume":[NSString stringWithFormat:@"%d %%",g_ov_volume],
        @"ldn":ov_text(fr,ldnActive ? @"LDN room active" : dm_net_ldn_enabled() ? @"LDN enabled" : @"LDN disabled"),
        @"ldnActive":@(ldnActive)
    } mutableCopy];
    d[@"hudNotice"]=g_hud_notice; d[@"shoulders"]=g_ov_shoulders;
    d[@"cover"] = g_ov_cover; d[@"total"] = ov_env("DM_OVERLAY_PLAY_TIME");
    d[@"social"] = g_ov_social;
    d[@"canArcane"] = @(g_hq_arcane);
    if (g_ov_help_visible) {
        if (@available(macOS 27.0,*)) d[@"homeHelp"] = ov_home_help(fr,YES);
        else d[@"homeHelp"] = ov_home_help(fr,NO);
    }
    char username[33]; int online;
    if (dm_net_nextendo_enabled() && dm_nextendo_login_display(username,&online)) {
        d[@"nextendo"] = [NSString stringWithFormat:@"%s · %@",username,ov_text(fr,online > 0 ? @"Online play allowed" : online == 0 ? @"Online play unavailable" : @"Signed in")];
        d[@"onlineAllowed"] = @(online > 0);
    }
    d[@"network"] = g_ov_vpn; d[@"vpnUp"] = @(g_ov_vpn && ![g_ov_vpn isEqual:ov_text(fr,@"VPN not detected")]);
    BOOL first = !g_hq_view;
    [g_hq_view removeFromSuperview];
    g_hq_view = ov_view(cv.bounds,g_hq,d,g_ov_theme,^(NSInteger action, NSInteger index) { hq_action(action,index); });
    [cv addSubview:g_hq_view];
    if (first) {
        hq_fade(g_hq_view,1);
        NSAccessibilityPostNotification(g_hq_view, NSAccessibilityLayoutChangedNotification);
    }
}
static void hq_changed(hq_phase was) {
    hq_phase next = g_hq.phase;
    if (was == HQ_HOLDING && next != was) hq_hide_hold();
    if (hq_visible(next)) {
        if (!hq_visible(was)) {
            pads_release(); keys_touch_release(); [NSCursor setHiddenUntilMouseMoves:NO];
            BOOL exposes_home = NO;
            for (GCController *c in GCController.controllers)
                exposes_home |= c.extendedGamepad.buttonHome != nil || c.physicalInputProfile.buttons[GCInputButtonHome] != nil;
            if (!g_ov_help_once && exposes_home && (g_ov_home_system || !g_ov_home_seen)) {
                g_ov_help_visible = g_ov_help_once = YES;
            }
            char adapter[IF_NAMESIZE]; BOOL fr=g_ov_fr;
            g_ov_vpn = dm_net_vpn() ? ov_text(fr, dm_net_vpn_adapter(adapter) ?
                (!strncmp(adapter,"zt",2) ? @"ZeroTier connected" : @"VPN connected") : @"VPN not detected") : nil;
        }
        hq_show();
    } else {
        g_ov_help_visible = NO;
        g_hud_notice = nil;
        if (hq_visible(was)) hq_hide();
        if (next == HQ_IDLE && was == HQ_SETTLE) {
            if (atomic_exchange(&g_ov_display_motion_blocked,0)) dm_motion_pro_active(g_input_on);
            pads_reread();
        }
        if (next == HQ_QUIT) [NSApp terminate:nil];
        if (next == HQ_PAUSED) bg_enter();
    }
    hq_tick();
}
static int hq_clamp(int v, int max) { return v < 0 ? 0 : v > max ? max : v; }
static void hud_save(void) { ov_hud_save(g_hud_store,g_ov_game,g_hud); hud_apply(); }
static BOOL hud_slider_row(void) {
    return g_hq.card==HQ_HUD && !g_hq.advanced && (g_hq.row==HUD_OPACITY_ROW || g_hq.row==HUD_SCALE_ROW);
}
static void hud_slide(double value, BOOL relative) {
    BOOL scale=g_hq.row==HUD_SCALE_ROW; double *n=scale ? &g_hud.scale : &g_hud.opacity;
    *n=ov_hud_unit(relative ? *n+value : value,scale ? .1 : 0);
    g_hud_notice=nil;
}
static void hq_adjust(int step) {
    if (g_hq.card == HQ_VOLUME) {
        g_ov_volume = hq_clamp(g_ov_volume + 5*step,100); dm_audio_game_volume(g_ov_volume);
    } else if (g_hq.card == HQ_HUD) {
        int row=g_hq.row;
        g_hud_notice=nil;
        if (g_hq.advanced) {
            if (row==HUD_SCOPE) g_hud.local=!g_hud.local;
            else if (row==HUD_PASTE) {
                NSUInteger ignored;
                BOOL pasted=ov_hud_import([NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString],&g_hud,&ignored);
                g_hud_notice=ov_text(g_ov_fr,pasted ? @"Configuration pasted" : @"No valid HUD configuration");
                if (ignored) g_hud_notice=[g_hud_notice stringByAppendingFormat:@" · %@",[NSString stringWithFormat:ov_text(g_ov_fr,@"Ignored: %lu"),(unsigned long)ignored]];
                if (!pasted) return;
            } else if (row==HUD_COPY) {
                NSPasteboard *board=NSPasteboard.generalPasteboard;
                [board clearContents];
                if ([board setString:ov_hud_export(g_hud) forType:NSPasteboardTypeString]) g_hud_notice=ov_text(g_ov_fr,@"Configuration copied");
                return;
            } else if (row==HUD_ENABLE) {
                g_hud.enabled=!g_hud.enabled;
                if (g_hud.enabled && g_hud.preset==HUD_OFF) ov_hud_select(&g_hud,HUD_FPS);
                else g_hud.preset=HUD_CUSTOM;
            }
            else if (row<HUD_FIRST_METRIC) g_hud.options^=1u<<(row-HUD_FIRST_OPTION);
            else { g_hud.elements^=ov_hud_metrics[row-HUD_FIRST_METRIC].bit; g_hud.preset=HUD_CUSTOM; }
        } else if (row==HUD_PRESET_ROW) {
            int from=g_hud.preset==HUD_CUSTOM ? (step>0 ? HUD_FULL : HUD_OFF) : g_hud.preset;
            ov_hud_select(&g_hud,hq_neighbor(from,step,HUD_CUSTOM));
        } else if (row==HUD_POSITION_ROW) g_hud.position=hq_neighbor(g_hud.position,step,9);
        else if (hud_slider_row()) hud_slide(.01*step,YES);
        else return;
        hud_save();
    }
}
static void hq_toggle_display(void) {
    if (g_bg_fs_transition) return;
    g_hq.phase=HQ_DISPLAYING;
    g_ov_display_motion_blocked=1;
    dm_motion_pro_active(0); hidpad_motion_clear();
    dispatch_async(dispatch_get_main_queue(), ^{ [g_win toggleFullScreen:nil]; });
}
static void hq_display_finished(BOOL success) {
    if (g_hq.phase!=HQ_DISPLAYING) return;
    if (success) ov_fullscreen_save(g_hud_store,g_ov_game,(g_win.styleMask & NSWindowStyleMaskFullScreen)!=0);
    hq_display_done(&g_hq);
    hq_tick();
    hq_poll();
}
static void hq_shoulder(int step) {
    if (!step || g_hq.confirm) return;
    g_hud_notice=nil;
    if (g_hq.card==HQ_HUD) { hq_hud_page(&g_hq,!g_hq.advanced); return; }
    if (g_hq.phase==HQ_QUICK) { hq_quick_neighbor(&g_hq,step); return; }
    NSArray<NSNumber *> *tabs=ov_tabs(g_ov_social);
    int i=(int)[tabs indexOfObject:@(g_hq.tab)];
    g_hq.tab=tabs[hq_neighbor(i<0 ? 0 : i,step,(int)tabs.count)].intValue;
    g_hq.selection=g_hq.row=0; g_hq.card=-1;
}
static void hq_swap_home(void) {
    g_hq.swap=!g_hq.swap;
    [g_hud_store setBool:g_hq.swap forKey:@"home-swap"];
}
static void hq_action(NSInteger action, NSInteger index) {
    hq_phase was = g_hq.phase;
    if (!hq_visible(was)) return;
    switch (action) {
    case OV_BACK: hq_back(&g_hq); break;
    case OV_FULL: if (!g_hq.confirm) hq_open(&g_hq,HQ_FULL); break;
    case OV_TAB: if (!g_hq.confirm) { g_hq.tab=(int)index; g_hq.selection=0; g_hq.card=-1; g_hq.row=0; } break;
    case OV_SHOULDER: hq_shoulder((int)index); break;
    case OV_CONFIRM:
        if (g_hq.confirm) { if (index == 1 && !g_hq.no_hold) g_hq.phase=HQ_QUIT; else hq_back(&g_hq); }
        break;
    case OV_MAIN:
        if (g_hq.confirm || index < 0 || index >= hq_count()) return;
        g_hq.selection=(int)index; hq_hud_page(&g_hq,0); g_hud_notice=nil;
        if (g_hq.tab==OV_PROFILE) g_hq.phase=HQ_PAUSED;
        else if (g_hq.tab==OV_FRIENDS) break;
        else if (was==HQ_QUICK || g_hq.tab==OV_SETTINGS) {
            if (index==HQ_DISPLAY) { g_hq.card=-1; hq_toggle_display(); }
            else if (g_hq.tab==OV_SETTINGS && index==HQ_HOME_SETTING) { g_hq.card=-1; hq_swap_home(); }
            else if (index==HQ_POWER) { g_hq.card=-1; g_hq.confirm=1; }
            else g_hq.card=(int)index;
        } else if (!index) g_hq.phase=HQ_SETTLE;
        else if (index==1 && g_hq_arcane) g_hq.phase=HQ_PAUSED;
        else if (!g_hq.no_hold) g_hq.confirm=1;
        break;
    case OV_ROW:
        g_hq.row=(int)(index<0 ? -index-1 : index); hq_adjust(index<0 ? -1 : 1); break;
    case OV_VALUE: {
        int item=(int)(index<0 ? -index-1 : index);
        if (g_hq.tab!=OV_SETTINGS || g_hq.card>=0 || item<0 || item>HQ_HOME_SETTING) return;
        if (item>=HQ_DISPLAY) { hq_action(OV_MAIN,item); return; }
        if (item>HQ_VOLUME) return;
        g_hq.selection=g_hq.card=item; g_hq.row=0;
        hq_adjust(index<0 ? -1 : 1); g_hq.card=-1;
        break;
    }
    case OV_HUD_PAGE: hq_hud_page(&g_hq,(int)index); g_hud_notice=nil; break;
    case OV_SCROLL:
        if (g_hq.card!=HQ_HUD || !g_hq.advanced) return;
        g_hq.row=hq_clamp(g_hq.row+(int)index,HUD_ADVANCED_COUNT-1); break;
    case OV_SLIDE:
        if (g_hq.card!=HQ_HUD || g_hq.advanced) return;
        g_hq.row=(int)(index/10001); hud_slide((index%10001)/10000.0,NO); hud_apply(); return;
    case OV_SLIDE_DONE: hud_save(); break;
    }
    hq_changed(was);
}
static void hq_nav(unsigned nav) {
    if (!hq_visible(g_hq.phase)) return;
    int horizontal = !!(nav&HQ_RIGHT)-!!(nav&HQ_LEFT), vertical=!!(nav&HQ_DOWN)-!!(nav&HQ_UP);
    if (nav&HQ_A) {
        if (g_hq.confirm) hq_action(OV_CONFIRM,g_hq.row);
        else if (g_hq.card < 0) hq_action(OV_MAIN,g_hq.selection);
        else if (g_hq.card==HQ_HUD && !g_hq.advanced && g_hq.row==HUD_ADVANCED_ROW) hq_action(OV_HUD_PAGE,1);
        else if (g_hq.card<=HQ_VOLUME && !hud_slider_row()) hq_action(OV_ROW,g_hq.row);
        return;
    }
    if (g_hq.confirm) g_hq.row=hq_clamp(g_hq.row+horizontal+vertical,1);
    else if (hq_shoulders(nav)) { hq_shoulder(hq_shoulders(nav)); }
    else if (g_hq.card>=0) {
        if (g_hq.card==HQ_HUD && vertical) g_hq.row=hq_clamp(g_hq.row+vertical,g_hq.advanced ? HUD_ADVANCED_COUNT-1 : HUD_ADVANCED_ROW);
        int trigger=!!(nav&HQ_ZR)-!!(nav&HQ_ZL);
        if (hud_slider_row() && trigger) hq_adjust(10*trigger);
        else if (horizontal && !(g_hq.card==HQ_HUD && g_hq.advanced)) hq_adjust(horizontal);
    } else if (g_hq.tab==OV_SETTINGS && horizontal && !vertical && (g_hq.selection<=HQ_VOLUME || g_hq.selection>=HQ_DISPLAY)) {
        hq_action(OV_VALUE,horizontal>0 ? g_hq.selection : -g_hq.selection-1); return;
    } else if (hq_count()) g_hq.selection=hq_clamp(g_hq.selection+(g_hq.tab ? vertical : horizontal ? horizontal : vertical),hq_count()-1);
    hq_show();
}
static int hq_menu_key(unsigned short code, int down) {
    if (g_hq.disabled) return 0;
    if (down) [g_ov_keys_down addIndex:code];
    BOOL hot = code==g_ov_keys[0] || code==g_ov_keys[1];
    hq_phase was=g_hq.phase;
    if (down && hot) {
        hq_key_open(&g_hq,code==g_ov_keys[0] ? hq_long(&g_hq) : hq_short(&g_hq));
        if (was!=g_hq.phase) hq_changed(was);
    }
    else if (down && hq_visible(was)) switch (code) {
        case 53: case 40: hq_action(OV_BACK,0); break;
        case 36: case 38: hq_nav(HQ_A); break;
        case 123: hq_nav(HQ_LEFT); break; case 124: hq_nav(HQ_RIGHT); break;
        case 126: hq_nav(HQ_UP); break;   case 125: hq_nav(HQ_DOWN); break;
        case 34: if (was==HQ_QUICK) hq_action(OV_FULL,0); break;
        case 12: hq_nav(HQ_L); break; case 14: hq_nav(HQ_R); break;
    }
    if (g_hq.phase==HQ_SETTLE) hq_poll();
    return hot || hq_blocks_input(was);
}
static void hq_poll(void) {
    static int busy;
    static unsigned held;
    static double heldSince, repeatAt;
    if (g_hq.disabled || !g_win || !g_input_on || busy || cp_blocks_input(g_cp.phase)) return;
    busy = 1;
    int player, tap;
    unsigned buttons = hq_buttons(&player);
    if (buttons & HQ_HOME) g_ov_home_seen = YES;
    if (g_hq.phase == HQ_SETTLE && (g_ov_keys_down.count || (NSEvent.pressedMouseButtons & 1))) buttons |= HQ_OTHER;
    double now = CACurrentMediaTime();
    home_quit was = g_hq;
    unsigned nav = hq_step(&g_hq,now,buttons,&tap);
    if (was.phase == HQ_IDLE && g_hq.phase == HQ_HOLDING && g_hq.trigger == HQ_PLUS) g_ov_menu_player = player;
    if (tap && g_ov_menu_player >= 0) {
        g_hq_pulse=g_ov_menu_player;
        unsigned gen=++g_hq_pulse_serial; pads_reread();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC*65/1000),dispatch_get_main_queue(),^{
            if (gen==g_hq_pulse_serial) { g_hq_pulse=-1; if (g_input_on && !hq_blocks_input(g_hq.phase)) pads_reread(); }
        });
    }
    unsigned dirs=hq_visible(g_hq.phase) && hud_slider_row() ? buttons & (HQ_LEFT|HQ_RIGHT) : 0;
    int repeats=hq_slider_repeat(now,&heldSince,&repeatAt,&held,dirs);
    if (nav & (HQ_A|HQ_LEFT|HQ_RIGHT|HQ_UP|HQ_DOWN|HQ_L|HQ_R|HQ_ZL|HQ_ZR)) hq_nav(nav);
    else if (repeats && (dirs==HQ_LEFT || dirs==HQ_RIGHT)) { hq_adjust(dirs==HQ_LEFT ? -repeats : repeats); hq_show(); }
    else if (was.phase!=g_hq.phase || was.card!=g_hq.card || was.confirm!=g_hq.confirm || was.tab!=g_hq.tab || was.advanced!=g_hq.advanced) hq_changed(was.phase);
    double fill = hq_ring(&g_hq, now);
    if (fill >= 0) {
        if (!g_hq_hold) {
            NSView *cv = g_win.contentView; CAShapeLayer *ring = nil;
            g_hq_hold = hq_hold_view(cv.bounds,ov_text(g_ov_fr,g_hq.swap ? @"Keep holding for the full overlay" : @"Keep holding for quick access"),&ring);
            g_hq_ring = ring; ring.strokeColor = [g_ov_theme[@"focus"] CGColor];
            [cv addSubview:g_hq_hold];
        }
        hq_hold_set(g_hq_ring, fill);
    }
    hq_tick();
    busy = 0;
}
static void hq_close(void) {
    g_ov_help_visible = NO;
    [g_ov_keys_down removeAllIndexes]; g_ov_menu_player = g_hq_pulse = -1; g_hq_pulse_serial++;
    hq_cancel(&g_hq); hq_hide_hold(); hq_hide(); hq_tick();
}

// Launcher handoff from NX2Apple 0035 (see home_quit.h). Use the window's normal minimize/restore lifecycle, not a process or network suspend.
enum { BG_PLAYING, BG_HIDING, BG_HIDDEN };
static int g_bg, g_bg_fullscreen, g_bg_resume_pending;
static unsigned g_bg_generation;   // a timeout from a previous pause must not hide a later session

static void game_suspend(void) { input_release(); dm_focus_set(3); dm_audio_suspend(1); dm_gfx_suspend(1); }
static void game_restore(void) { dm_gfx_suspend(0); dm_audio_suspend(0); dm_focus_set(2); }
static NSString *bg_name(NSString *action) { return [NSString stringWithFormat:@"org.nxnative.%@.%d", action, getpid()]; }
static void bg_post(NSString *action) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:bg_name(action) object:nil userInfo:nil deliverImmediately:YES];
}

static void bg_restore_fullscreen(void) {
    if (g_bg || !g_bg_fullscreen || g_bg_fs_transition || !NSApp.isActive || !g_win.isOnActiveSpace) return;
    g_bg_fullscreen = 0;
    if (!(g_win.styleMask & NSWindowStyleMaskFullScreen)) [g_win toggleFullScreen:nil];
}
static void bg_front(void) {
    if (NSApp.hidden) [NSApp unhide:nil];
    [g_win makeKeyAndOrderFront:nil];
    if (!NSApp.isActive) [NSApp activate];
}
static void bg_resume(void) {
    if (g_bg == BG_HIDING) { g_bg_resume_pending = 1; return; }
    if (g_bg != BG_HIDDEN) return;
    g_bg = BG_PLAYING;
    hq_resumed(&g_hq);
    game_restore();
    bg_front();
    if (!g_input_on && g_win.isKeyWindow && NSApp.isActive) { input_resume(); dm_focus_set(1); }
    hq_tick();
    // macOS may still be leaving the launcher's Space; the active-Space observer also tries once it is ready.
    unsigned gen = g_bg_generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
        if (gen == g_bg_generation) bg_restore_fullscreen();
    });
    LOG("front end: resumed");
    bg_post(@"resumed");
}
static void bg_hide(void) {
    if (g_bg != BG_HIDING) return;
    const char *value = getenv("DM_LAUNCHER_BUNDLE_ID");
    NSString *bid = value ? [[NSString alloc] initWithUTF8String:value] : nil;
    if (bid.length) {
        NSRunningApplication *launcher = [NSRunningApplication runningApplicationsWithBundleIdentifier:bid].firstObject;
        if (launcher) {
            [NSApp yieldActivationToApplication:launcher];
            if (![launcher activateFromApplication:NSRunningApplication.currentApplication options:NSApplicationActivateAllWindows])
                LOG("front end: launcher did not take activation");
        } else {
            NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bid];
            if (url) [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:nil];
            else LOG("front end: launcher bundle unavailable");
        }
    }
    [NSApp hide:nil];
    g_bg = BG_HIDDEN;
    LOG("front end: paused in the background");
    bg_post(@"paused");
    if (g_bg_resume_pending) bg_resume();
}
static void bg_exit_fullscreen(void) {
    if (g_bg != BG_HIDING || g_bg_fs_transition) return;
    if (g_win.styleMask & NSWindowStyleMaskFullScreen) [g_win toggleFullScreen:nil];
    else bg_hide();
}
static void bg_enter(void) {
    g_bg = BG_HIDING;
    g_bg_fullscreen |= g_bg_fs_transition > 0 || (g_win.styleMask & NSWindowStyleMaskFullScreen) != 0;
    g_bg_resume_pending = 0;
    unsigned gen = ++g_bg_generation;
    game_suspend();
    bg_exit_fullscreen();
    if (g_bg == BG_HIDING) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (g_bg == BG_HIDING && gen == g_bg_generation) {
            LOG("front end: fullscreen exit did not finish, hiding the paused game");
            bg_hide();
        }
    });
}
static void bg_start(void) {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[NSWindowWillEnterFullScreenNotification, NSWindowWillExitFullScreenNotification])
        [nc addObserverForName:name object:g_win queue:nil usingBlock:^(NSNotification *n) {
            g_bg_fs_transition = [n.name isEqualToString:NSWindowWillEnterFullScreenNotification] ? 1 : -1;
        }];
    if (!g_hq_arcane) return;
    for (NSNotificationName name in @[NSApplicationDidBecomeActiveNotification, NSApplicationDidUnhideNotification])
        [nc addObserverForName:name object:NSApp queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            (void)n;
            if (g_bg == BG_HIDDEN && !NSApp.hidden) bg_resume();
            else if ([name isEqualToString:NSApplicationDidBecomeActiveNotification]) bg_restore_fullscreen();
        }];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        (void)n; bg_restore_fullscreen();
    }];
    NSDistributedNotificationCenter *dc = NSDistributedNotificationCenter.defaultCenter;
    [dc addObserverForName:bg_name(@"resume") object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        (void)n; if (g_bg) bg_resume(); else bg_front();
    }];
    [dc addObserverForName:bg_name(@"quit") object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        (void)n;
        if (g_bg) { dm_gfx_suspend(0); dm_audio_suspend(0); }   // release the gate before running the normal exit handlers
        [NSApp terminate:nil];
    }];
}

// The controller applet's prompt (front.h front_ctrl_support, ctrl_prompt.h; GitHub issue #1640): the game asked for more players than it sees, and the game's thread waits while
// the prompt is up over the game, as the Switch's player screen. A controller that joins meanwhile is a player at once (its first button with DM_PAD_PRESS_TO_JOIN, its
// connection without), and the count on the card follows. A and B are GameController's buttonA and buttonB on any controller, as the Home prompt's (a raw HID pad's A and B,
// pad_hid_mac.h); the press that makes a controller join does not count. Return or J is done, Escape or K closes it. The game gets no controller, keyboard or mouse input
// while it is up, nor until the A or B that closed it is let go. A front end passes the texts in the player's language as DM_CTRL_PROMPT_TEXT (cp_text)
static NSView *g_cp_view; static dispatch_semaphore_t g_cp_done; static int g_cp_ok, g_cp_shown_joined = -1, g_cp_shown_on = -1;
static void cp_buttons(int *a, int *b) {
    *a = *b = 0;
    for (GCController *c in GCController.controllers) { GCExtendedGamepad *g = c.extendedGamepad; if (g) { *a |= g.buttonA.isPressed; *b |= g.buttonB.isPressed; } }
    for (hid_pad *d = g_hidpads; d; d = d->next) { uint64_t m = d->twin && hidpad_is_pro(d) ? d->pro_m : pad_hid_buttons(&d->st); *a |= !!(m & DM_BTN_A); *b |= !!(m & DM_BTN_B); }
    for (s2_pad *d = dm_switch2_pads(); d; d = d->next) s2_pad_ab(&d->st, a, b);   // Switch 2 controllers (pad_switch2_apple.h)
    for (jc1_pad *d = g_jc1_pads; d; d = d->next) jc1_pad_ab(d, a, b);             // original Joy-Cons read from HID (pad_jc1_mac.h)
}
static int cp_waiting(void) {   // connected controllers that are no player yet
    if (g_merge) return 0;
    int n = 0;
    for (GCController *c in GCController.controllers) if (c.extendedGamepad && !pad_gc_unread(c) && pad_slot_of(&g_slots, (__bridge const void *)c) < 0) n++;
    for (jc1_pad *d = g_jc1_pads; d; d = d->next) if (pad_slot_of(&g_slots, d) < 0) n++;
    for (hid_pad *d = g_hidpads; d; d = d->next) if (pad_slot_of(&g_slots, d) < 0) n++;
    for (s2_pad *d = dm_switch2_pads(); d; d = d->next) if (pad_slot_of(&g_slots, d) < 0) n++;
    return n;
}
static void cp_show(void) {   // the card, built again when its count or its done action changes
    int on = cp_can_confirm(&g_cp);
    if (g_cp_view && g_cp_shown_joined == g_cp.joined && g_cp_shown_on == on) return;
    const char *env = getenv("DM_CTRL_PROMPT_TEXT"); char t[CP_TEXTS][256];
    for (int i = 0; i < CP_TEXTS; i++) cp_text(env, i, &g_cp, t[i], sizeof t[i]);
    GCExtendedGamepad *g = nil; for (GCController *c in GCController.controllers) if ((g = c.extendedGamepad)) break;
    NSView *cv = g_win.contentView, *v = hq_card_view(cv.bounds, @(t[CP_TEXT_TITLE]), [NSString stringWithFormat:@"%s\n%s", t[CP_TEXT_HINT], t[CP_TEXT_COUNT]], @(t[CP_TEXT_DONE]),
                                                   @(t[CP_TEXT_CANCEL]), g.buttonA.sfSymbolsName, g.buttonB.sfSymbolsName, on);
    if (g_cp_view) [g_cp_view removeFromSuperview];
    [cv addSubview:v]; if (!g_cp_view) hq_fade(v, 1);
    g_cp_view = v; g_cp_shown_joined = g_cp.joined; g_cp_shown_on = on;
}
// One step of the prompt (a button, a key, a controller joining, coming or going); returns whether it keeps the game's input
static int cp_poll(void) {
    if (g_cp.phase == CP_IDLE) return 0;
    int a, b, joined = dm_players_reported(); cp_buttons(&a, &b);
    int confirm = g_cp_confirm, cancel = g_cp_cancel; g_cp_confirm = g_cp_cancel = 0;
    cp_phase was = g_cp.phase, ph = cp_step(&g_cp, joined, cp_waiting(), a, b, confirm, cancel);
    if (was == CP_OPEN && ph == CP_OPEN) cp_show();
    if (was == CP_OPEN && ph != CP_OPEN) {
        hq_fade(g_cp_view, 0); g_cp_view = nil;
        LOG("front end: controller prompt closed: %d players (%s)", joined, g_cp.ok ? "done" : "canceled");
        g_cp_ok = g_cp.ok; dispatch_semaphore_signal(g_cp_done);
        ph = cp_step(&g_cp, joined, 0, a, b, 0, 0);   // nothing held: the game has its input at once
    }
    if (ph == CP_IDLE) { pads_reread(); return 0; }   // each controller read as it is now
    return 1;
}
int front_ctrl_support(int min, int max) {
    if (!g_layer) return -1;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        hq_close();
        if (g_hq.phase == HQ_SETTLE) g_hq.phase = HQ_IDLE;   // the native controller applet now owns input and its own release gate
        hq_tick();
        keys_touch_release();   // nothing the game held stays pressed while the prompt has the input
        pads_release();
        int a, b; cp_buttons(&a, &b);
        g_cp_done = done; cp_open(&g_cp, min, max, dm_players_reported(), a, b);
        LOG("front end: controller prompt open: %d to %d players wanted, %d in, %d controllers waiting to join", min, max, g_cp.joined, cp_waiting());
        cp_show(); cp_poll();
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return g_cp_ok;
}
static void pads_start(void) {
    const char *e = getenv("DM_PAD_MERGE"); g_merge = e && atoi(e);
    e = getenv("DM_KBD_PLAYER"); g_kbd_own = !g_merge && e && !strcmp(e, "own");
    e = getenv("DM_PAD_PRESS_TO_JOIN"); g_press_to_join = !g_merge && e && atoi(e);
    static const char kbd = 0;
    if (g_kbd_own) pad_slot_take(&g_slots, &kbd, "keyboard");   // holds player 1 for good
    LOG("front end: %s", g_merge ? "every controller is player 1 (DM_PAD_MERGE)" : g_kbd_own ? "the keyboard is player 1, each controller a player of its own from player 2 on (DM_KBD_PLAYER=own)"
                                                                           : "each controller is a player of its own, the keyboard plays with player 1");
    if (g_press_to_join) LOG("front end: a controller becomes a player at its first button press, the lowest player free (DM_PAD_PRESS_TO_JOIN)");
    hq_start();
    pads_changed(nil);
    dm_motion_pro_start(pro_devices_changed);
    dm_jc1_start(g_merge);
    hidpad_start();
    static const dm_switch2_front s2front = {s2pad_attach, s2pad_detach, s2pad_read, s2pad_player, s2pad_blocked};
    dm_switch2_start(&s2front);
}

// Mouse as a single-point touchscreen (front.h dm_touch_set): left button down / drag = finger 0, release = lifted. The content view takes the clicks,
// not a window-wide event monitor, so clicks on the title bar, the window buttons and the resize edges still reach AppKit.
// The picture's width / height (front.h front_picture_shape; 16:9 until the first present), which the present fits into the view
static _Atomic double g_picture_aspect = 16.0 / 9.0;
void front_picture_shape(int w, int h) { if (w > 0 && h > 0) g_picture_aspect = (double)w / h; }
@interface DmGameView : NSView @end
// Keep the Metal layer in its own view: AppKit can then sample the sibling behind
// the visual effect without making the Metal view responsible for AppKit sublayers.
@interface DmPictureView : NSView @end
@implementation DmPictureView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
@end
@implementation DmGameView
- (void)mouseDown:(NSEvent *)e { [self mouseDragged:e]; }
- (void)mouseDragged:(NSEvent *)e {
    if (!g_input_on || hq_blocks_input(g_hq.phase)) return;
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; NSSize b = self.bounds.size;
    double w = b.width, h = b.height;
    if (w <= 0 || h <= 0) return;
    double a = g_picture_aspect; if (w / h > a) w = h * a; else h = w / a;   // the centered picture the present fits into the view (16:9, or a taller one under DM_SCREEN_ASPECT)
    double x0 = (b.width - w) / 2, y0 = (b.height - h) / 2;
    dm_touch t = {0, (float)fmin(fmax((p.x - x0) / w, 0), 0.999), (float)fmin(fmax(1 - (p.y - y0) / h, 0), 0.999)};   // The AppKit view origin is at bottom left, the touchscreen origin is at top left
    dm_touch_set(&t, 1); g_mouse_down = 1;
}
- (void)mouseUp:(NSEvent *)e { (void)e; if (g_mouse_down) { g_mouse_down = 0; dm_touch_set(NULL, 0); } }
// The drawable follows the view in pixels: a layer assigned to a layer-backed view kept the drawable at the first window's 1280x720 in fullscreen too, so the game picture was
// scaled down to it and up again by the compositor
- (void)fitDrawable {
    CAMetalLayer *l = g_layer; if (!l || !self.window) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES]; l.frame = self.bounds; [CATransaction commit];
    l.contentsScale = self.window.backingScaleFactor;
    NSSize px = [self convertSizeToBacking:self.bounds.size]; if (px.width < 1 || px.height < 1 || CGSizeEqualToSize(l.drawableSize, px)) return;
    l.drawableSize = px; LOG("front end: drawable %.0fx%.0f", px.width, px.height);
}
- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; [self fitDrawable]; hq_show(); }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; [self fitDrawable]; }
@end

// AppKit reports a refused fullscreen request only to the window delegate (there is no notification for it)
static void (^g_fs_failed)(void);
@interface DmWinDelegate : NSObject <NSWindowDelegate> @end
@implementation DmWinDelegate
- (void)windowDidFailToEnterFullScreen:(NSWindow *)w {
    (void)w; g_bg_fs_transition = 0;
    hq_display_finished(NO);
    if (g_bg == BG_HIDING) bg_exit_fullscreen();
    else if (g_fs_failed) g_fs_failed();
}
- (void)windowDidFailToExitFullScreen:(NSWindow *)w { (void)w; g_bg_fs_transition = 0; hq_display_finished(NO); bg_hide(); bg_restore_fullscreen(); }
@end

typedef struct { void (*fn)(void); } guest_arg;
static void *guest_tramp(void *p) {
    static char alt[65536];                       // The signal alternate stack is per thread; crash printing must also work on the guest thread
    stack_t ss = {.ss_sp = alt, .ss_size = sizeof alt}; sigaltstack(&ss, 0);
    ((guest_arg *)p)->fn(); LOG("guest thread finished"); exit(0);
}

// Metal reads MTL_HUD_ENABLED when the process makes its first device, which can be before the window: set from DM_METAL_HUD before main (set in front_run, the HUD did not show)
__attribute__((constructor)) static void hud_env(void) {
    front_hud_env();
    if (!hud_forced()) @autoreleasepool {   // the saved HUD choice (the overlay's card) turns it on unless it is Off
        NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:@"org.nxnative.overlay"];
        ov_hud hud=ov_hud_load(store,[@"game-" stringByAppendingString:@(DM_GAME_ID)]);
        if (hud.enabled) {
            setenv("MTL_HUD_ENABLED","1",0);
            if (hud.preset==HUD_FPS) setenv("MTL_HUD_ELEMENTS","fps",1);
            // Apple may reserve some instrumentation when creating the device.
            setenv("MTL_HUD_ENCODER_TIMING_ENABLED",hud.options & 2u ? "1" : "0",1);
        }
    }
    g_hud_live = getenv("MTL_HUD_ENABLED") && atoi(getenv("MTL_HUD_ENABLED"));
}

// ---------- Cheats: the menu and the panel (hle_cheats.c holds every state; these only show it and call it) ----------

// A string of the engine as an NSString that is never nil: cheat names, sections and notes come from the player's files,
// which may be Shift-JIS or Latin-1, and a UTF-8 name cut at the engine's buffer size may end in half a character. UTF-8
// first, then UTF-8 without up to three trailing bytes, then Shift-JIS, then Windows-1252 (which decodes any byte)
static NSString *engine_str(const char *s) {
    if (!s) return @"";
    size_t n = strlen(s);
    for (size_t cut = 0; cut <= 3 && cut <= n; cut++) {
        NSString *u = [[NSString alloc] initWithBytes:s length:n - cut encoding:NSUTF8StringEncoding];
        if (u) return u;
    }
    return [[NSString alloc] initWithBytes:s length:n encoding:NSShiftJISStringEncoding]
        ?: [[NSString alloc] initWithBytes:s length:n encoding:NSWindowsCP1252StringEncoding] ?: @"";
}

// A path quoted for the shell (single quotes; a quote inside becomes '\'')
static NSString *shell_quote(NSString *p) { return [NSString stringWithFormat:@"'%@'", [p stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; }

// The name a row shows: the on half of an on / off pair loses its " - on" (the pair is one switch, its off half has no row)
static NSString *cheat_display_name(int i) {
    NSString *n = engine_str(dm_cheat_name_at(i));
    if (!(dm_cheat_flags_at(i) & DM_CHEAT_PAIR_ON)) return n;
    static NSRegularExpression *re;
    if (!re) re = [NSRegularExpression regularExpressionWithPattern:@"(\\s*[-:_]\\s*|\\s+|\\s*[(\\[]\\s*)on\\s*[)\\]]?\\s*$" options:NSRegularExpressionCaseInsensitive error:nil];
    NSString *base = [re stringByReplacingMatchesInString:n options:0 range:NSMakeRange(0, n.length) withTemplate:@""];
    return base.length ? base : n;
}

// Does entry i get a row of its own? Not the off half of a pair (its on half is the switch) and not a section marker
// (the section shows as a header above its entries)
static BOOL cheat_has_row(int i) {
    int f = dm_cheat_flags_at(i);
    return !(f & (DM_CHEAT_PAIR_OFF | DM_CHEAT_SECTION_START | DM_CHEAT_SECTION_END));
}

// The row's whole title, the same string the menu's row carries: the name, plus the run-time reason when there is one,
// "— master code (always on)" for a master code, "(nxnative only)" for a cheat this host runs itself (never-decrease)
static NSString *cheat_row_title(int i) {
    const char *why = dm_cheat_why_at(i);
    int kind = dm_cheat_kind_at(i), f = dm_cheat_flags_at(i);
    NSString *n = cheat_display_name(i);
    if (kind == 1) return [n stringByAppendingString:@" — master code (always on)"];
    if (why && *why) return [n stringByAppendingString:engine_str(why)];
    if (f & DM_CHEAT_HOST) return [n stringByAppendingString:@" (nxnative only)"];
    return n;
}

// The row's tooltip: the title, the meta file's note (how scripts/cheat_anchor.py compiled it), what a host-only or a
// one-pass cheat does
static NSString *cheat_row_tip(int i) {
    NSMutableString *t = [cheat_row_title(i) mutableCopy];
    int f = dm_cheat_flags_at(i);
    const char *note = dm_cheat_note_at(i);
    if (note && *note) [t appendFormat:@"\n%@", engine_str(note)];
    if (f & DM_CHEAT_HOST) [t appendString:@"\nRun by nxnative itself: it keeps the highest value seen since it was turned on; other engines see an empty entry."];
    if (f & DM_CHEAT_ONCE) [t appendString:@"\nApplied once: it writes one pass, then turns itself off."];
    if (f & DM_CHEAT_PAIR_ON) [t appendString:@"\nSwitching it off puts the game's original code back."];
    if (f & DM_CHEAT_WEAK) [t appendString:@"\nResolved weakly for this build: check its effect."];
    return t;
}

// The row's state as hle_cheats.c has it: a plain cheat carries its own on state, a master code is always on, and a
// disabled row (unsupported opcode, malformed, or killed at run time) or a label is off, its checkbox not clickable
static NSControlStateValue cheat_row_state(int i) {
    int kind = dm_cheat_kind_at(i);
    return kind == 1 || (kind == 0 && dm_cheat_on_at(i)) ? NSControlStateValueOn : NSControlStateValueOff;
}

// A build's name for a player: "1.0.3 (build E1D8B399B787AE41)", or the build ID alone when its version is unknown
static NSString *build_label(const char *bid, const char *ver) {
    return ver && *ver ? [NSString stringWithFormat:@"%@ (build %@)", engine_str(ver), engine_str(bid)] : [NSString stringWithFormat:@"build %@", engine_str(bid)];
}

// "Open cheats folder": the menu's and the panel's action, one helper — create the folder when missing, then reveal it in Finder
static void cheats_open_folder(void) {
    const char *dir = dm_cheats_dir_path();
    if (dir && *dir) { mkdir(dir, 0755); [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:@(dir)]]; }
}

// The Cheats panel (the menu's "Show Cheats Window", ⌘⇧C, or DM_CHEATS_WINDOW=1 at launch): a utility NSPanel that stays
// open beside the game window, toggles applied live, scrollable. It never takes the key window from the game for a click
// (becomesKeyOnlyIfNeeded, shown with orderFront), so the game keeps the keyboard and the controllers; it becomes key only
// while the player types in its search field or a value field, and Return or Escape there hands the keyboard back.
// Created once lazily and kept for the process's lifetime, closed only to hide (its place and size survive in the frame
// autosave "DmCheatsPanel"). Every row comes from the C API (dm_cheat* in dm.h); the class holds no cheats state of its own
// beyond the controls. Top to bottom:
//   - the header (game build and version, counts) and, when it applies, a line about safe mode with Restore;
//   - Cheats On (the master switch), Select All / Deselect All and the search field;
//   - the rows: section headers, labels, one row per cheat (an on / off pair is one row; a "set" cheat has an Apply button
//     instead of a checkbox; an "ask" cheat a value field; ⓘ shows its details), then the cheats the compiler left out,
//     the other builds' files, and the anchored sources not compiled for this build;
//   - a details line (a cheat's dry run and note, or the load report);
//   - Reload, Open folder, Find Cheats… (in Ryujinx, the yuzu family and SD cards) and Report.
// A .txt or a .cheats.toml dropped on the panel is copied into the cheats folder (import below; the drop works from a
// background Finder window, see DmCheatsDropView). The rows are rebuilt
// when what they were built from changes (a reload, the search text), updated in place otherwise; a ~1 s timer runs only
// while the panel is visible
@interface DmCheatsPanel : NSObject <NSWindowDelegate, NSTextFieldDelegate, NSSearchFieldDelegate>
- (void)show;      // create the panel if needed, order it front (not key) and refresh
- (void)refresh;   // the one refresh for every trigger: shown, a click, Reload, a Cheats-menu toggle, the 1 s timer
- (BOOL)importFiles:(NSArray<NSURL *> *)urls;   // copy dropped / found cheat files into the cheats folder, reload
@end
static DmCheatsPanel *g_cheats_panel;   // created on the first Show Cheats Window, kept for the process's lifetime

// The panel class: a panel may become key (its search and value fields need the keyboard); becomesKeyOnlyIfNeeded keeps a
// checkbox click from making it key
@interface DmCheatsNSPanel : NSPanel @end
@implementation DmCheatsNSPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

// The panel's content view: it takes dropped files (a .txt or .cheats.toml) for the import. The utility panel hides while
// another app is in front, so a drop works from a Finder window dragged without activating Finder first (a background
// window), not after clicking into Finder; Find Cheats… covers the usual places without a drag
@interface DmCheatsDropView : NSView @end
@implementation DmCheatsDropView
// A drag enters: accept it as a copy when it carries a cheat file
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
    NSArray *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *u in urls) {
        NSString *e = u.lastPathComponent.lowercaseString;
        if ([e hasSuffix:@".txt"] || [e hasSuffix:@".cheats.toml"]) return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}
// The drop: the import runs a main-queue turn later, so its questions (modal alerts) do not hold Finder's drag session open
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    NSArray *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls.count || !g_cheats_panel) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ [g_cheats_panel importFiles:urls]; });
    return YES;
}
@end

// The scroll view's document view: flipped, so the stack view's rows start at the top and the scroll position counts
// downward like the rows (unflipped, everything would sit at the bottom of the document view)
@interface DmCheatsDocView : NSView @end
@implementation DmCheatsDocView
- (BOOL)isFlipped { return YES; }
@end

// The Cheats menu of the game window (hle_cheats.c's rows, only meaningful with a window): rebuilt on every open, so the
// loaded file's state, the menu's toggles and the cheats the VM disabled at run time are what the player sees. Rows: Show
// Cheats Window (⌘⇧C), Cheats On (the master switch) and, in safe mode, Restore Saved Cheats; then the panel's rows in
// short (section headers, labels, one row per cheat, a pair as one row, "set" cheats applied on click), the other builds'
// files when none of this build is loaded, and Reload cheats (⌘R) / Open cheats folder. A click here also refreshes the
// panel when one exists, so the two never disagree
@interface DmCheatsMenuDelegate : NSObject <NSMenuDelegate>
@end
@implementation DmCheatsMenuDelegate
// Rebuild the menu's rows from the engine (every open, and once at launch so its key equivalents exist)
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSMenuItem *sh = [menu addItemWithTitle:@"Show Cheats Window" action:@selector(showPanel:) keyEquivalent:@"c"];
    sh.target = self;
    sh.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;   // ⌘⇧C (the plain "c" already maps ZR)
    NSMenuItem *ms = [menu addItemWithTitle:@"Cheats On" action:@selector(toggleMaster:) keyEquivalent:@""];
    ms.target = self; ms.state = dm_cheats_master() ? NSControlStateValueOn : NSControlStateValueOff;
    if (dm_cheats_safe()) [menu addItemWithTitle:@"Restore Saved Cheats (safe mode)" action:@selector(restoreSafe:) keyEquivalent:@""].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    const char *sec = "";
    for (int i = 0, n = dm_cheats_ncheats(); i < n; i++) {
        if (!cheat_has_row(i)) continue;
        const char *s = dm_cheat_section_at(i);
        if (strcmp(s, sec)) {   // a section header before its first entry
            sec = s;
            if (*s) [menu addItemWithTitle:[NSString stringWithFormat:@"— %@ —", engine_str(s)] action:nil keyEquivalent:@""].enabled = NO;
        }
        int kind = dm_cheat_kind_at(i), f = dm_cheat_flags_at(i);
        NSString *title = cheat_row_title(i);
        if (f & DM_CHEAT_ONCE) title = [title stringByAppendingString:@" (apply once)"];
        NSMenuItem *it = [menu addItemWithTitle:title action:nil keyEquivalent:@""];
        if (kind == 0) { it.target = self; it.action = @selector(toggleCheat:); it.tag = i; }
        it.enabled = kind == 0;
        it.state = cheat_row_state(i);
        it.toolTip = cheat_row_tip(i);
    }
    for (int i = 0, n = dm_cheats_nothers(); i < n; i++)   // .txt files of other builds, lightly disabled (the brief's wording)
        [menu addItemWithTitle:[NSString stringWithFormat:@"Cheats for %@ (another version of the game)", build_label(dm_cheats_other(i), dm_cheats_other_version(i))] action:nil keyEquivalent:@""].enabled = NO;
    if (!dm_cheats_found())
        [menu addItemWithTitle:[NSString stringWithFormat:@"No cheats for %@", build_label(dm_cheats_build(), dm_cheats_version())] action:nil keyEquivalent:@""].enabled = NO;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *re = [menu addItemWithTitle:@"Reload cheats" action:@selector(reloadCheats:) keyEquivalent:@"r"];
    re.target = self;
    const char *dir = dm_cheats_dir_path();
    NSMenuItem *op = [menu addItemWithTitle:@"Open cheats folder" action:dir && *dir ? @selector(openCheatsFolder:) : nil keyEquivalent:@""];
    op.target = self;
    op.enabled = dir && *dir != 0;
}
// A cheat row: toggle it (a "set" cheat runs one pass)
- (void)toggleCheat:(NSMenuItem *)it {
    dm_cheat_toggle((int)it.tag);
    it.state = dm_cheat_on_at((int)it.tag) ? NSControlStateValueOn : NSControlStateValueOff;   // The new state right now; a run-time [RED] kill shows its reason when the menu next opens
    if (g_cheats_panel) [g_cheats_panel refresh];   // the panel (if created) follows the menu so the two never disagree; its visibility is checked there
}
// Cheats On: the master switch
- (void)toggleMaster:(NSMenuItem *)it { (void)it; dm_cheats_master_set(!dm_cheats_master()); if (g_cheats_panel) [g_cheats_panel refresh]; }
// Restore Saved Cheats: leave safe mode
- (void)restoreSafe:(NSMenuItem *)it { (void)it; dm_cheats_safe_restore(); if (g_cheats_panel) [g_cheats_panel refresh]; }
// Reload cheats (⌘R): re-read the file in place
- (void)reloadCheats:(NSMenuItem *)it { (void)it; dm_cheats_reload(); if (g_cheats_panel) [g_cheats_panel refresh]; }
// Open cheats folder: create it when missing, reveal it in Finder
- (void)openCheatsFolder:(NSMenuItem *)it { (void)it; cheats_open_folder(); }
// Lazily create the panel on the first Show Cheats Window (it is kept for the process's lifetime) and order it front:
// orderFront keeps the game the key window
- (void)showPanel:(NSMenuItem *)it {
    (void)it;
    if (!g_cheats_panel) g_cheats_panel = [DmCheatsPanel new];   // created here, on the first Show Cheats Window
    [g_cheats_panel show];
}
@end
static DmCheatsMenuDelegate *g_cheats_menu;   // NSMenu keeps its delegate unretained

@implementation DmCheatsPanel {
    NSPanel *_panel;              // created once in show, kept for the process's lifetime
    NSTextField *_header;         // the one-line status line above the rows
    NSStackView *_safeRow;        // safe mode's line and Restore, hidden otherwise
    NSButton *_master;            // Cheats On: the master switch
    NSButton *_selectAll;         // enabled while some plain cheat is off
    NSButton *_deselectAll;       // enabled while some plain cheat is on
    NSSearchField *_search;       // filters the rows by name and section
    NSScrollView *_scroll;        // scrolls the rows
    NSStackView *_stack;          // the rows (vertical, leading alignment), inside _doc
    NSView *_doc;                 // the flipped document view the stack is pinned to
    NSTextField *_details;        // a cheat's dry run and note, or the load report
    NSButton *_openFolder;        // disabled while dm_cheats_dir_path() is empty
    NSMutableDictionary<NSNumber *, NSButton *> *_checks;   // cheat index -> its checkbox (or Apply button), to update in place
    NSMutableDictionary<NSNumber *, NSTextField *> *_values; // cheat index -> its value field
    NSMutableDictionary<NSNumber *, NSTextField *> *_labels; // cheat index -> the name label of a "set" cheat's row
    BOOL _rebuilding;             // the rows are being replaced: a field's end of editing then applies nothing
    NSString *_rows_sig;          // what the rows on screen were built from: a change rebuilds
    int _detailsFor;              // the cheat whose details are shown (-1: the report, -2: nothing)
    NSTimer *_refreshTimer;       // ~1 s, scheduled only while the panel is on screen; invalidated when it hides
    BOOL _upOnDeactivate;         // the panel was on screen when the app was deactivated: AppKit brings it back on activation
    BOOL _finding;                // a Find Cheats… scan is running on a background queue: another click does not start a second one
}

// A button of the panel's toolbar rows
static NSButton *panel_button(NSString *title, id target, SEL action) { return [NSButton buttonWithTitle:title target:target action:action]; }

// A horizontal row of views, leading-aligned
static NSStackView *panel_hrow(NSArray<NSView *> *views) {
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = NSUserInterfaceLayoutOrientationHorizontal; s.spacing = 8; s.translatesAutoresizingMaskIntoConstraints = NO;
    return s;
}

// A secondary-colour label that truncates instead of widening the panel, its whole text in the tooltip
static NSTextField *panel_note(NSString *text) {
    NSTextField *l = [NSTextField labelWithString:text];
    l.textColor = NSColor.secondaryLabelColor; l.lineBreakMode = NSLineBreakByTruncatingTail; l.toolTip = text;
    [l setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return l;
}

// Create the panel, the content view and the fixed layout once (header, safe-mode line, toolbar, scrolled rows, details,
// bottom buttons); refresh fills the rows afterwards
- (void)makePanel {
    _panel = [[DmCheatsNSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 480, 560)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                        | NSWindowStyleMaskUtilityWindow
                                                  backing:NSBackingStoreBuffered defer:NO];
    _panel.title = @"Cheats";
    _panel.releasedWhenClosed = NO;         // the close button only hides (windowShouldClose)
    _panel.floatingPanel = YES;             // above the game window
    _panel.becomesKeyOnlyIfNeeded = YES;    // a checkbox click never takes the key window: the game keeps keyboard and controllers
    _panel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;   // shows over the fullscreen game too
    _panel.frameAutosaveName = @"DmCheatsPanel";   // place and size remembered (set after the frame is read back: makePanel's end)
    _panel.minSize = NSMakeSize(360, 260);
    _panel.delegate = self;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(appResignedActive:) name:NSApplicationDidResignActiveNotification object:NSApp];
    [nc addObserver:self selector:@selector(appBecameActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
    DmCheatsDropView *content = [[DmCheatsDropView alloc] initWithFrame:NSMakeRect(0, 0, 480, 560)];
    [content registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    _panel.contentView = content;

    _header = [NSTextField labelWithString:@""];
    _header.translatesAutoresizingMaskIntoConstraints = NO;
    _header.lineBreakMode = NSLineBreakByTruncatingTail;
    [_header setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *safeText = panel_note(@"Last run ended unexpectedly with cheats on: all are off.");
    safeText.textColor = NSColor.systemOrangeColor;
    _safeRow = panel_hrow(@[safeText, panel_button(@"Restore", self, @selector(restoreSafe:))]);
    _master = [NSButton checkboxWithTitle:@"Cheats On" target:self action:@selector(toggleMaster:)];
    _selectAll = panel_button(@"Select All", self, @selector(selectAllCheats:));
    _deselectAll = panel_button(@"Deselect All", self, @selector(deselectAllCheats:));
    _search = [NSSearchField new];
    _search.placeholderString = @"Search";
    _search.delegate = self;
    _search.sendsSearchStringImmediately = YES;
    [_search setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *tools = panel_hrow(@[_master, _selectAll, _deselectAll, _search]);

    _scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scroll.hasVerticalScroller = YES; _scroll.autohidesScrollers = YES;
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _doc = [[DmCheatsDocView alloc] initWithFrame:NSZeroRect];
    _doc.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.documentView = _doc;
    _stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeLeading;
    _stack.spacing = 4;
    _stack.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_doc addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.topAnchor constraintEqualToAnchor:_doc.topAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:_doc.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_doc.trailingAnchor],
        [_doc.leadingAnchor constraintEqualToAnchor:_scroll.contentView.leadingAnchor],
        [_doc.widthAnchor constraintEqualToAnchor:_scroll.contentView.widthAnchor],     // no horizontal scrolling
        [_doc.topAnchor constraintEqualToAnchor:_scroll.contentView.topAnchor],
        [_doc.bottomAnchor constraintEqualToAnchor:_stack.bottomAnchor],
    ]];

    _details = [NSTextField wrappingLabelWithString:@""];
    _details.translatesAutoresizingMaskIntoConstraints = NO;
    _details.selectable = NO;   // a selectable label would make the panel key on a click and keep the keyboard from the game
    _details.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    _details.maximumNumberOfLines = 8;
    [_details setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _detailsFor = -2;

    _openFolder = panel_button(@"Open Folder", self, @selector(openFolder:));
    NSStackView *bottom = panel_hrow(@[panel_button(@"Reload", self, @selector(reload:)), _openFolder,
                                       panel_button(@"Find Cheats…", self, @selector(findCheats:)), panel_button(@"Report", self, @selector(showReport:))]);
    // the header, the safe-mode line and the toolbar in one column: a stack view detaches a hidden view, so the safe-mode
    // line takes no room while it is hidden
    NSStackView *top = [NSStackView stackViewWithViews:@[_header, _safeRow, tools]];
    top.orientation = NSUserInterfaceLayoutOrientationVertical; top.alignment = NSLayoutAttributeLeading; top.spacing = 6;
    top.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *v in @[top, _scroll, _details, bottom]) [content addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [top.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [top.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [top.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [_header.trailingAnchor constraintEqualToAnchor:top.trailingAnchor],
        [tools.trailingAnchor constraintEqualToAnchor:top.trailingAnchor],
        [_scroll.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:8],
        [_scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:_details.topAnchor constant:-6],
        [_details.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [_details.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [_details.bottomAnchor constraintEqualToAnchor:bottom.topAnchor constant:-6],
        [bottom.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [bottom.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-8],
        [bottom.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8],
    ]];
    _checks = [NSMutableDictionary dictionary];
    _values = [NSMutableDictionary dictionary];
    _labels = [NSMutableDictionary dictionary];
    _rows_sig = @"";
    if (![_panel setFrameUsingName:@"DmCheatsPanel"] && g_win) {   // first use: beside the game window, not the screen's corner
        NSRect g = g_win.frame, f = _panel.frame;
        [_panel setFrameOrigin:NSMakePoint(NSMaxX(g) + 8, NSMaxY(g) - f.size.height)];
    }
}

// The panel became key: keep it only while one of its fields is being edited (a click elsewhere, Full Keyboard Access
// on a button, the search field's clear button); otherwise the keyboard goes back to the game a main-queue turn later,
// once the click has settled the first responder
- (void)windowDidBecomeKey:(NSNotification *)n {
    (void)n;
    dispatch_async(dispatch_get_main_queue(), ^{ if (![self editing]) [self giveKeyBack]; });
}

// Is the search field or a value field being edited (its field editor is the panel's first responder)?
- (BOOL)editing {
    if (_search.currentEditor) return YES;
    for (NSTextField *v in _values.allValues) if (v.currentEditor) return YES;
    return NO;
}

// Give the keyboard back to the game: after typing in the search or a value field (Return, Escape, the end of editing)
- (void)giveKeyBack {
    if (g_win && _panel.isKeyWindow) [g_win makeKeyWindow];
}

// ---- the actions ----

// Open Folder: create the cheats folder when missing, reveal it in Finder
- (void)openFolder:(NSButton *)b { (void)b; cheats_open_folder(); }
// Reload: re-read the file in place (edits during play need no re-launch)
- (void)reload:(NSButton *)b { (void)b; dm_cheats_reload(); [self refresh]; }
// Cheats On: the master switch (off stops every cheat without touching the toggles)
- (void)toggleMaster:(NSButton *)b { (void)b; dm_cheats_master_set(!dm_cheats_master()); [self refresh]; }
// Restore (safe mode): the saved toggles and the masters come back
- (void)restoreSafe:(NSButton *)b { (void)b; dm_cheats_safe_restore(); [self refresh]; }
// Report: the load report in the details line
- (void)showReport:(NSButton *)b { (void)b; _detailsFor = -1; [self fillDetails]; }

// Select All / Deselect All: flip every plain cheat (kind 0) that is not already in the wanted state, then one refresh.
// The loop over dm_cheat_toggle instead of a bulk call keeps the C API small; each toggle rewrites <build ID>.enabled once
// (a few tiny writes), and a pass between two toggles sees a mix for one frame, which is harmless. Masters, disabled
// cheats, labels and "set" cheats (Select All must not fire them) are never touched, nor the off half of a pair
// (hle_cheats.c switches it with its on half)
- (void)setPlainCheatsOn:(BOOL)on {
    for (int i = 0, n = dm_cheats_ncheats(); i < n; i++) {
        if (dm_cheat_kind_at(i) != 0 || (dm_cheat_flags_at(i) & (DM_CHEAT_PAIR_OFF | DM_CHEAT_ONCE))) continue;
        if (!!dm_cheat_on_at(i) == on) continue;
        dm_cheat_toggle(i);
    }
    [self refresh];
}
// The two buttons behind setPlainCheatsOn:
- (void)selectAllCheats:(NSButton *)b   { (void)b; [self setPlainCheatsOn:YES]; }
- (void)deselectAllCheats:(NSButton *)b { (void)b; [self setPlainCheatsOn:NO]; }

// A checkbox click (or an Apply button: a "set" cheat runs one pass and turns itself off): flip the cheat (hle_cheats.c
// also rewrites <build ID>.enabled), then refresh — the state comes back from the model
- (void)cheatClicked:(NSButton *)b {
    int i = (int)b.tag;
    BOOL apply = i >= 0 && i < dm_cheats_ncheats() && (dm_cheat_flags_at(i) & DM_CHEAT_ONCE);
    if (apply && dm_cheat_on_at(i)) return;   // Apply only applies: one already waiting for its pass is not cancelled
    if (i >= 0 && i < dm_cheats_ncheats()) dm_cheat_toggle(i);
    if (_detailsFor == i) [self fillDetails];
    [self refresh];
}

// ⓘ: show the cheat's details below the rows (its dry run now, its note)
- (void)infoClicked:(NSButton *)b { _detailsFor = (int)b.tag; [self fillDetails]; }

// A field's edit ended. A value field (still the row's own: a rebuild ends edits without applying them) sets its value;
// a refused one beeps and shows the current value again. The keyboard goes back to the game only for Return (or the
// search field's Escape), not when the player moved on to another field of the panel (Tab, a click)
- (void)controlTextDidEndEditing:(NSNotification *)n {
    NSTextField *f = n.object;
    NSInteger how = [n.userInfo[@"NSTextMovement"] integerValue];
    BOOL done = how == NSTextMovementReturn || how == NSTextMovementCancel;
    if (f != (id)_search && !_rebuilding && _values[@(f.tag)] == f) {
        int i = (int)f.tag;
        if (dm_cheat_value_set(i, f.stringValue.UTF8String)) {
            NSBeep();
            char v[64]; if (dm_cheat_value_get(i, v, sizeof v)) f.stringValue = @(v);
        }
        if (_detailsFor == i) [self fillDetails];
    }
    if (done) [self giveKeyBack];
}

// The search text changed: the rows are filtered again (the signature includes it, so refresh rebuilds)
- (void)controlTextDidChange:(NSNotification *)n { if (n.object == _search) [self refresh]; }

// Escape: in a value field it abandons the typed text (the current value comes back, nothing is applied); in the search
// field it clears the search as usual. Either way the keyboard goes back to the game (Return ends editing,
// controlTextDidEndEditing)
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    (void)tv;
    if (sel != @selector(cancelOperation:)) return NO;
    if (c == (id)_search) { dispatch_async(dispatch_get_main_queue(), ^{ [self giveKeyBack]; }); return NO; }
    NSTextField *f = (NSTextField *)c;
    [f abortEditing];
    char v[64]; if (dm_cheat_value_get((int)f.tag, v, sizeof v)) f.stringValue = @(v);
    [self giveKeyBack];
    return YES;
}

// ---- Find Cheats… and the import ----

// The cheat files of this game the usual places hold, this build's own first:
//   - Ryujinx: mods/contents/<title ID>/cheats/ and its mods' own cheats folders (mods/contents/<title ID>/<mod>/cheats/);
//   - the yuzu family: load/<title ID>/<mod>/cheats/;
//   - the Atmosphère tree of a mounted local volume (an SD card); network volumes are not listed (a stall even off the main thread).
// Only the .txt files named after a build ID count (not Ryujinx's enabled.txt); each folder is read once whatever case
// the path came in. build: this build's ID (read from the engine on the main thread by the caller). Runs on a background
// queue (findCheats:): it touches only the file system and Foundation, never AppKit or the cheats engine
static NSArray<NSURL *> *found_cheat_files(NSString *build) {
    NSString *tid = [NSString stringWithFormat:@"%016llX", (unsigned long long)DM_GAME_PROGRAM_ID];
    NSString *as = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *t in @[tid.lowercaseString, tid]) {
        NSString *mods = [as stringByAppendingFormat:@"/Ryujinx/mods/contents/%@", t];
        [dirs addObject:[mods stringByAppendingString:@"/cheats"]];
        for (NSString *m in [fm contentsOfDirectoryAtPath:mods error:nil] ?: @[]) [dirs addObject:[mods stringByAppendingFormat:@"/%@/cheats", m]];
    }
    for (NSString *emu in @[@"yuzu", @"citron", @"eden", @"sudachi", @"suyu"]) {
        NSString *load = [as stringByAppendingFormat:@"/%@/load/%@", emu, tid];
        for (NSString *m in [fm contentsOfDirectoryAtPath:load error:nil] ?: @[]) [dirs addObject:[load stringByAppendingFormat:@"/%@/cheats", m]];
    }
    for (NSURL *vol in [fm mountedVolumeURLsIncludingResourceValuesForKeys:@[NSURLVolumeIsLocalKey] options:NSVolumeEnumerationSkipHiddenVolumes] ?: @[]) {
        NSNumber *local = nil; [vol getResourceValue:&local forKey:NSURLVolumeIsLocalKey error:nil];
        NSString *root = vol.path;   // nil for a volume without a file-system path: nothing to look in
        if (local.boolValue && root) [dirs addObject:[root stringByAppendingFormat:@"/atmosphere/contents/%@/cheats", tid]];
    }
    NSMutableArray<NSURL *> *mine = [NSMutableArray array], *rest = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSCharacterSet *nothex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"].invertedSet;
    for (NSString *d in dirs) {
        NSString *real = [d stringByResolvingSymlinksInPath].lowercaseString;   // one folder however its path was spelled
        if ([seen containsObject:real]) continue;
        [seen addObject:real];
        for (NSString *f in [fm contentsOfDirectoryAtPath:d error:nil] ?: @[]) {
            if (f.length != 20 || ![f.lowercaseString hasSuffix:@".txt"] || [[f substringToIndex:16] rangeOfCharacterFromSet:nothex].location != NSNotFound) continue;
            NSURL *u = [NSURL fileURLWithPath:[d stringByAppendingPathComponent:f]];
            [([f.uppercaseString hasPrefix:build] ? mine : rest) addObject:u];
        }
    }
    [mine addObjectsFromArray:rest];
    return mine;
}

// Find Cheats…: a menu of the files found, under the button; picking one imports it. The folders are read on a background
// queue, since a sleeping external disk can take seconds to answer and the main thread would beachball the game window
// meanwhile; the button reads "Looking…" and is disabled until the scan ends, and _finding keeps a second click (or an
// action sent while disabled) from starting another scan. The menu is built and shown on the main queue, and only while
// the panel is still on screen (it hides when the app is deactivated): a menu popping up out of nowhere would be worse
- (void)findCheats:(NSButton *)b {
    if (_finding) return;
    _finding = YES;
    NSString *title = b.title;
    b.title = @"Looking…"; b.enabled = NO;
    NSString *build = engine_str(dm_cheats_build());   // the engine's state is read here, on the main thread, not by the scan
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSURL *> *found = found_cheat_files(build);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_finding = NO;
            b.title = title; b.enabled = YES;
            if (b.window.visible) [self showFound:found under:b];
        });
    });
}
// The files a Find Cheats… scan found, as a menu under its button (main thread)
- (void)showFound:(NSArray<NSURL *> *)found under:(NSButton *)b {
    NSMenu *m = [NSMenu new];
    if (!found.count) [m addItemWithTitle:@"No cheat files of this game in Ryujinx, the yuzu family or an SD card" action:nil keyEquivalent:@""].enabled = NO;
    for (NSURL *u in found) {
        NSString *parent = u.URLByDeletingLastPathComponent.path.stringByAbbreviatingWithTildeInPath;
        NSMenuItem *it = [m addItemWithTitle:[NSString stringWithFormat:@"%@ — %@", u.lastPathComponent, parent] action:@selector(importFound:) keyEquivalent:@""];
        it.target = self; it.representedObject = u;
    }
    [m popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, b.bounds.size.height) inView:b];
}
// A file picked in Find Cheats…: import it
- (void)importFound:(NSMenuItem *)it { if (it.representedObject) [self importFiles:@[it.representedObject]]; }

// A yes / no question as a modal alert, answered before returning (the import is the player's own action, so a modal
// question is fine; the keyboard goes back to the game after it): YES for the first button
- (BOOL)ask:(NSString *)text info:(NSString *)info yes:(NSString *)yes {
    NSAlert *a = [NSAlert new];
    a.messageText = text; a.informativeText = info ?: @"";
    [a addButtonWithTitle:yes]; [a addButtonWithTitle:@"Cancel"];
    BOOL r = [a runModal] == NSAlertFirstButtonReturn;
    [self giveKeyBack];
    return r;
}

// Copy cheat files into the cheats folder, then reload: a .cheats.toml (an anchored source) keeps its name; a .txt keeps a
// build ID name, and a file named otherwise (a Ryujinx list such as "all cheats.txt") becomes this build's after the
// player confirms it is for this build. A file already there is kept as <name>.bak (asked first). Returns whether
// something was imported
- (BOOL)importFiles:(NSArray<NSURL *> *)urls {
    const char *dirc = dm_cheats_dir_path();
    if (!dirc || !*dirc || strlen(dm_cheats_build()) != 16) { NSBeep(); return NO; }   // no folder, or no build ID to name a file by
    NSString *dir = engine_str(dirc), *build = engine_str(dm_cheats_build());
    NSString *tid = [NSString stringWithFormat:@"%016llX", (unsigned long long)DM_GAME_PROGRAM_ID];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL any = NO;
    for (NSURL *u in urls) {
        NSString *name = u.lastPathComponent, *dest;
        if ([name.lowercaseString hasSuffix:@".cheats.toml"]) dest = name;
        else if (![name.lowercaseString hasSuffix:@".txt"]) continue;
        else {
            NSString *stem = name.length >= 16 ? [name substringToIndex:16].uppercaseString : @"";
            BOOL hex = stem.length == 16 && [stem rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"].invertedSet].location == NSNotFound;
            if (hex && ![stem isEqualToString:tid]) dest = [stem stringByAppendingString:@".txt"];   // a title ID name says no build
            else {
                if (![self ask:[NSString stringWithFormat:@"Is “%@” for this version of the game?", name]
                          info:[NSString stringWithFormat:@"Its name does not say which build it is for. It will be used as the cheats of %@.", build_label(dm_cheats_build(), dm_cheats_version())]
                           yes:@"Use for This Build"]) continue;
                dest = [build stringByAppendingString:@".txt"];
            }
        }
        NSString *path = [dir stringByAppendingPathComponent:dest];
        if ([u.path.stringByStandardizingPath.lowercaseString isEqualToString:path.stringByStandardizingPath.lowercaseString]) continue;   // already the folder's own file
        if ([fm fileExistsAtPath:path]) {
            if (![self ask:[NSString stringWithFormat:@"Replace %@?", dest] info:[NSString stringWithFormat:@"The current one is kept as %@.bak (an older %@.bak is replaced).", dest, dest] yes:@"Replace"]) continue;
            NSString *bak = [path stringByAppendingString:@".bak"];
            [fm removeItemAtPath:bak error:nil];
            [fm moveItemAtPath:path toPath:bak error:nil];
        }
        NSError *e = nil;
        if ([fm copyItemAtURL:u toURL:[NSURL fileURLWithPath:path] error:&e]) any = YES;
        else LOG("[RED] cheats: cannot copy %s into the cheats folder: %s", u.path.UTF8String, e.localizedDescription.UTF8String);
    }
    if (any) { dm_cheats_reload(); _detailsFor = -1; [self refresh]; [self fillDetails]; }
    return any;
}

// ---- the rows ----

// A row of one cheat: its checkbox (or, for a "set" cheat, its name and an Apply button), its value field for an "ask"
// cheat, and ⓘ. The title truncates and is whole in the tooltip, so a long one never widens the panel
- (NSView *)cheatRow:(int)i {
    int kind = dm_cheat_kind_at(i), f = dm_cheat_flags_at(i);
    NSString *title = cheat_row_title(i), *tip = cheat_row_tip(i);
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    NSButton *b;
    if (f & DM_CHEAT_ONCE) {
        NSTextField *l = [NSTextField labelWithString:title];
        l.lineBreakMode = NSLineBreakByTruncatingTail; l.toolTip = tip;
        _labels[@(i)] = l;
        [l setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [views addObject:l];
        b = panel_button(@"Apply", self, @selector(cheatClicked:));
        b.controlSize = NSControlSizeSmall;
    } else {
        b = [NSButton checkboxWithTitle:title target:self action:@selector(cheatClicked:)];
        ((NSButtonCell *)b.cell).lineBreakMode = NSLineBreakByTruncatingTail;
        [b setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        b.state = cheat_row_state(i);
    }
    b.tag = i; b.enabled = kind == 0; b.toolTip = tip;
    _checks[@(i)] = b;
    if (!(f & DM_CHEAT_ONCE)) [views addObject:b];
    if (f & DM_CHEAT_ASK) {
        NSTextField *v = [NSTextField textFieldWithString:@""];
        char cur[64]; if (dm_cheat_value_get(i, cur, sizeof cur)) v.stringValue = @(cur);
        v.placeholderString = @(dm_cheat_value_bounds(i));
        v.toolTip = [NSString stringWithFormat:@"Value (%s, %s)", dm_cheat_type_at(i), dm_cheat_value_bounds(i)];
        v.tag = i; v.delegate = self; v.controlSize = NSControlSizeSmall;
        [v.widthAnchor constraintEqualToConstant:90].active = YES;
        _values[@(i)] = v;
        [views addObject:v];
    }
    if (f & DM_CHEAT_ONCE) [views addObject:b];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:@"Details"];   // nil only if the symbol is gone
    NSButton *info = icon ? [NSButton buttonWithImage:icon target:self action:@selector(infoClicked:)] : [NSButton buttonWithTitle:@"i" target:self action:@selector(infoClicked:)];
    info.bordered = NO; info.tag = i; info.toolTip = @"Show what it writes now, and its note";
    [views addObject:info];
    return panel_hrow(views);
}

// A section header: the section's name in bold
- (NSView *)sectionRow:(const char *)name {
    NSTextField *l = [NSTextField labelWithString:engine_str(name)];
    l.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    return l;
}

// Does entry i pass the search text (its name or its section contains it, any case)?
- (BOOL)matches:(int)i {
    NSString *q = _search.stringValue;
    if (!q.length) return YES;
    return [cheat_display_name(i) rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound
        || [engine_str(dm_cheat_section_at(i)) rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// What the rows on screen were built from: the signature rebuilt on every refresh, the rows rebuilt when it differs (the
// list, the flags that choose a row's controls, the search text). States and titles are not in it: they change per cheat
// and the update path carries them in place
- (NSString *)rowsSig {
    NSMutableString *s = [NSMutableString stringWithFormat:@"%d/%d/%@/", dm_cheats_ncheats(), dm_cheats_found(), _search.stringValue];
    for (int i = 0, n = dm_cheats_ncheats(); i < n; i++) [s appendFormat:@"%@:%d|", engine_str(dm_cheat_name_at(i)), dm_cheat_flags_at(i)];
    for (int i = 0, n = dm_cheats_nothers(); i < n; i++) [s appendFormat:@"%@:%@|", engine_str(dm_cheats_other(i)), engine_str(dm_cheats_other_version(i))];
    for (int i = 0, n = dm_cheats_nskipped(); i < n; i++) [s appendFormat:@"%@|", engine_str(dm_cheats_skipped_name(i))];
    for (int i = 0, n = dm_cheats_nsources(); i < n; i++) [s appendFormat:@"%@|", engine_str(dm_cheats_source(i))];
    return s;
}

// Rebuild all rows (a reload, a first fill, a new search), keeping the scroll position as far as possible
- (void)rebuildRows {
    NSClipView *clip = _scroll.contentView;
    CGFloat keepY = clip.bounds.origin.y;
    _rebuilding = YES;   // an edit in progress ends now without being applied (its row may be another cheat after a reload)
    for (NSTextField *v in _values.allValues) if (v.currentEditor) [v abortEditing];
    for (NSView *v in [_stack.arrangedSubviews copy]) [v removeFromSuperview];
    _rebuilding = NO;
    [_checks removeAllObjects]; [_values removeAllObjects]; [_labels removeAllObjects];
    const char *sec = "";
    for (int i = 0, n = dm_cheats_ncheats(); i < n; i++) {
        if (!cheat_has_row(i) || ![self matches:i]) continue;
        const char *s = dm_cheat_section_at(i);
        if (strcmp(s, sec)) { sec = s; if (*s) [_stack addArrangedSubview:[self sectionRow:s]]; }
        if (dm_cheat_kind_at(i) == 3) [_stack addArrangedSubview:panel_note(cheat_display_name(i))];   // a label: credits and the like
        else [_stack addArrangedSubview:[self cheatRow:i]];
    }
    for (int i = 0, n = dm_cheats_nskipped(); i < n; i++)
        [_stack addArrangedSubview:panel_note([NSString stringWithFormat:@"Left out of this build: %@ — %@", engine_str(dm_cheats_skipped_name(i)), engine_str(dm_cheats_skipped_why(i))])];
    for (int i = 0, n = dm_cheats_nothers(); i < n; i++)
        [_stack addArrangedSubview:panel_note([NSString stringWithFormat:@"Cheats for %@: another version of the game, its addresses do not fit this one",
                                                build_label(dm_cheats_other(i), dm_cheats_other_version(i))])];
    if (!dm_cheats_found())
        for (int i = 0, n = dm_cheats_nsources(); i < n; i++) {
            NSButton *copy = panel_button(@"Copy Command", self, @selector(copyCompile:)); copy.tag = i; copy.controlSize = NSControlSizeSmall;
            [_stack addArrangedSubview:panel_hrow(@[panel_note([NSString stringWithFormat:@"%@: anchored cheats, not compiled for this build yet", engine_str(dm_cheats_source(i))]), copy])];
        }
    _rows_sig = [self rowsSig];
    if (keepY <= 0) return;   // at the top already: the new rows start at the top too
    __weak DmCheatsPanel *wself = self;   // one main-queue tick later: the panel may be hidden by then
    dispatch_async(dispatch_get_main_queue(), ^{
        DmCheatsPanel *s = wself;
        if (!s || !s->_panel || !s->_panel.isVisible) return;
        NSClipView *c = s->_scroll.contentView;
        CGFloat max = fmax(0, s->_doc.frame.size.height - c.bounds.size.height);
        [c setBoundsOrigin:NSMakePoint(0, fmin(keepY, max))];
    });
}

// Copy Command: the command that compiles an anchored source for this build (scripts/cheat_anchor.py, run from the
// nxnative repository's folder; the build's ExeFS/main is the one the NSP script extracted), paths quoted for the shell
- (void)copyCompile:(NSButton *)b {
    NSString *dir = engine_str(dm_cheats_dir_path());
    NSString *cmd = [NSString stringWithFormat:@"python3 scripts/cheat_anchor.py compile %@ --nso '<the ExeFS/main of build %@>' -o %@",
                     shell_quote([dir stringByAppendingPathComponent:engine_str(dm_cheats_source((int)b.tag))]), engine_str(dm_cheats_build()), shell_quote(dir)];
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:cmd forType:NSPasteboardTypeString];
    _detailsFor = -2;   // the timer leaves this text alone
    _details.stringValue = [@"Copied (run it in the nxnative folder): " stringByAppendingString:cmd];
}

// Update the rows in place (a click, a timer tick, a menu toggle): each control's state, enabled flag and title; a value
// field the player is editing is left alone
- (void)updateRows {
    [_checks enumerateKeysAndObjectsUsingBlock:^(NSNumber *k, NSButton *b, BOOL *stop) {
        (void)stop; int i = k.intValue;
        BOOL once = (dm_cheat_flags_at(i) & DM_CHEAT_ONCE) != 0;
        b.enabled = dm_cheat_kind_at(i) == 0 && (!once || (dm_cheats_master() && !dm_cheat_on_at(i)));   // Apply: not while one waits
        if (once) {
            NSTextField *l = self->_labels[k];
            NSString *full = cheat_row_title(i);
            if (l && ![l.stringValue isEqualToString:full]) { l.stringValue = full; l.toolTip = cheat_row_tip(i); }
        } else {
            b.state = cheat_row_state(i);
            NSString *full = cheat_row_title(i);
            if (![b.title isEqualToString:full]) { b.title = full; b.toolTip = cheat_row_tip(i); }
        }
    }];
    [_values enumerateKeysAndObjectsUsingBlock:^(NSNumber *k, NSTextField *v, BOOL *stop) {
        (void)stop;
        if (v.currentEditor) return;
        char cur[64]; if (dm_cheat_value_get(k.intValue, cur, sizeof cur) && ![v.stringValue isEqualToString:@(cur)]) v.stringValue = @(cur);
    }];
}

// The details line: the shown cheat's dry run and note, or the load report
- (void)fillDetails {
    if (_detailsFor == -1) { _details.stringValue = engine_str(dm_cheats_report()); return; }
    if (_detailsFor < 0 || _detailsFor >= dm_cheats_ncheats()) { _details.stringValue = @""; return; }
    char pv[1024]; dm_cheat_preview(_detailsFor, pv, sizeof pv);
    NSMutableString *t = [NSMutableString stringWithFormat:@"%@\n%@", cheat_display_name(_detailsFor), engine_str(pv)];
    const char *note = dm_cheat_note_at(_detailsFor);
    if (note && *note) [t appendString:engine_str(note)];
    _details.stringValue = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// The Select All / Deselect All buttons' enable state: Select All while some switchable plain cheat is off, Deselect All
// while one is on (the same cheats setPlainCheatsOn: flips); both off while Cheats On is off
- (void)updateSelectButtons {
    BOOL someOff = NO, someOn = NO;
    for (int i = 0, n = dm_cheats_ncheats(); i < n; i++) {
        if (dm_cheat_kind_at(i) != 0 || (dm_cheat_flags_at(i) & (DM_CHEAT_PAIR_OFF | DM_CHEAT_ONCE))) continue;
        if (dm_cheat_on_at(i)) someOn = YES; else someOff = YES;
        if (someOn && someOff) break;
    }
    _selectAll.enabled = someOff && dm_cheats_master();
    _deselectAll.enabled = someOn && dm_cheats_master();
}

// The header's one line (the folder missing, the counts and the build's version, or no file of this build) and the
// master switch and safe-mode controls
- (void)fillHeader {
    const char *dir = dm_cheats_dir_path();
    int n = 0, on = 0, masters = 0;   // switchable cheats and those on; master codes are counted apart (always on)
    for (int i = 0, c = dm_cheats_ncheats(); i < c; i++) {
        int kind = dm_cheat_kind_at(i);
        if (!cheat_has_row(i) || kind == 3) continue;
        if (kind == 1) { masters++; continue; }
        n++; on += kind == 0 && dm_cheat_on_at(i);
    }
    NSString *build = build_label(dm_cheats_build(), dm_cheats_version());
    if (!dir || !*dir) _header.stringValue = @"Cheats are off: no cheats folder (DM_CHEATS or DM_ROOT is not set)";
    else if (dm_cheats_found()) _header.stringValue = [NSString stringWithFormat:@"%@: %d cheats, %d on%@", build, n, on,
                                                        masters ? [NSString stringWithFormat:@", %d master", masters] : @""];
    else _header.stringValue = [NSString stringWithFormat:@"No cheats for %@", build];
    _header.toolTip = engine_str(dm_cheats_report());
    _master.state = dm_cheats_master() ? NSControlStateValueOn : NSControlStateValueOff;
    _safeRow.hidden = !dm_cheats_safe();
}

// The one refresh: the header and the buttons always, the rows rebuilt when what they show changed, only updated when it
// did not. Nothing happens while the panel is not on screen — it fills itself in show
- (void)refresh {
    if (!_panel || !_panel.isVisible) return;
    [self fillHeader];
    [self updateSelectButtons];
    _openFolder.enabled = ({ const char *d = dm_cheats_dir_path(); d && *d; });
    if (![_rows_sig isEqualToString:[self rowsSig]]) [self rebuildRows];
    else [self updateRows];
}

// Arm the ~1 s refresh unless it is already running: called by show and by the app's return to the foreground
- (void)startTimer {
    if (_refreshTimer.isValid) return;
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

// One timer tick: refresh the rows (and the details of a shown cheat, whose dry run changes with the game), and stop for a
// panel that is no longer on screen
- (void)tick {
    if (!_panel.isVisible) { [_refreshTimer invalidate]; _refreshTimer = nil; return; }
    [self refresh];
    if (_detailsFor >= 0) [self fillDetails];
}

// The app was deactivated: the utility panel goes off screen with it, so the refresh timer stops until the app comes back
- (void)appResignedActive:(NSNotification *)n {
    (void)n;
    _upOnDeactivate = _panel.isVisible;
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

// The app is active again: AppKit brings back a panel that was up, so the timer is armed a main-queue turn later
- (void)appBecameActive:(NSNotification *)n {
    (void)n;
    dispatch_async(dispatch_get_main_queue(), ^{ if (_upOnDeactivate) [self startTimer]; });
}

// Shown: order the panel front (created first if needed) — orderFront, not makeKeyAndOrderFront, so the game window stays
// key. While the panel is on screen a ~1 s timer refreshes it
- (void)show {
    if (!_panel) [self makePanel];
    [_panel orderFront:self];
    [self refresh];
    [self startTimer];
}

// The close button: hide instead of close (the panel object and its autosaved frame stay), and stop the refresh timer
- (BOOL)windowShouldClose:(NSWindow *)w {
    if (w != _panel) return YES;
    [_refreshTimer invalidate];
    _refreshTimer = nil;
    for (NSTextField *v in _values.allValues) if (v.currentEditor) [v abortEditing];   // an unfinished value is abandoned
    [self giveKeyBack];   // while the panel is still key
    [_panel orderOut:nil];
    return NO;
}
@end

void front_run(void (*guest)(void)) {
    // Keep the latency-critical activity token alive for the host process, including windowless play.
    static id<NSObject> game_activity;
    if (!game_activity)
        game_activity = [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityUserInitiated | NSActivityLatencyCritical reason:@"game"];
    if (!getenv("DM_WINDOW")) {
        kern_return_t kr;
        int role_status = front_windowless_role(getenv("DM_WINDOWLESS_ROLE"), &kr);
        if (role_status > 0) LOG("front end: applied the default application task role for windowless play");
        else if (role_status < 0) LOG("front end: could not apply the default application task role (Mach error %d)", kr);
        else LOG("front end: kept the existing task role (DM_WINDOWLESS_ROLE=0)");
        guest();
        return;
    }
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSRect r = NSMakeRect(0, 0, 1280, 720);
        NSWindow *win = [[NSWindow alloc] initWithContentRect:r
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered defer:NO];
        win.title = @(DM_GAME_NAME);   // the game profile's name (game name label)
        // Fullscreen: without FullScreenPrimary the green button only zooms the window. The present path already scales
        // the game picture to fit the drawable with black bars around it, so fullscreen keeps the game's aspect ratio.
        win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        NSView *v = win.contentView = [[DmGameView alloc] initWithFrame:r];
        v.wantsLayer = YES;
        g_layer = [CAMetalLayer layer];
        g_layer.device = MTLCreateSystemDefaultDevice();
        g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        g_layer.contentsScale = win.backingScaleFactor;
        // Apple's HUD over the game: hud_env turns it on before the first device, hud_apply (the overlay's HUD card) sets its look through developerHUDProperties
        if (hud_forced()) LOG("front end: Metal performance HUD on (DM_METAL_HUD)");
        NSView *picture = [[DmPictureView alloc] initWithFrame:v.bounds];
        picture.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        picture.layer = g_layer; picture.wantsLayer = YES;
        [v addSubview:picture]; [(DmGameView *)v fitDrawable];
        [win center];
        [win makeKeyAndOrderFront:nil];
        screen_refresh(win.screen ?: NSScreen.mainScreen);
        g_win = win;
        [NSApp activateIgnoringOtherApps:YES];
        // A host another process starts (scripts/regress.py) is not activated (its focus state stays 2), so its window opened wherever it landed in the window order, and behind
        // another app's window macOS fires its display link about once a second: Breath of the Wild stepped up to 3 vsyncs at boot and never came back (20 fps runs).
        // DM_WINDOW_TOP=1 orders it in front without activation and keeps it above other apps' windows; the log names every change of the window's visibility either way
        if (getenv("DM_WINDOW_TOP") && atoi(getenv("DM_WINDOW_TOP"))) { win.level = NSFloatingWindowLevel; [win orderFrontRegardless]; LOG("front end: window kept in front (DM_WINDOW_TOP)"); }
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidChangeOcclusionStateNotification object:win queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            (void)n; static int vis = -1; int v = (win.occlusionState & NSWindowOcclusionStateVisible) != 0; if (v == vis) return; vis = v;
            if (v) LOG("front end: window visible"); else LOG("front end: window covered (its display link fires about once a second: frame times measure nothing)"); }];
        // Main menu: AppKit runs ⌘ shortcuts only through menu items, so ⌘Q quits and ⌃⌘F toggles fullscreen from here (AppKit shows the item as Globe-F and keeps ⌃⌘F as a hidden twin)
        NSMenu *bar = [NSMenu new], *app = [NSMenu new], *wm = [[NSMenu alloc] initWithTitle:@"Window"];
        [[bar addItemWithTitle:@"" action:nil keyEquivalent:@""] setSubmenu:app];
        [app addItemWithTitle:[@"Quit " stringByAppendingString:@(DM_GAME_NAME)] action:@selector(terminate:) keyEquivalent:@"q"];
        // Cheats (hle_cheats.c): the rows rebuild on every open through the delegate, the same rows the file reload changes
        g_cheats_menu = [DmCheatsMenuDelegate new];
        NSMenu *cm = [[NSMenu alloc] initWithTitle:@"Cheats"];
        cm.delegate = g_cheats_menu;
        cm.autoenablesItems = NO;   // the delegate sets enabled on every row itself
        // Fill the rows now: AppKit matches a key equivalent (⌘R, ⌘⇧C) only against items that exist, and it calls the
        // delegate's menuNeedsUpdate: when the menu is opened, not at launch, so without this neither works until the
        // Cheats menu has been opened once. Every open rebuilds them through the delegate as before
        [g_cheats_menu menuNeedsUpdate:cm];
        [[bar addItemWithTitle:@"Cheats" action:nil keyEquivalent:@""] setSubmenu:cm];
        if (getenv("DM_CHEATS_WINDOW") && atoi(getenv("DM_CHEATS_WINDOW")))   // the Cheats panel open from the start (beside the game, not key)
            dispatch_async(dispatch_get_main_queue(), ^{ [g_cheats_menu showPanel:nil]; });
        [[bar addItemWithTitle:@"Window" action:nil keyEquivalent:@""] setSubmenu:wm];
        [wm addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"].keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;
        NSApp.mainMenu = bar;
        static DmWinDelegate *wd; wd = [DmWinDelegate new]; win.delegate = wd;   // handle failed transitions even after entering fullscreen manually
        const char *fs = getenv("DM_FULLSCREEN");   // 1 (or any value but 0): start in fullscreen; 0, the settings window's Window, or unset: a window
        NSUserDefaults *overlayStore=[[NSUserDefaults alloc] initWithSuiteName:@"org.nxnative.overlay"];
        if (ov_fullscreen_load(overlayStore,[@"game-" stringByAppendingString:@(DM_GAME_ID)],fs)) {
            // A game opened from a fullscreen app starts while macOS leaves that Space. Wait for activation and for the window to reach the active Space before asking for fullscreen
            // (whichever happens last), and repeat a refused startup request once. Only a request made here owns a retry; a later player request must never restart startup handling
            __block int want = 1, retried = 0, entering = 0;
            void (^enter)(void) = ^{
                if (!want || g_bg || (win.styleMask & NSWindowStyleMaskFullScreen) || !NSApp.isActive || !win.isOnActiveSpace) return;
                want = 0; entering = 1; [win toggleFullScreen:nil]; };
            g_fs_failed = ^{
                if (!entering) return;
                entering = 0;
                LOG("front end: fullscreen was refused (app active %d, window on the active Space %d)%s", NSApp.isActive, win.isOnActiveSpace, retried ? "" : ", asking once more");
                if (retried) return;
                retried = 1; want = 1; dispatch_async(dispatch_get_main_queue(), enter); };
            [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n) { (void)n; enter(); }];
            [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) { (void)n; enter(); }];
            for (NSNotificationName nm in @[NSWindowWillEnterFullScreenNotification, NSWindowWillExitFullScreenNotification])
                [NSNotificationCenter.defaultCenter addObserverForName:nm object:win queue:nil usingBlock:^(NSNotification *n) {
                    (void)n; want = 0;
                    if (!entering) g_fs_failed = nil; }];   // the player took over while startup was waiting; our own transition has entering set
            [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidEnterFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) {
                (void)n; want = 0; entering = 0; g_fs_failed = nil; }];   // startup succeeded: later manual refusals have no startup request to retry
            dispatch_async(dispatch_get_main_queue(), enter);
        }
        for (NSNotificationName nm in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:nm object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                GCController *c = n.object; int conn = n.name == GCControllerDidConnectNotification;
                if (!c.extendedGamepad || g_merge) LOG("controller %s: %s%s", conn ? "connected" : "disconnected", pad_name(c), c.extendedGamepad ? "" : " (no extended gamepad profile: not used)");
                if (conn) hidpad_gc_connected(c);   // a HID pad of its name that only waited for it (pad_hid_mac.h)
                pads_changed(conn ? nil : c);
            }];
        dm_haptics_apple_init();
        pads_start();
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp handler:^NSEvent *(NSEvent *e) {
            if (e.window != win) return e;   // Only swallow keys for the game window; other windows such as the software keyboard input box receive typing as usual
            if (e.type == NSEventTypeKeyDown && (e.modifierFlags & NSEventModifierFlagCommand)) return e;   // ⌘ shortcuts go to the menu; a key released while ⌘ is held still reaches the game, or it would stay pressed
            if (e.type == NSEventTypeKeyDown && fn_shortcut(e)) return e;   // fn (Globe) + a letter is the system's (fn+F full screen, GitHub issue #873), not the game's F
            if (hq_visible(g_hq.phase) && ((e.modifierFlags & (NSEventModifierFlagControl|NSEventModifierFlagOption)) == (NSEventModifierFlagControl|NSEventModifierFlagOption))) {
                if (e.type == NSEventTypeKeyUp) [g_ov_keys_down removeIndex:e.keyCode];
                return e;   // VoiceOver takes the event, but a tracked key still needs its release
            }
            if (!e.isARepeat) on_key(e, e.type == NSEventTypeKeyDown);
            return nil;   // Swallow it to avoid the system beep
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:win queue:nil
                                                      usingBlock:^(NSNotification *n) { (void)n; exit(0); }];
        // Lifecycle (hle.h / dm.h): focus lost → 2, focus regained → 1; minimized → 3 + audio paused + GPU suspended, restored → resume (followed by focus regained → 1).
        // Input is released when the window stops being key (and when it is minimized) and taken up again when it is key again
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:NSWindowDidChangeScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; screen_refresh(win.screen); if (win.screen) g_layer.contentsScale = win.backingScaleFactor; screen_match_apply(); }];
        [nc addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil queue:nil usingBlock:^(NSNotification *n) { (void)n; screen_refresh(win.screen); }];
        // Entering and leaving fullscreen: the layer is layer-backed, so its frame (and with it the drawable) follows the
        // content view by itself; only the scale factor has to be carried over to the screen the window ended up on. The screen's rate is matched in fullscreen only (screen_match_apply)
        [nc addObserverForName:NSWindowDidEnterFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) {
            (void)n; screen_refresh(win.screen); g_fullscreen = 1; g_layer.contentsScale = win.backingScaleFactor; screen_match_apply();
            g_bg_fs_transition = 0; hq_display_finished(YES);
            if (g_bg == BG_HIDING) dispatch_async(dispatch_get_main_queue(), ^{ bg_exit_fullscreen(); });
        }];
        [nc addObserverForName:NSWindowDidExitFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) {
            (void)n; g_fullscreen = 0; screen_refresh(win.screen); g_layer.contentsScale = win.backingScaleFactor; screen_match_apply();
            g_bg_fs_transition = 0; hq_display_finished(YES); bg_hide();
            if (!g_bg && g_bg_fullscreen) dispatch_async(dispatch_get_main_queue(), ^{ bg_restore_fullscreen(); });   // an exit that finished after the timeout
        }];
        // DM_FOCUS_KEEP=1 (scripts/regress.py): the game stays in focus while its window is up, whichever app is active. Tears of the Kingdom stops presenting out of focus, so
        // another app taking the key window during an unattended run read as a hang (no frame after the last focus change)
        static int keep = -1; if (keep < 0) keep = getenv("DM_FOCUS_KEEP") && atoi(getenv("DM_FOCUS_KEEP"));
        [nc addObserverForName:NSWindowDidResignKeyNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; if (g_bg) return; input_release(); if (!win.miniaturized && !g_text_box && !keep) dm_focus_set(2); }];
        [nc addObserverForName:NSWindowDidBecomeKeyNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; if (g_bg) return; input_resume(); dm_focus_set(1); hq_tick(); }];
        [nc addObserverForName:NSWindowDidMiniaturizeNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; if (!g_bg) game_suspend(); }];
        [nc addObserverForName:NSWindowDidDeminiaturizeNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; if (!g_bg) game_restore(); }];
        bg_start();
        display_awake(win.isKeyWindow);   // the window may have become key (makeKeyAndOrderFront above) before these observers were installed
        // Guest thread: 64 MiB stack (the Switch main thread stack is specified by npdm; the host gives plenty)
        static guest_arg ga; ga.fn = guest;
        pthread_attr_t a; pthread_attr_init(&a); pthread_attr_setstacksize(&a, 64u << 20);
        pthread_t th; if (pthread_create(&th, &a, guest_tramp, &ga)) die("pthread_create guest");
        [NSApp run];
    }
}

// Progress screen of the prepare step (front.h front_progress): a dark view over the game's, the title, a bar and a count, centered; AppKit views, so it draws while the game's thread waits
static NSView *g_prog; static NSTextField *g_prog_title, *g_prog_count; static NSProgressIndicator *g_prog_bar;
static NSTextField *prog_label(NSRect r, CGFloat size, NSFontWeight w, NSColor *c) {
    NSTextField *t = [NSTextField labelWithString:@""]; t.frame = r; t.alignment = NSTextAlignmentCenter; t.textColor = c;
    t.font = [NSFont monospacedDigitSystemFontOfSize:size weight:w]; return t;
}
void (*front_progress_hook)(const char *title, long done, long total);
void front_progress(const char *title, long done, long total) {
    if (!g_layer) return;
    NSString *tt = title ? @(title) : nil;
    void (*hook)(const char *, long, long) = front_progress_hook;
    if (hook) { dispatch_async(dispatch_get_main_queue(), ^{ hook(tt.UTF8String, done, total); }); return; }   // the host app draws it (front.h)
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!tt) { [g_prog removeFromSuperview]; g_prog = nil; return; }
        if (!g_prog) {
            NSView *cv = g_win.contentView;
            g_prog = [[NSView alloc] initWithFrame:cv.bounds]; g_prog.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            g_prog.wantsLayer = YES; g_prog.layer.backgroundColor = [NSColor colorWithWhite:0.06 alpha:0.94].CGColor;
            NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(floor((cv.bounds.size.width - 400) / 2), floor((cv.bounds.size.height - 96) / 2), 400, 96)];
            box.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
            g_prog_title = prog_label(NSMakeRect(0, 62, 400, 30), 20, NSFontWeightSemibold, NSColor.whiteColor);
            g_prog_bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 36, 360, 20)];
            g_prog_bar.style = NSProgressIndicatorStyleBar; g_prog_bar.indeterminate = NO; g_prog_bar.minValue = 0;
            g_prog_count = prog_label(NSMakeRect(0, 4, 400, 22), 13, NSFontWeightRegular, [NSColor colorWithWhite:0.72 alpha:1]);
            [box addSubview:g_prog_title]; [box addSubview:g_prog_bar]; [box addSubview:g_prog_count]; [g_prog addSubview:box];
            [cv addSubview:g_prog];
        }
        g_prog_title.stringValue = tt; g_prog_bar.maxValue = total > 0 ? (double)total : 1; g_prog_bar.doubleValue = (double)done;
        g_prog_count.stringValue = [NSString stringWithFormat:@"%@ of %@", [NSNumberFormatter localizedStringFromNumber:@(done) numberStyle:NSNumberFormatterDecimalStyle],
                                    [NSNumberFormatter localizedStringFromNumber:@(total) numberStyle:NSNumberFormatterDecimalStyle]];
    });
}

// Offline HTML pages (web_apple.m): the page's view covers the game view and resizes with it; it is the first responder while shown (front_web_show), and the game view again after
void front_web_attach(NSView *box) { NSView *v = g_win.contentView; box.frame = v.bounds; [v addSubview:box]; }
void front_web_detach(NSView *box) { if (box.window && box.window.firstResponder != box.window.contentView) [box.window makeFirstResponder:box.window.contentView]; }

// Software keyboard input box (front.h): the main thread shows an NSAlert + text field and the guest thread waits synchronously for the result. Not shown in windowless mode (returns -1, the caller treats it as cancel)
extern int g_swkbd_min_chars;   // hle_swkbd.c: this input's minimum length from ShowKeyboardArg; the applet keeps OK disabled until the text is long enough
int front_user_select(const front_user *users, int count, int allow_create, int allow_skip) {
    if (!g_layer) return FRONT_USER_CANCEL;
    __block int result = FRONT_USER_CANCEL;
    dispatch_sync(dispatch_get_main_queue(), ^{
        g_text_box = 1; input_release();
        result = user_select_mac(users, count, allow_create, allow_skip);
        g_text_box = 0;
        if (g_win.isKeyWindow) input_resume();
    });
    return result;
}
int front_text_input(const char *title, const char *sub, const char *guide, const char *initial, int max_chars, char *out, int out_cap) {
    if (!g_layer) return -1;
    __block int r = 0;
    __block NSString *text = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        // The box takes the keyboard and the mouse, so the game window never sees the key-up of the button or the touch-up of the click that opened it: nothing may stay pressed
        // while it is up, or the game reads the stuck button / touch the moment the box closes (Stardew Valley's character creation re-opened the keyboard endlessly)
        g_btn = 0; g_w = g_a = g_s = g_d = 0; g_rl = g_ru = g_rr = g_rd = 0; push();
        dm_touch_set(NULL, 0);
        int min_chars = g_swkbd_min_chars > 0 ? g_swkbd_min_chars : 0;
        NSString *info = [NSString stringWithFormat:@"%s%s%s", sub ? sub : "", sub && *sub && guide && *guide ? "\n" : "", guide ? guide : ""];
        for (;;) {
            NSAlert *a = [NSAlert new];
            a.messageText = title && *title ? @(title) : @"Input";
            a.informativeText = info;
            [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
            NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
            f.stringValue = text ?: (initial ? @(initial) : @"");
            if (guide && *guide) f.placeholderString = @(guide);
            a.accessoryView = f; a.window.initialFirstResponder = f;
            g_text_box = 1; r = [a runModal] == NSAlertFirstButtonReturn; g_text_box = 0;
            text = f.stringValue;
            if (!r || (int)text.length >= min_chars) break;
            // On hardware the applet would not have accepted the shorter text (OK stayed disabled); a game that rejects it re-opens the keyboard for ever, so the box comes back with the rule instead
            info = [info stringByAppendingFormat:@"\nAt least %d characters are needed here.", min_chars];
        }
    });
    if (!r) return 0;
    (void)max_chars;                              // Truncation is done uniformly in hle_swkbd.c in UTF-16 units
    snprintf(out, out_cap, "%s", text.UTF8String);
    return 1;
}

// GPU lost (front.h): macOS runs none of the game's GPU work any more and nothing is drawn again. In full screen the frozen game held the whole screen (#1326: WindowServer froze for 40 s
// and its watchdog killed it), so the window leaves full screen first and the alert comes once it has, or after 3 s if it has not. Then the app quits with exit status 70
// (EX_SOFTWARE), so a launcher or script that runs it sees a failed run: exit() runs the same atexit handlers as ⌘Q's terminate (the one will-terminate
// observer, haptics_apple.m's, is an atexit handler too), whose exit status is 0
void front_gpu_lost(void) {
    if (!g_layer) die("GPU access revoked: macOS runs none of this process's GPU work any more");
    LOG("front end: the GPU no longer runs the game's work; telling the player and quitting");
    dispatch_async(dispatch_get_main_queue(), ^{
        __block int told = 0;
        void (^tell)(void) = ^{
            if (told++) return;
            NSAlert *a = [NSAlert new];
            a.alertStyle = NSAlertStyleCritical;
            a.messageText = [@"The GPU stopped running " stringByAppendingString:@(DM_GAME_NAME)];   // @(): the name is UTF-8, which %s would not read as such
            a.informativeText = [NSString stringWithFormat:@"After a GPU error, macOS stopped running the game's GPU work, so nothing more can be drawn and the game quits. The log has the details. "
                                                           "Please report it on GitHub with python3 scripts/bug_report.py %@, which collects the log.", @(DM_GAME_ID)];
            [a addButtonWithTitle:@"Quit"];
            // An app opened in the background would leave the alert behind other apps' windows, and DM_WINDOW_TOP's floating game window would cover it
            [NSApp activateIgnoringOtherApps:YES];
            [a layout]; NSWindow *game = g_win; if (game && a.window.level <= game.level) a.window.level = game.level + 1;
            [a runModal];
            exit(70);
        };
        NSWindow *win = g_win;
        if (!(win.styleMask & NSWindowStyleMaskFullScreen)) { tell(); return; }
        [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidExitFullScreenNotification object:win queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { (void)n; tell(); }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), tell);
        [win toggleFullScreen:nil];
    });
}
