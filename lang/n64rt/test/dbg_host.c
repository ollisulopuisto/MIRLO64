/* dbg_test.py's host side: n64rt_dbg.h's windows and drawing, checked against what they should be. Prints "dbg_host: PASS". */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../n64rt_dbg.h"

static int errors;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); errors++; } } while (0)

static void window(n64rt_dbg_t *d, int cpu, int rsp, int rdp, uint32_t swaps, int n)
{   /* n ticks, the first `cpu` of them with the CPU busy, ... */
    uint32_t s0 = d->swaps0;
    for (int i = 0; i < n; i++) n64rt_dbg_sample(d, i < cpu, i < rsp, i < rdp, s0 + (swaps * (uint32_t)(i + 1)) / (uint32_t)n);
}

int main(void)
{
    CHECK(n64rt_dbg_idle(0x1000FFFFu, 0) && n64rt_dbg_idle(0, 0x1000FFFFu) && !n64rt_dbg_idle(0x1000FFFEu, 0), "idle");

    n64rt_dbg_t d; memset(&d, 0, sizeof d);
    window(&d, 60, 0, 30, 15, 60);                        /* a full-busy CPU, no RSP, half the RDP, 15 frames (60 fps in a quarter second) */
    CHECK(d.head == 1 && d.ticks == 0, "one column: head %u ticks %u", d.head, d.ticks);
    CHECK(d.h[0][0] == 8 && d.h[1][0] == 0 && d.h[2][0] == 4 && d.h[3][0] == 8, "heights %d %d %d %d", d.h[0][0], d.h[1][0], d.h[2][0], d.h[3][0]);
    window(&d, 15, 60, 0, 7, 60);                         /* a quarter, all the RSP, none, 7 frames */
    CHECK(d.h[0][1] == 2 && d.h[1][1] == 8 && d.h[2][1] == 0 && d.h[3][1] == 4, "heights %d %d %d %d", d.h[0][1], d.h[1][1], d.h[2][1], d.h[3][1]);
    for (int i = 0; i < N64RT_DBG_COLS; i++) window(&d, 0, 0, 0, 0, 60);   /* the ring wraps: the oldest column is the next to write */
    CHECK(d.head == 2u + N64RT_DBG_COLS, "wrapped head %u", d.head);
    CHECK(d.h[0][0] == 0 && d.h[0][1] == 0, "wrapped columns written");

    /* drawing, 16-bit: columns 0 (oldest) .. 95; a column of full CPU at the newest place */
    memset(&d, 0, sizeof d);
    for (int i = 0; i < N64RT_DBG_COLS - 1; i++) window(&d, 0, 0, 0, 0, 60);
    window(&d, 60, 30, 0, 0, 60);                         /* the newest: CPU 8, RSP 4 */
    enum { W = 320, H = 60 };
    static uint32_t fb[W * H / 2], fb32[W * H];
    n64rt_dbg_draw(&d, fb, W, 0, 4, 12);
    uint16_t *p16 = (uint16_t *)fb;                       /* (a host's little-endian halves: the word's high half is the left pixel) */
    #define PX16(x, y) ((uint16_t)(((x) & 1) ? (fb[((y) * W + (x)) / 2] & 0xFFFFu) : (fb[((y) * W + (x)) / 2] >> 16)))
    (void)p16;
    const int xn = 4 + N64RT_DBG_COLS - 1;                /* the newest column's x */
    CHECK(PX16(xn, 12) == N64RT_DBG_RGB16(31, 6, 6), "CPU bar top %04x", PX16(xn, 12));
    CHECK(PX16(xn, 12 + 7) == N64RT_DBG_RGB16(31, 6, 6), "CPU bar bottom");
    CHECK(PX16(xn - 1, 12 + 7) == N64RT_DBG_RGB16(4, 4, 4), "the column before is empty");
    CHECK(PX16(xn, 12 + 8) == N64RT_DBG_RGB16(4, 4, 4), "RSP band top row is off (height 4)");
    CHECK(PX16(xn, 12 + 8 + 4) == N64RT_DBG_RGB16(6, 31, 6), "RSP bar's top row (row 4 of 8)");
    CHECK(PX16(xn, 12 + 16 + 7) == N64RT_DBG_RGB16(4, 4, 4), "RDP band empty");
    CHECK(PX16(3, 12) == 0 && PX16(xn + 1, 12) == 0, "outside the graph untouched");
    CHECK(PX16(4, 12 + 31) == N64RT_DBG_RGB16(4, 4, 4), "the last row's background");
    CHECK(PX16(4, 12 + 32) == 0, "below untouched");

    /* an odd stride draws nothing; 32-bit pixels */
    static uint32_t odd[400]; n64rt_dbg_draw(&d, odd, 321, 0, 4, 0);
    int any = 0; for (unsigned i = 0; i < 400; i++) any |= odd[i] != 0;
    CHECK(!any, "an odd stride draws nothing");
    n64rt_dbg_draw(&d, fb32, W, 1, 4, 12);
    CHECK(fb32[12 * W + xn] == N64RT_DBG_RGB32(248, 48, 48), "32-bit CPU bar %08x", fb32[12 * W + xn]);
    CHECK(fb32[(12 + 8 + 7) * W + xn] == N64RT_DBG_RGB32(48, 248, 48), "32-bit RSP bar");
    CHECK(fb32[12 * W + 3] == 0 && fb32[12 * W + xn + 1] == 0, "32-bit: outside untouched");

    /* the frame rate: "27" at (4, 46) in 16-bit pixels, one digit, three digits, an odd stride */
    memset(fb, 0, sizeof fb);
    n64rt_dbg_draw_number(fb, W, 0, 4, 46, 27);
    { const int px = 4, py = 46;                          /* the '2' (rows of its font: ###, ..#, ###, #.., ###; each pixel is 2 x 2) */
      CHECK(PX16(px + 0, py + 0) == N64RT_DBG_RGB16(31, 31, 31) && PX16(px + 5, py + 1) == N64RT_DBG_RGB16(31, 31, 31), "the 2's top row");
      CHECK(PX16(px + 0, py + 2) == N64RT_DBG_RGB16(4, 4, 4) && PX16(px + 4, py + 2) == N64RT_DBG_RGB16(31, 31, 31), "the 2's second row: only the right pixel");
      CHECK(PX16(px + 0, py + 6) == N64RT_DBG_RGB16(31, 31, 31) && PX16(px + 5, py + 6) == N64RT_DBG_RGB16(4, 4, 4), "the 2's fourth row: only the left pixel");
      CHECK(PX16(px + 7 + 0, py + 0) == N64RT_DBG_RGB16(31, 31, 31) && PX16(px + 7 + 0, py + 2) == N64RT_DBG_RGB16(4, 4, 4), "the 7's top row, then the rest only on the right");
      CHECK(PX16(px + 7 + 4, py + 4) == N64RT_DBG_RGB16(31, 31, 31), "the 7's stem");
      CHECK(PX16(px + 14, py) == N64RT_DBG_RGB16(4, 4, 4), "no third digit: the background");
      CHECK(PX16(px - 1, py) == 0 && PX16(px, py + 10) == 0, "outside untouched"); }
    memset(fb32, 0, sizeof fb32);
    n64rt_dbg_draw_number(fb32, W, 1, 4, 46, 7);
    CHECK(fb32[46 * W + 4] == N64RT_DBG_RGB32(248, 248, 248) && fb32[46 * W + 3] == 0, "32-bit: the 7's first pixel");
    memset(odd, 0, sizeof odd); n64rt_dbg_draw_number(odd, 321, 0, 4, 0, 5);
    any = 0; for (unsigned i = 0; i < 400; i++) any |= odd[i] != 0;
    CHECK(!any, "an odd stride draws no number");

    if (errors) { printf("dbg_host: FAIL (%d)\n", errors); return 1; }
    printf("dbg_host: PASS\n");
    return 0;
}
