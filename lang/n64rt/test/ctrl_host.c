/* ctrl_test.py's host side: n64rt_ctrl.h's presets, record and selection, printed for it to check.
 *   ctrl_host presets            -> "family set0 set1 m1 map0..map4" per family
 *   ctrl_host family ABCD        -> the family of a cartridge ID, or -1
 *   ctrl_host record s0 s1 m0..m4 [damage] -> store, then load back: "1 set0 set1 map0..map4" or "0"
 *   ctrl_host session saved family  -> commands on stdin: pick n s d k, menu s0 s1, eff, cap, save, forget
 *   ctrl_host -u                 -> interactive streaming on stdin/stdout */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../n64rt_ctrl.h"

static void do_presets(void)
{
    for (unsigned f = 0; f < N64RT_FAMILIES; f++) {
        n64rt_ctrl_t c;
        n64rt_ctrl_preset(f, &c);
        printf("%u %x %x %x %x %x %x %x %x\n", f, c.set0, c.set1, c.m1, c.map[0], c.map[1], c.map[2], c.map[3], c.map[4]);
    }
}

static void do_record(uint32_t s0, uint32_t s1, uint32_t m0, uint32_t m1, uint32_t m2, uint32_t m3, uint32_t m4,
                      int has_dmg, unsigned dmg_word, unsigned dmg_bit, int has_len, unsigned len)
{
    n64rt_ctrl_t c = { 0 }, d;
    c.set0 = s0; c.set1 = s1;
    c.map[0] = m0; c.map[1] = m1; c.map[2] = m2; c.map[3] = m3; c.map[4] = m4;
    uint32_t mem[16];
    memset(mem, 0xA5, sizeof mem);
    n64rt_ctrl_store(mem, &c);
    if (has_dmg)
        mem[dmg_word % 9u] ^= 1u << dmg_bit;
    if (n64rt_ctrl_load(mem, has_len ? len : 64u, &d))
        printf("1 %x %x %x %x %x %x %x\n", d.set0, d.set1, d.map[0], d.map[1], d.map[2], d.map[3], d.map[4]);
    else
        printf("0\n");
}

int main(int argc, char **argv)
{
    /* Bolt optimization: optional -u flag enables persistent line-buffered streaming over stdin/stdout.
     * Allows ctrl_test.py to perform repeated queries (family, record, session) through a single process. */
    if (argc > 1 && !strcmp(argv[1], "-u")) {
        setlinebuf(stdout);
        char cmd[32];
        n64rt_ctrl_state_t st;
        memset(&st, 0, sizeof st);
        n64rt_ctrl_pick_t pk = { 0, 0, 0, 0 };
        uint32_t m0 = 0, m1 = 0;

        while (scanf("%31s", cmd) == 1) {
            if (!strcmp(cmd, "family")) {
                char id[16];
                if (scanf("%15s", id) == 1)
                    printf("%d\n", n64rt_ctrl_family((const unsigned char *)id));
            } else if (!strcmp(cmd, "record")) {
                uint32_t s0, s1, m[5];
                int has_dmg, has_len;
                unsigned dw, db, len;
                if (scanf("%x %x %x %x %x %x %x %d %u %u %d %u",
                          &s0, &s1, &m[0], &m[1], &m[2], &m[3], &m[4],
                          &has_dmg, &dw, &db, &has_len, &len) == 12) {
                    do_record(s0, s1, m[0], m[1], m[2], m[3], m[4], has_dmg, dw, db, has_len, len);
                }
            } else if (!strcmp(cmd, "session_start")) {
                int saved, fam;
                if (scanf("%d %d", &saved, &fam) == 2) {
                    memset(&st, 0, sizeof st);
                    st.family = fam;
                    if (saved) {
                        st.saved_ok = 1;
                        st.saved.set0 = 3u << 10;
                        st.saved.m1 = N64RT_CTRL_MASK1;
                        st.saved.map[0] = 0x1234;
                    }
                    pk.normal = pk.shift = pk.shift_dpad = pk.dpad_keys = 0;
                    m0 = m1 = 0;
                    printf("session_ok\n");
                }
            } else if (!strcmp(cmd, "pick") && scanf("%u %u %u %u", &pk.normal, &pk.shift, &pk.shift_dpad, &pk.dpad_keys) == 4) {
            } else if (!strcmp(cmd, "menu") && scanf("%x %x", &m0, &m1) == 2) {
            } else if (!strcmp(cmd, "eff")) {
                uint32_t s0 = m0, s1 = m1, map[5];
                n64rt_ctrl_effective(&st, &pk, &s0, &s1, map);
                printf("eff %x %x %x %x %x %x %x\n", s0, s1, map[0], map[1], map[2], map[3], map[4]);
            } else if (!strcmp(cmd, "cap")) {
                n64rt_ctrl_t r;
                n64rt_ctrl_capture(&st, &pk, m0, m1, &r);
                printf("cap %x %x %x %x %x %x %x\n", r.set0, r.set1, r.map[0], r.map[1], r.map[2], r.map[3], r.map[4]);
            } else if (!strcmp(cmd, "save")) {
                n64rt_ctrl_capture(&st, &pk, m0, m1, &st.saved);
                st.saved_ok = 1;
            } else if (!strcmp(cmd, "forget")) {
                st.saved_ok = 0;
            } else if (!strcmp(cmd, "presets")) {
                do_presets();
            } else if (!strcmp(cmd, "quit")) {
                break;
            }
        }
        return 0;
    }

    if (argc >= 2 && !strcmp(argv[1], "presets")) {
        do_presets();
    } else if (argc == 4 && !strcmp(argv[1], "session")) {         /* session <saved 0/1> <family>: commands on stdin, one result line per "eff" / "cap" */
        n64rt_ctrl_state_t st;
        memset(&st, 0, sizeof st);
        st.family = atoi(argv[3]);
        if (atoi(argv[2])) { st.saved_ok = 1; st.saved.set0 = 3u << 10; st.saved.m1 = N64RT_CTRL_MASK1; st.saved.map[0] = 0x1234; }
        n64rt_ctrl_pick_t pk = { 0, 0, 0, 0 };
        uint32_t m0 = 0, m1 = 0;
        char cmd[16];
        while (scanf("%15s", cmd) == 1) {
            if (!strcmp(cmd, "pick") && scanf("%u %u %u %u", &pk.normal, &pk.shift, &pk.shift_dpad, &pk.dpad_keys) == 4) { }
            else if (!strcmp(cmd, "menu") && scanf("%x %x", &m0, &m1) == 2) { }
            else if (!strcmp(cmd, "eff")) {
                uint32_t s0 = m0, s1 = m1, map[5];
                n64rt_ctrl_effective(&st, &pk, &s0, &s1, map);
                printf("eff %x %x %x %x %x %x %x\n", s0, s1, map[0], map[1], map[2], map[3], map[4]);
            } else if (!strcmp(cmd, "cap")) {
                n64rt_ctrl_t r;
                n64rt_ctrl_capture(&st, &pk, m0, m1, &r);
                printf("cap %x %x %x %x %x %x %x\n", r.set0, r.set1, r.map[0], r.map[1], r.map[2], r.map[3], r.map[4]);
            } else if (!strcmp(cmd, "save")) { n64rt_ctrl_capture(&st, &pk, m0, m1, &st.saved); st.saved_ok = 1; }
            else if (!strcmp(cmd, "forget")) st.saved_ok = 0;
        }
    } else if (argc == 3 && !strcmp(argv[1], "family")) {
        printf("%d\n", n64rt_ctrl_family((const unsigned char *)argv[2]));
    } else if (argc >= 9 && !strcmp(argv[1], "record")) {
        uint32_t s0 = (uint32_t)strtoul(argv[2], 0, 16);
        uint32_t s1 = (uint32_t)strtoul(argv[3], 0, 16);
        uint32_t m[5];
        for (int i = 0; i < 5; i++) m[i] = (uint32_t)strtoul(argv[4 + i], 0, 16);
        int has_dmg = argc >= 10;
        unsigned dw = has_dmg ? (unsigned)atoi(argv[9]) : 0;
        unsigned db = (argc >= 11) ? (unsigned)atoi(argv[10]) : 0;
        int has_len = argc >= 12;
        unsigned len = has_len ? (unsigned)atoi(argv[11]) : 0;
        do_record(s0, s1, m[0], m[1], m[2], m[3], m[4], has_dmg, dw, db, has_len, len);
    }
    return 0;
}
