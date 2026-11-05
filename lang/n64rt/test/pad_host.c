/* pad_test.py's host side: n64rt_pad_map() (../n64rt_pad.h) over the lines it is given on stdin
 * ("keys joy set0 set1 map0 .. map4", hex) -> "button stick_x stick_y" */
#include <stdio.h>
#include <string.h>
#include "../n64rt_pad.h"

int main(int argc, char **argv)
{
    /* Bolt optimization: optional -u flag enables line-buffering on stdout so
     * persistent harness callers (ctrl_test.py) can read line-by-line without deadlocking.
     * Invoked without arguments (pad_test.py), default block buffering is preserved. */
    if (argc > 1 && !strcmp(argv[1], "-u"))
        setlinebuf(stdout);
    unsigned k, j, s0, s1, m[5];
    while (scanf("%x %x %x %x %x %x %x %x %x", &k, &j, &s0, &s1, &m[0], &m[1], &m[2], &m[3], &m[4]) == 9) {
        const uint32_t map[5] = { m[0], m[1], m[2], m[3], m[4] };
        uint16_t b; int8_t x, y;
        n64rt_pad_map(k, j, s0, s1, map, &b, &x, &y);
        printf("%04x %d %d\n", b, x, y);
    }
    return 0;
}
