/* ctrl_test.py's host side: n64rt_ctrl.h's presets, record and selection, printed for it to check.
 *   ctrl_host presets            -> "family set0 set1 m1 map0..map4" per family
 *   ctrl_host family ABCD        -> the family of a cartridge ID, or -1
 *   ctrl_host record s0 s1 m0..m4 [damage] -> store, then load back: "1 set0 set1 map0..map4" or "0" */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../n64rt_ctrl.h"

int main(int argc, char **argv)
{
    if (argc >= 2 && !strcmp(argv[1], "presets")) {
        for (unsigned f = 0; f < N64RT_FAMILIES; f++) {
            n64rt_ctrl_t c;
            n64rt_ctrl_preset(f, &c);
            printf("%u %x %x %x %x %x %x %x %x\n", f, c.set0, c.set1, c.m1, c.map[0], c.map[1], c.map[2], c.map[3], c.map[4]);
        }
    } else if (argc == 6 && !strcmp(argv[1], "edit")) {            /* edit layer key gives special -> the changed flag and the table, from a zero one */
        n64rt_ctrl_t c = { 0 };
        const int r = n64rt_ctrl_edit(&c, (unsigned)atoi(argv[2]), (unsigned)atoi(argv[3]), (unsigned)atoi(argv[4]), (unsigned)atoi(argv[5]));
        printf("%d %x %x %x %x %x\n", r, c.map[0], c.map[1], c.map[2], c.map[3], c.map[4]);
    } else if (argc == 3 && !strcmp(argv[1], "family")) {
        printf("%d\n", n64rt_ctrl_family((const unsigned char *)argv[2]));
    } else if (argc >= 9 && !strcmp(argv[1], "record")) {
        n64rt_ctrl_t c = { 0 }, d;
        c.set0 = (uint32_t)strtoul(argv[2], 0, 16); c.set1 = (uint32_t)strtoul(argv[3], 0, 16);
        for (int i = 0; i < 5; i++) c.map[i] = (uint32_t)strtoul(argv[4 + i], 0, 16);
        uint32_t mem[16];
        memset(mem, 0xA5, sizeof mem);
        n64rt_ctrl_store(mem, &c);
        if (argc >= 10) mem[(unsigned)atoi(argv[9]) % 9u] ^= 1u << (unsigned)(argc >= 11 ? atoi(argv[10]) : 0);
        if (n64rt_ctrl_load(mem, argc >= 12 ? (unsigned)atoi(argv[11]) : 64u, &d))
            printf("1 %x %x %x %x %x %x %x\n", d.set0, d.set1, d.map[0], d.map[1], d.map[2], d.map[3], d.map[4]);
        else printf("0\n");
    } else if (argc == 6 && !strcmp(argv[1], "select")) {          /* select src saved(0/1) family -> the layout's set0 set1 m1 map0 (or "menu") */
        n64rt_ctrl_t saved = { 0 }, tmp;
        saved.set0 = 6u << 10; saved.m1 = N64RT_CTRL_MASK1; saved.map[0] = 0x1234;
        const n64rt_ctrl_t *r = n64rt_ctrl_select((unsigned)atoi(argv[2]), atoi(argv[3]) ? &saved : 0, atoi(argv[4]), &tmp);
        if (!r) printf("menu\n"); else printf("%x %x %x %x\n", r->set0, r->set1, r->m1, r->map[0]);
    }
    return 0;
}
