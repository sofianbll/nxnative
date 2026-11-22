#include "../home_quit.h"
#include <assert.h>

int main(void) {
    home_quit q = {0};
    int tap;
    assert(!hq_step(&q, 1, HQ_HOME, &tap) && q.phase == HQ_HOLDING);
    assert(hq_ring(&q, 1.25) == .5);
    hq_step(&q, 1.49, 0, &tap);
    assert(q.phase == HQ_FULL && q.selection == 0 && q.card == -1);
    hq_step(&q, 2, HQ_HOME, &tap);
    assert(q.phase == HQ_SETTLE);
    hq_step(&q, 2.1, HQ_A, &tap);
    assert(q.phase == HQ_SETTLE);
    hq_step(&q, 2.2, 0, &tap);
    assert(q.phase == HQ_IDLE);
    hq_step(&q, 3, HQ_HOME | HQ_A, &tap);
    hq_step(&q, 3.5, HQ_HOME | HQ_A, &tap);
    assert(q.phase == HQ_QUICK);
    assert(!hq_step(&q, 3.6, HQ_A, &tap) && q.phase == HQ_QUICK);
    hq_step(&q, 3.7, 0, &tap);
    assert(hq_step(&q, 3.8, HQ_A, &tap) == HQ_A);
    hq_step(&q, 3.9, HQ_Y, &tap);
    assert(q.phase == HQ_FULL);
    q.confirm = 1;
    assert(!hq_step(&q, 4, HQ_A | HQ_B, &tap) && !q.confirm && q.phase == HQ_FULL);
    hq_step(&q, 4.1, 0, &tap);
    q.card = HQ_HUD;
    hq_step(&q, 4.2, HQ_B, &tap);
    assert(q.card == -1 && q.phase == HQ_FULL);
    hq_cancel(&q);
    assert(q.phase == HQ_SETTLE);
    hq_step(&q, 5, 0, &tap);
    hq_step(&q, 5.1, HQ_PLUS, &tap);
    hq_step(&q, 5.5, 0, &tap);
    assert(tap && q.phase == HQ_IDLE);
    hq_step(&q, 6, HQ_PLUS, &tap);
    hq_step(&q, 6.5, 0, &tap);
    assert(!tap && q.phase == HQ_QUICK);   // release at threshold before timer delivered
    hq_key_open(&q, HQ_FULL);
    assert(q.phase == HQ_FULL);
    q.selection = 1;
    hq_key_open(&q, HQ_FULL);
    assert(q.selection == 1);   // repeated shortcut does not reopen
    hq_key_open(&q, HQ_QUICK);
    assert(q.phase == HQ_QUICK && q.selection == 0);
    q = (home_quit){.no_hold = 1};
    hq_step(&q, 7, HQ_PLUS, &tap);
    assert(q.phase == HQ_IDLE);
    hq_step(&q, 7.1, HQ_HOME, &tap);
    hq_step(&q, 7.6, 0, &tap);
    assert(q.phase == HQ_IDLE && hq_ring(&q, 7.6) == -1);
    hq_step(&q, 8, HQ_HOME, &tap);
    hq_step(&q, 8.2, 0, &tap);
    assert(q.phase == HQ_FULL);
    q = (home_quit){.disabled = 1};
    hq_key_open(&q, HQ_QUICK);
    hq_step(&q, 9, HQ_HOME | HQ_PLUS, &tap);
    assert(q.phase == HQ_IDLE);
    assert(hq_menu_enabled("1", NULL) && !hq_menu_enabled("1", "0") && !hq_menu_enabled(NULL, NULL));
    char line[16];
    hq_text_line("First\n\nThird", 1, "fallback", line, sizeof line);
    assert(!strcmp(line,"fallback"));
    hq_text_line("First\n\nThird", 2, "fallback", line, 3);
    assert(!strcmp(line,"Th"));
    puts("Home, Menu, keyboard shortcuts, navigation and catch-up: OK");
}
