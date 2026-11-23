// Mac overlay input, independent of AppKit and controller APIs. Home menu
// originally adapted from NX2Apple patch 0035 (MIT, Copyright 2026 LNPANDY and contributors).
#pragma once
#include "dm_input.h"
#include <stdio.h>
#include <string.h>

#define HQ_HOLD_S 0.5
#define HQ_STICK 0.5

typedef enum { HQ_IDLE, HQ_HOLDING, HQ_QUICK, HQ_FULL, HQ_SETTLE, HQ_QUIT, HQ_PAUSED, HQ_DISPLAYING } hq_phase;
enum { HQ_HOME = 1, HQ_PLUS = 2, HQ_A = 4, HQ_B = 8, HQ_Y = 16,
       HQ_LEFT = 32, HQ_RIGHT = 64, HQ_UP = 128, HQ_DOWN = 256, HQ_L = 512, HQ_R = 1024, HQ_OTHER = 2048,
       HQ_ZL = 4096, HQ_ZR = 8192 };
// Leave a small neutral zone for drift; navigation still takes a deliberate tilt of the left stick.
static inline unsigned hq_stick_bits(const int32_t s[4]) {
    const int32_t neutral = DM_STICK_MAX / 20;
    unsigned bits = (s[0] < -DM_STICK_MAX*HQ_STICK ? HQ_LEFT : 0) | (s[0] > DM_STICK_MAX*HQ_STICK ? HQ_RIGHT : 0) |
        (s[1] > DM_STICK_MAX*HQ_STICK ? HQ_UP : 0) | (s[1] < -DM_STICK_MAX*HQ_STICK ? HQ_DOWN : 0);
    for (int i = 0; i < 4; i++) if (s[i] < -neutral || s[i] > neutral) return bits | HQ_OTHER;
    return bits;
}
enum { HQ_HUD, HQ_VOLUME, HQ_PADS, HQ_NETWORK, HQ_DISPLAY, HQ_POWER, HQ_HOME_SETTING = HQ_POWER };
typedef struct {
    hq_phase phase;
    double since;
    unsigned buttons, trigger;
    int disabled, no_hold, menu_hold, swap;
    int selection, card, row, tab, confirm, advanced;
} home_quit;

static inline int hq_enabled(const char *env) { return !(env && !strcmp(env, "0")); }
static inline int hq_captures_menu(const home_quit *q) { return q->menu_hold && !q->disabled && !q->no_hold; }
static inline int hq_menu_enabled(const char *launcher, const char *menu) { return launcher && !strcmp(launcher, "1") && hq_enabled(menu); }
static inline int hq_visible(hq_phase p) { return p == HQ_QUICK || p == HQ_FULL; }
static inline int hq_blocks_input(hq_phase p) { return p != HQ_IDLE && p != HQ_HOLDING; }
static inline hq_phase hq_short(const home_quit *q) { return q->swap ? HQ_QUICK : HQ_FULL; }
static inline hq_phase hq_long(const home_quit *q) { return q->swap ? HQ_FULL : HQ_QUICK; }
static inline int hq_shoulders(unsigned nav) { return !!(nav & HQ_R) - !!(nav & HQ_L); }
static inline int hq_neighbor(int current, int step, int count) { return (current + step + count) % count; }
static inline void hq_hud_page(home_quit *q, int advanced) { q->advanced = advanced; q->row = 0; }
static inline void hq_quick_neighbor(home_quit *q, int step) {
    q->selection = hq_neighbor(q->selection,step,HQ_POWER + !q->no_hold);
    if (q->card >= 0) q->card = q->selection < HQ_DISPLAY ? q->selection : -1;
    hq_hud_page(q,0);
}
static inline int hq_slider_repeat(double now, double *since, double *next, unsigned *held, unsigned directions) {
    if (!directions || directions != *held) {
        *held=directions; *since=now; *next=now+.30;
        return 0;
    }
    if (now < *next) return 0;
    *next=now+.07;
    return now-*since>=1.0 ? 4 : 1;
}
static inline void hq_display_done(home_quit *q) { if (q->phase == HQ_DISPLAYING) q->phase = HQ_SETTLE; }
static inline void hq_open(home_quit *q, hq_phase phase) {
    q->phase = phase; q->selection = q->row = q->tab = q->confirm = q->advanced = 0; q->card = -1;
}
static inline void hq_back(home_quit *q) {
    if (q->confirm) { q->confirm = 0; q->row = 0; }
    else if (q->card == HQ_HUD && q->advanced) hq_hud_page(q,0);
    else if (q->card >= 0) { q->card = -1; q->row = 0; }
    else if (q->tab) { q->tab = 0; q->selection = 0; }
    else q->phase = HQ_SETTLE;
}
static inline void hq_key_open(home_quit *q, hq_phase phase) {
    if (!q->disabled && q->phase != HQ_PAUSED && q->phase != HQ_QUIT && q->phase != HQ_SETTLE && q->phase != HQ_DISPLAYING && q->phase != phase)
        hq_open(q, phase);
}

// Returns new navigation presses only when the overlay was already open.
// With Menu hold enabled, the host sends short Menu taps to the guest on release.
static inline unsigned hq_step(home_quit *q, double now, unsigned buttons, int *menu_tap) {
    unsigned down = buttons & ~q->buttons; q->buttons = buttons; *menu_tap = 0;
    if (q->disabled) return 0;
    switch (q->phase) {
    case HQ_IDLE: {
        unsigned trigger = down & HQ_HOME ? HQ_HOME : down & HQ_PLUS && hq_captures_menu(q) ? HQ_PLUS : 0;
        if (trigger) { q->since = now; q->trigger = trigger; q->phase = HQ_HOLDING; }
        break;
    }
    case HQ_HOLDING:
        if (!q->no_hold && now >= q->since + HQ_HOLD_S) hq_open(q, hq_long(q));
        else if (!(buttons & q->trigger)) {
            if (q->trigger == HQ_HOME && now < q->since + HQ_HOLD_S) hq_open(q, hq_short(q));
            else { *menu_tap = q->trigger == HQ_PLUS; q->phase = HQ_IDLE; }
        }
        break;
    case HQ_QUICK: case HQ_FULL:
        if (down & HQ_HOME) q->phase = HQ_SETTLE;
        else if (down & HQ_B) hq_back(q);
        else if ((down & HQ_Y) && q->phase == HQ_QUICK && !q->confirm) hq_open(q, HQ_FULL);
        else return down & ~(HQ_HOME | HQ_PLUS | HQ_B);
        break;
    case HQ_SETTLE:
        if (!buttons) q->phase = HQ_IDLE;
        break;
    case HQ_PAUSED: case HQ_QUIT: case HQ_DISPLAYING:
        break;
    }
    return 0;
}
static inline void hq_cancel(home_quit *q) {
    if (q->phase != HQ_QUIT && q->phase != HQ_PAUSED && q->phase != HQ_DISPLAYING) {
        q->phase = hq_blocks_input(q->phase) ? HQ_SETTLE : HQ_IDLE;
        q->buttons = HQ_HOME | HQ_PLUS;
    }
}
static inline void hq_resumed(home_quit *q) { if (q->phase == HQ_PAUSED) q->phase = HQ_SETTLE; }
static inline double hq_ring(const home_quit *q, double now) {
    return q->phase == HQ_HOLDING && !q->no_hold ? (now - q->since) / HQ_HOLD_S : -1;
}

// Existing launcher text lines retain their numbering.
enum { HQ_TEXT_HOLD, HQ_TEXT_TITLE, HQ_TEXT_NOTE, HQ_TEXT_QUIT, HQ_TEXT_CANCEL, HQ_TEXT_RESUME, HQ_TEXT_CONSOLE, HQ_TEXT_MENU_TITLE, HQ_TEXTS };
static inline void hq_text_line(const char *text, int i, const char *def, char *out, size_t cap) {
    const char *s = text;
    for (int k = 0; s && k < i; k++) { s = strchr(s, '\n'); if (s) s++; }
    size_t n = 0;
    if (s) { const char *e = strchr(s, '\n'); n = e ? (size_t)(e - s) : strlen(s); }
    if (!n) { snprintf(out, cap, "%s", def); return; }
    if (n >= cap) n = cap - 1;
    memcpy(out, s, n); out[n] = 0;
}
static inline const char *hq_in_app_name(long v) {
    return v == 0 ? "system" : v == 1 ? "app" : v == -1 ? "unavailable" : v > 1 ? "off" : "unavailable";
}
