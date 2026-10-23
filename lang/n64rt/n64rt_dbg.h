/* n64rt_dbg.h -- the debug graph (the fork's menu entry "Debug": Graph). A pure part, host-tested (test/dbg_test.py):
 * the runtime's monitor takes a sample at each tick (four a field: what the game CPU, the RSP and the RDP were doing, and how many frames
 * the game showed), a column of the graph is the window of DBG_TICKS of them, and the graph is drawn into the frame buffer the VI shows.
 *
 * Four bands from the top, each DBG_BAND pixels high, one column a window (about a quarter of a second at 240 ticks a second; the newest
 * column at the right, DBG_COLS of them):
 *   red    the game CPU busy: the share of the samples whose PC was not in the idle thread (a branch to itself, 0x1000FFFF, at the PC or
 *          the word before it: libultra's idle loop; a game with another idle loop reads as busy)
 *   green  the RSP running (SP_STATUS not halted)
 *   blue   the RDP drawing (the RDP not idle)
 *   white  the game's frames (frame buffer swaps) in the window, two to a pixel: 60 fps is full height, 30 fps half
 * A bar grows from the bottom of its band; a full band is 100 %. */
#ifndef N64RT_DBG_H
#define N64RT_DBG_H
#include <stdint.h>

#define N64RT_DBG_COLS  96
#define N64RT_DBG_BAND  8
#define N64RT_DBG_BANDS 4
#define N64RT_DBG_TICKS 60

typedef struct {
    uint8_t  h[N64RT_DBG_BANDS][N64RT_DBG_COLS];        /* bar heights, 0..N64RT_DBG_BAND, by ring index */
    uint32_t head;                                      /* the ring index of the next column (the oldest one) */
    uint32_t ticks, cpu, rsp, rdp, swaps0;              /* the window so far; the frame count at its start */
} n64rt_dbg_t;

static inline int n64rt_dbg_idle(uint32_t insn_at_pc, uint32_t insn_before)
{
    return insn_at_pc == 0x1000FFFFu || insn_before == 0x1000FFFFu;
}

/* one sample; the window's end makes a column */
static inline void n64rt_dbg_sample(n64rt_dbg_t *d, int cpu_busy, int rsp_busy, int rdp_busy, uint32_t swaps)
{
    d->cpu += cpu_busy != 0; d->rsp += rsp_busy != 0; d->rdp += rdp_busy != 0;
    if (++d->ticks < N64RT_DBG_TICKS) return;
    const uint32_t c = d->head++ % N64RT_DBG_COLS, t = N64RT_DBG_TICKS, b = N64RT_DBG_BAND;
    d->h[0][c] = (uint8_t)((d->cpu * b + t / 2) / t);
    d->h[1][c] = (uint8_t)((d->rsp * b + t / 2) / t);
    d->h[2][c] = (uint8_t)((d->rdp * b + t / 2) / t);
    uint32_t f = (swaps - d->swaps0 + 1u) / 2u;
    d->h[3][c] = (uint8_t)(f > b ? b : f);
    d->swaps0 = swaps;
    d->ticks = d->cpu = d->rsp = d->rdp = 0;
}

/* the colours: RGBA5551 and RGBA8888 */
#define N64RT_DBG_RGB16(r, g, b) ((uint16_t)(((r) & 31u) << 11 | ((g) & 31u) << 6 | ((b) & 31u) << 1 | 1u))
#define N64RT_DBG_RGB32(r, g, b) ((uint32_t)(r) << 24 | (uint32_t)(g) << 16 | (uint32_t)(b) << 8 | 0xFFu)
static inline uint32_t n64rt_dbg_px(unsigned band, int on, int bpp32)
{
    static const uint8_t c[4][3] = { { 31, 6, 6 }, { 6, 31, 6 }, { 8, 12, 31 }, { 31, 31, 31 } };
    if (bpp32) return on ? N64RT_DBG_RGB32(c[band][0] * 8, c[band][1] * 8, c[band][2] * 8) : N64RT_DBG_RGB32(32, 32, 32);
    return on ? N64RT_DBG_RGB16(c[band][0], c[band][1], c[band][2]) : N64RT_DBG_RGB16(4, 4, 4);
}

/* Draws the graph with its top left at pixel (x0, y0) of the frame buffer fb (word 0 is pixel 0 of row 0), stride_px pixels a row
 * (the VI's width). 16-bit pixels are stored two to a word (the left one in the high half); an odd stride or x0 draws nothing. */
static inline void n64rt_dbg_draw(const n64rt_dbg_t *d, volatile uint32_t *fb, uint32_t stride_px, int bpp32, uint32_t x0, uint32_t y0)
{
    if (!bpp32 && ((stride_px | x0) & 1u)) return;
    for (unsigned r = 0; r < N64RT_DBG_BANDS * N64RT_DBG_BAND; r++) {
        const unsigned band = r / N64RT_DBG_BAND, k = r % N64RT_DBG_BAND;      /* k = 0 is the band's top row */
        volatile uint32_t *row = fb + (bpp32 ? (y0 + r) * stride_px + x0 : ((y0 + r) * stride_px + x0) / 2u);
        for (unsigned x = 0; x < N64RT_DBG_COLS; x += (bpp32 ? 1u : 2u)) {
            const uint32_t c0 = (d->head + x) % N64RT_DBG_COLS;
            const int on0 = d->h[band][c0] > N64RT_DBG_BAND - 1u - k;
            if (bpp32) { row[x] = n64rt_dbg_px(band, on0, 1); continue; }
            const uint32_t c1 = (d->head + x + 1u) % N64RT_DBG_COLS;
            const int on1 = d->h[band][c1] > N64RT_DBG_BAND - 1u - k;
            row[x / 2u] = n64rt_dbg_px(band, on0, 0) << 16 | n64rt_dbg_px(band, on1, 0);
        }
    }
}

/* The frame rate, as a number (the runtime draws it: the video block's own counter went with the OSD that upstream removed): up to three
 * decimal digits, 3 x 5 pixels of font scaled by two (6 x 10 each, one pixel between), white on the graph's dark grey, top left at (x0, y0). */
static const uint16_t n64rt_dbg_font[10] = {      /* a digit's 15 bits, row by row, the top row in bits 14..12, a row's left pixel in its bit 2 */
    0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9, 0x79CF, 0x79EF, 0x7249, 0x7BEF, 0x7BCF };
static inline void n64rt_dbg_draw_number(volatile uint32_t *fb, uint32_t stride_px, int bpp32, uint32_t x0, uint32_t y0, uint32_t value)
{
    if (!bpp32 && ((stride_px | x0) & 1u)) return;
    if (value > 999u) value = 999u;
    const unsigned digits = value >= 100u ? 3u : value >= 10u ? 2u : 1u;
    const unsigned d3[3] = { value / 100u, (value / 10u) % 10u, value % 10u };
    const unsigned width = 3u * 7u;                                       /* pixels: three cells of 6 + 1 */
    for (unsigned r = 0; r < 10u; r++) {
        volatile uint32_t *row = fb + (bpp32 ? (y0 + r) * stride_px + x0 : ((y0 + r) * stride_px + x0) / 2u);
        uint32_t pix[24];                                                  /* a row's pixels (width, rounded up to even) */
        for (unsigned x = 0; x < 24u; x++) pix[x] = n64rt_dbg_px(0, 0, bpp32);
        for (unsigned k = 0; k < digits; k++) {
            const unsigned d = d3[3u - digits + k], fr = r / 2u;
            for (unsigned c = 0; c < 6u; c++) {
                const int on = (n64rt_dbg_font[d] >> (14u - 3u * fr - c / 2u)) & 1u;
                pix[k * 7u + c] = on ? n64rt_dbg_px(3, 1, bpp32) : n64rt_dbg_px(0, 0, bpp32);
            }
        }
        (void)width;
        if (bpp32) { for (unsigned x = 0; x < 22u; x++) row[x] = pix[x]; }
        else for (unsigned x = 0; x < 22u; x += 2u) row[x / 2u] = pix[x] << 16 | pix[x + 1u];
    }
}
#endif
