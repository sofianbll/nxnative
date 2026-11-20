// The Home button's hold and quit prompt (home_quit.h): the hold time, letting go early, A and B in the prompt, a button already held when it opens, Home closing it,
// the settle phase that keeps the closing B from the game, losing the focus, the hold indicator, the switch, a front end's texts and the setting's log word
#include "../home_quit.h"
#include <stdio.h>

static int checks, fails;
#define CHECK(c, msg) do { checks++; if (!(c)) { fails++; fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); } } while (0)

int main(void) {
    home_quit q = {0};
    CHECK(hq_step(&q, 0, 0, 0, 0) == HQ_IDLE, "nothing pressed: idle");
    CHECK(hq_step(&q, 1.0, 1, 0, 0) == HQ_HOLDING, "Home pressed: the hold starts");
    CHECK(hq_ring(&q, 1.1) == -1, "a short press shows no indicator");
    CHECK(hq_ring(&q, 1.0 + HQ_RING_S + (HQ_HOLD_S - HQ_RING_S) / 2) > 0.49 && hq_ring(&q, 1.0 + HQ_RING_S + (HQ_HOLD_S - HQ_RING_S) / 2) < 0.51, "half way the ring is half full");
    CHECK(hq_step(&q, 2.9, 1, 0, 0) == HQ_HOLDING, "1.9 s: still holding");
    CHECK(!hq_blocks_input(q.phase), "the game keeps its input while Home is held");
    CHECK(hq_step(&q, 3.0, 1, 0, 0) == HQ_PROMPT, "2 s: the prompt opens");
    CHECK(hq_ring(&q, 3.0) == -1, "the indicator goes when the prompt opens");
    CHECK(hq_blocks_input(q.phase), "the prompt takes the controllers");
    CHECK(hq_step(&q, 3.5, 0, 0, 0) == HQ_PROMPT, "letting go of Home keeps the prompt open");
    CHECK(hq_step(&q, 4.0, 0, 1, 0) == HQ_QUIT, "A quits");
    CHECK(hq_step(&q, 4.1, 0, 0, 0) == HQ_QUIT, "quit is final");
    hq_cancel(&q);
    CHECK(q.phase == HQ_QUIT, "a focus loss after quit changes nothing");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0);
    CHECK(hq_step(&q, 1.0, 0, 0, 0) == HQ_IDLE, "let go before 2 s: nothing happens");
    CHECK(hq_step(&q, 5.0, 0, 0, 0) == HQ_IDLE, "and nothing later either");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 2.0, 1, 0, 0);
    CHECK(hq_step(&q, 2.5, 1, 0, 1) == HQ_SETTLE, "B closes the prompt");
    CHECK(hq_blocks_input(q.phase), "the B that closed it does not reach the game");
    CHECK(hq_step(&q, 2.6, 1, 0, 0) == HQ_SETTLE, "Home still down: still settling");
    CHECK(hq_step(&q, 2.7, 0, 0, 0) == HQ_IDLE, "all up: the game has the controllers again");
    CHECK(hq_step(&q, 2.8, 1, 0, 0) == HQ_HOLDING, "a new press starts a new hold");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 1, 1);
    CHECK(hq_step(&q, 2.0, 1, 1, 1) == HQ_PROMPT, "A and B held through the hold: the prompt opens");
    CHECK(hq_step(&q, 2.1, 1, 1, 1) == HQ_PROMPT, "an A or B already held when it opens does not count");
    CHECK(hq_step(&q, 2.2, 1, 0, 1) == HQ_PROMPT, "A released, B still held");
    CHECK(hq_step(&q, 2.3, 1, 1, 1) == HQ_QUIT, "A pressed again quits");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 2.0, 1, 0, 0);
    CHECK(hq_step(&q, 2.1, 1, 0, 0) == HQ_PROMPT, "Home still held from the hold does not close it");
    hq_step(&q, 2.2, 0, 0, 0);
    CHECK(hq_step(&q, 2.3, 1, 0, 0) == HQ_SETTLE, "a new press of Home closes it");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 2.0, 1, 0, 0);
    CHECK(hq_step(&q, 2.1, 0, 1, 1) == HQ_SETTLE, "A and B at once: the safe one wins");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 2.0, 1, 0, 0);
    hq_cancel(&q);
    CHECK(q.phase == HQ_IDLE && !hq_blocks_input(q.phase), "a focus loss closes the prompt");
    CHECK(hq_step(&q, 3.0, 1, 0, 0) == HQ_IDLE, "a Home held through the focus change needs a new press");
    hq_step(&q, 3.1, 0, 0, 0);
    CHECK(hq_step(&q, 3.2, 1, 0, 0) == HQ_HOLDING, "then a press holds again");

    CHECK(hq_enabled(NULL) && hq_enabled("1") && hq_enabled(""), "on by default");
    CHECK(!hq_enabled("0"), "DM_HOME_QUIT=0: off");

    CHECK(!hq_menu_enabled(NULL, NULL) && !hq_menu_enabled("0", NULL), "no launcher opt-in: no Home menu");
    CHECK(!hq_menu_enabled("1", "0") && hq_menu_enabled("1", NULL), "launcher opt-in respects DM_HOME_MENU=0");
    q = (home_quit){.menu = hq_menu_enabled(NULL, NULL)};
    hq_step(&q, 0, 1, 0, 0);
    CHECK(hq_step(&q, 0.2, 0, 0, 0) == HQ_IDLE && !hq_blocks_input(q.phase), "short Home is unchanged without a launcher");
    q = (home_quit){.menu = 1};
    hq_step(&q, 0, 1, 0, 0);
    CHECK(hq_step(&q, 0.2, 0, 0, 0) == HQ_MENU && q.sel == HQ_ROW_RESUME && hq_blocks_input(q.phase), "short Home opens the menu on Resume");
    CHECK(hq_step(&q, 0.3, 0, 0, 1) == HQ_SETTLE, "B dismisses the menu to the game");
    hq_step(&q, 0.4, 0, 0, 0);
    hq_step(&q, 1, 1, 0, 0);
    CHECK(hq_step(&q, 2, 0, 0, 0) == HQ_IDLE, "a medium press is neither a tap nor a hold");
    hq_step(&q, 3, 1, 0, 0);
    CHECK(hq_step(&q, 5, 1, 0, 0) == HQ_PROMPT, "a 2 s hold goes straight to the old quit prompt with the menu enabled");

    q = (home_quit){.menu = 1, .no_hold = 1};
    hq_step(&q, 0, 1, 0, 0);
    CHECK(hq_step(&q, 2.1, 1, 0, 0) == HQ_HOLDING && hq_ring(&q, 2.1) < 0, "DM_HOME_QUIT=0 suppresses the hold and ring");
    hq_step(&q, 2.2, 0, 0, 0);
    hq_step(&q, 3, 1, 0, 0);
    CHECK(hq_step(&q, 3.2, 0, 1, 0) == HQ_MENU, "DM_HOME_QUIT=0 does not turn off an opted-in short tap");
    CHECK(hq_step(&q, 3.3, 0, 1, 0) == HQ_MENU, "A held at open cannot select Resume");
    hq_step_nav(&q, 3.4, 0, 0, 0, 0, 1);
    hq_step_nav(&q, 3.5, 0, 0, 0, 0, 1);
    CHECK(q.sel == HQ_ROW_CONSOLE, "holding down moves to Back to console only once");
    hq_step(&q, 3.6, 0, 0, 0);
    hq_step_nav(&q, 3.7, 0, 0, 0, 0, 1);
    CHECK(q.sel == HQ_ROW_QUIT, "a second down moves to Quit");
    CHECK(hq_step(&q, 3.8, 0, 1, 0) == HQ_PROMPT && hq_step(&q, 3.9, 0, 1, 0) == HQ_PROMPT, "Quit still requires a second A in the prompt");
    hq_step(&q, 4.0, 0, 0, 0);
    CHECK(hq_step(&q, 4.1, 0, 1, 0) == HQ_QUIT, "quit via the menu confirms as before");

    q = (home_quit){.menu = 1};
    hq_step(&q, 0, 1, 0, 0);
    hq_step(&q, 0.2, 0, 0, 0);
    hq_step_nav(&q, 0.3, 0, 0, 0, 0, 1);
    CHECK(hq_step(&q, 0.4, 0, 1, 0) == HQ_PAUSED && hq_blocks_input(q.phase), "Back to console pauses and holds input");
    hq_cancel(&q);
    CHECK(q.phase == HQ_PAUSED, "losing focus while hiding the app keeps it paused");
    hq_resumed(&q);
    CHECK(hq_step(&q, 0.5, 0, 1, 0) == HQ_SETTLE && hq_step(&q, 0.6, 0, 0, 0) == HQ_IDLE, "resume waits for A to be released before returning input");

    char out[64];
    hq_text_line("Hold\nQuit Zelda?\nLost\nQuit\nCancel", HQ_TEXT_TITLE, "d", out, sizeof out);
    CHECK(!strcmp(out, "Quit Zelda?"), "a line of the text");
    hq_text_line("Hold\nQuit Zelda?\nLost\nQuit\nCancel", HQ_TEXT_CANCEL, "d", out, sizeof out);
    CHECK(!strcmp(out, "Cancel"), "the last line");
    hq_text_line("Hold\n\nLost", HQ_TEXT_TITLE, "Quit Mario?", out, sizeof out);
    CHECK(!strcmp(out, "Quit Mario?"), "an empty line takes the default");
    hq_text_line("Hold", HQ_TEXT_QUIT, "Quit", out, sizeof out);
    CHECK(!strcmp(out, "Quit"), "a missing line takes the default");
    hq_text_line("Hold\nTitle\nNote\nQuit\nCancel\nResume\nConsole\nGame", HQ_TEXT_CONSOLE, "d", out, sizeof out);
    CHECK(!strcmp(out, "Console"), "line seven localizes Back to console without shifting the original quit lines");
    hq_text_line(NULL, HQ_TEXT_HOLD, "Keep holding to quit", out, sizeof out);
    CHECK(!strcmp(out, "Keep holding to quit"), "no text: the defaults");
    char small[4]; hq_text_line("Abcdef", 0, "d", small, sizeof small);
    CHECK(!strcmp(small, "Abc"), "a long line is cut to the buffer");

    CHECK(!strcmp(hq_in_app_name(0), "system") && !strcmp(hq_in_app_name(1), "app") && !strcmp(hq_in_app_name(-1), "unavailable"), "the setting's words");
    CHECK(!strcmp(hq_in_app_name(0x7fffffffffffffffL), "off"), "disabled is off");

    printf("t_home_quit: %d checks, %d failed\n", checks, fails);
    return fails != 0;
}
