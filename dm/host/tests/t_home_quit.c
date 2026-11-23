#include "../home_quit.h"
#include <assert.h>

int main(void) {
    home_quit q = {0};
    int tap;
    for (int axis = 0; axis < 4; axis++) {
        int32_t s[4] = {0};
        s[axis] = axis & 1 ? -DM_STICK_MAX : DM_STICK_MAX;
        assert(hq_stick_bits(s) == (axis == 0 ? HQ_RIGHT | HQ_OTHER : axis == 1 ? HQ_DOWN | HQ_OTHER : HQ_OTHER));
        hq_open(&q, HQ_FULL);
        hq_step(&q, 0, HQ_B | hq_stick_bits(s), &tap);
        assert(q.phase == HQ_SETTLE);
        s[axis] /= 4;   // B released, stick below the navigation threshold but not centered
        hq_step(&q, .1, hq_stick_bits(s), &tap);
        assert(q.phase == HQ_SETTLE);
        s[axis] = DM_STICK_MAX / 20;
        hq_step(&q, .2, hq_stick_bits(s), &tap);
        assert(q.phase == HQ_IDLE);
    }
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
    assert(!hq_captures_menu(&q));   // pass Menu through to the game by default
    hq_step(&q, 5.1, HQ_PLUS, &tap);
    hq_step(&q, 5.7, HQ_PLUS, &tap);
    assert(q.phase == HQ_IDLE && !tap && hq_ring(&q, 5.7) == -1);
    hq_step(&q, 5.8, 0, &tap);
    assert(q.phase == HQ_IDLE && !tap);
    q.menu_hold = 1;
    assert(hq_captures_menu(&q));
    hq_step(&q, 5.9, HQ_PLUS, &tap);
    hq_step(&q, 6, 0, &tap);
    assert(tap && q.phase == HQ_IDLE);
    hq_step(&q, 6.1, HQ_PLUS, &tap);
    hq_step(&q, 6.7, 0, &tap);
    assert(!tap && q.phase == HQ_QUICK);   // release at threshold before timer delivered
    hq_key_open(&q, HQ_FULL);
    assert(q.phase == HQ_FULL);
    q.selection = 1;
    hq_key_open(&q, HQ_FULL);
    assert(q.selection == 1);   // repeated shortcut does not reopen
    hq_key_open(&q, HQ_QUICK);
    assert(q.phase == HQ_QUICK && q.selection == 0);
    q = (home_quit){.no_hold = 1, .menu_hold = 1};
    assert(!hq_captures_menu(&q));
    hq_step(&q, 7, HQ_PLUS, &tap);
    assert(q.phase == HQ_IDLE);
    hq_step(&q, 7.1, HQ_HOME, &tap);
    hq_step(&q, 7.6, 0, &tap);
    assert(q.phase == HQ_IDLE && hq_ring(&q, 7.6) == -1);
    hq_step(&q, 8, HQ_HOME, &tap);
    hq_step(&q, 8.2, 0, &tap);
    assert(q.phase == HQ_FULL);
    q = (home_quit){.disabled = 1, .menu_hold = 1};
    assert(!hq_captures_menu(&q));
    hq_key_open(&q, HQ_QUICK);
    hq_step(&q, 9, HQ_HOME | HQ_PLUS, &tap);
    assert(q.phase == HQ_IDLE);
    assert(hq_menu_enabled("1", NULL) && !hq_menu_enabled("1", "0") && !hq_menu_enabled(NULL, NULL));
    q=(home_quit){.swap=1};
    assert(hq_short(&q)==HQ_QUICK && hq_long(&q)==HQ_FULL);
    hq_step(&q,10,HQ_HOME,&tap); hq_step(&q,10.1,0,&tap); assert(q.phase==HQ_QUICK);
    q.phase=HQ_IDLE; hq_step(&q,11,HQ_HOME,&tap); hq_step(&q,11.6,HQ_HOME,&tap); assert(q.phase==HQ_FULL);
    q.phase=HQ_IDLE; q.menu_hold=1; hq_step(&q,12,0,&tap); hq_step(&q,12.1,HQ_PLUS,&tap); hq_step(&q,12.7,HQ_PLUS,&tap); assert(q.phase==HQ_FULL && !tap);
    hq_key_open(&q,hq_short(&q)); assert(q.phase==HQ_QUICK);
    hq_key_open(&q,hq_long(&q)); assert(q.phase==HQ_FULL);
    q.phase=HQ_DISPLAYING; hq_cancel(&q);
    hq_key_open(&q,HQ_FULL); assert(!hq_step(&q,13,HQ_A,&tap) && q.phase==HQ_DISPLAYING && hq_blocks_input(q.phase));
    hq_display_done(&q); assert(q.phase==HQ_SETTLE);
    hq_step(&q,14,HQ_A,&tap); assert(q.phase==HQ_SETTLE); hq_step(&q,15,0,&tap); assert(q.phase==HQ_IDLE);
    hq_open(&q,HQ_QUICK); q.card=HQ_HUD;
    assert(hq_step(&q,16,HQ_R,&tap)==HQ_R);
    hq_hud_page(&q,1); assert(q.advanced && q.row==0); hq_back(&q); assert(!q.advanced && q.card==HQ_HUD);
    hq_quick_neighbor(&q,hq_shoulders(HQ_R)); assert(q.card==HQ_VOLUME && q.selection==HQ_VOLUME);
    hq_quick_neighbor(&q,hq_shoulders(HQ_L)); assert(q.card==HQ_HUD && q.selection==HQ_HUD);
    hq_quick_neighbor(&q,-1); assert(q.card==-1 && q.selection==HQ_POWER);
    assert(hq_neighbor(0,hq_shoulders(HQ_L),5)==4 && hq_neighbor(4,hq_shoulders(HQ_R),5)==0);
    double since=0,next=0; unsigned held=0;
    assert(hq_slider_repeat(1,&since,&next,&held,HQ_RIGHT)==0);
    assert(hq_slider_repeat(1.2,&since,&next,&held,HQ_RIGHT)==0);
    assert(hq_slider_repeat(1.4,&since,&next,&held,HQ_RIGHT)==1);
    assert(hq_slider_repeat(2.1,&since,&next,&held,HQ_RIGHT)==4);
    char line[16];
    hq_text_line("First\n\nThird", 1, "fallback", line, sizeof line);
    assert(!strcmp(line,"fallback"));
    hq_text_line("First\n\nThird", 2, "fallback", line, 3);
    assert(!strcmp(line,"Th"));
    puts("Home, Menu, keyboard shortcuts, navigation and catch-up: OK");
}
