// pocket_frame against a model. The input is the scan-out's shape: a field of 240 lines of 640 pixels (two clocks each, the
// second skipped), VS after the last line, the picture's bounds given, a pixel's colour a function of its place inside them
// and black outside. Each configuration runs for several frames (the first announces, the next send it).
#include "Vpocket_frame.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cstring>
#include <algorithm>

struct Cfg { int mode, dock, L, T, W, H, woven; };
static Vpocket_frame *t;
static int errs = 0;
static void tick() { t->clk_vid = 0; t->eval(); t->clk_vid = 1; t->eval(); }

static unsigned colour(int x, int y) { return 0x010101u * (1 + (x * 7 + y * 13) % 250) ^ (unsigned)(x << 12 | y << 4); }
static bool in_pic(const Cfg &c, int x, int y) { return x >= c.L && x < c.L + c.W && y >= c.T && y < c.T + c.H; }
static unsigned src(const Cfg &c, int x, int y) { return in_pic(c, x, y) ? (colour(x, y) & 0xffffff) | 0x010101 : 0; }

static int choose(const Cfg &c) {
    if (c.woven) return 1;
    switch (c.mode) {
    case 1: if (c.W >= 560 && c.W <= 640 && c.H != 0) { if (c.H <= 216 && c.T + 216 <= 240) return 4; if (c.H <= 224 && c.T + 224 <= 240) return 3; if (c.H <= 240) return 2; } return 0;
    case 3: if (!c.dock) { if (c.H >= 234 && c.H <= 240 && c.W >= 520) return 5; if (c.H >= 216 && c.H < 234 && c.W >= 480) return 6; } return 0;
    case 4: return c.H >= 200 && c.H <= 240 && c.W >= 588 ? 7 : 0;
    default: return 0;
    }
}
struct Rect { int x0, w, y0, h; };
static Rect rect(const Cfg &c, int s) {
    switch (s) {
    case 3: return { 0, 640, c.T, 224 };
    case 4: return { 0, 640, c.T, 216 };
    case 5: return { c.L + (c.W - 520) / 2, 520, c.T + (c.H - 234) / 2, 234 };
    case 6: return { c.L + (c.W - 480) / 2, 480, c.T + (c.H - 216) / 2, 216 };
    case 7: return { c.L + (c.W - 588) / 2, 588, 0, 240 };
    default: return { 0, 640, 0, 240 };
    }
}

struct Got { std::vector<std::vector<unsigned>> lines; std::vector<int> words; };

// One frame in; what comes out, with each line's slot word (the word on the first clock after its DE).
static Got frame(const Cfg &c, int lines = 240, int pxw = 640, bool vblank = true) {
    Got g; std::vector<unsigned> cur; bool prev_de = false; int word_after = -1;
    t->screen_mode = c.mode; t->docked = c.dock;
    t->pic_x = c.L; t->pic_y = c.T; t->pic_w = c.W; t->pic_h = c.H;
    t->woven = c.woven; t->ann = 0;
    const int LINE = 1500;
    for (int y = 0; y < (vblank ? 263 : lines); y++) {
        for (int k = 0; k < LINE; k++) {
            const bool act = y < lines && k >= 100 && k < 100 + 2 * pxw;
            const int px = (k - 100) >> 1;
            t->de = act; t->skip = act && ((k - 100) & 1) && !c.woven;
            t->rgb = act ? src(c, px, y) : 0x00aaaa;      // (the scan-out's own word outside DE: not the Pocket's)
            t->hs = k >= 10 && k < 50;
            t->vs = y >= 242 && y < 247 && k >= 60 && k < 70;
            tick();
            // outputs (registered: one clock behind)
            const bool de = t->video_de;
            if (de && (!t->video_skip || c.woven)) cur.push_back(t->video_rgb);
            if (de && !prev_de) cur.clear(), cur.push_back(t->video_rgb);
            if (!de && prev_de) { g.lines.push_back(cur); word_after = 1; }
            else if (word_after == 1 && !de) { g.words.push_back((t->video_rgb >> 13) & 7); word_after = 0; }
            prev_de = de;
        }
    }
    return g;
}

static void check(const char *name, const Cfg &c, const Cfg &prev_cfg, bool steady) {
    // the announcement is for the frame after: this frame is sent as announced by prev (same bounds => right)
    Got g = frame(c);
    const int ps = choose(prev_cfg);
    const Rect r = rect(prev_cfg, ps);
    const bool same = prev_cfg.L == c.L && prev_cfg.T == c.T && prev_cfg.W == c.W && prev_cfg.H == c.H;
    const int want_lines = c.woven ? 240 : (ps <= 2 ? 240 : r.h);       // (a woven frame in this model has 240 lines too)
    if ((int)g.lines.size() != (c.woven ? 240 : want_lines)) { printf("%s: %zu lines, expected %d\n", name, g.lines.size(), want_lines); errs++; return; }
    if (c.woven) return;
    for (int j = 0; j < want_lines; j++) {
        const int w = ps <= 2 ? 640 : r.w;
        if ((int)g.lines[j].size() != w) { printf("%s: line %d has %zu pixels, expected %d\n", name, j, g.lines[j].size(), w); errs++; return; }
        for (int i = 0; i < w; i++) {
            const int sx = (ps <= 2 ? 0 : r.x0) + i, sy = (ps <= 2 ? 0 : r.y0) + j;
            const unsigned e = same ? src(c, sx, sy) : 0;
            if (g.lines[j][i] != e) { printf("%s: (%d,%d) got %06x expected %06x\n", name, i, j, g.lines[j][i], e); errs++; return; }
        }
    }
    // the slot words of this frame announce choose(c)
    for (int w : g.words) if (w != choose(c) && !(steady == false)) { printf("%s: slot word %d, expected %d\n", name, w, choose(c)); errs++; return; }
    if (g.words.empty()) { printf("%s: no slot words\n", name); errs++; }
}

static void run(const char *name, const Cfg &c) {
    frame(c); frame(c);                     // (announces; then sent as announced)
    check(name, c, c, true);
    check(name, c, c, true);
}


// replay <stream> <mode> <dock>: one frame of the real scan-out (sim/vi_filter's TB_STREAM, bounds and all) through pocket_frame, four
// times over; the last pass is the steady one. The preset its bounds ask for (choose) must come out, pixel for pixel, and be announced.
static int replay(const char *file, int mode, int dock) {
    struct Rec { uint32_t px; uint16_t b[4]; uint8_t f, pad[3]; };
    std::vector<Rec> rs; FILE *f = fopen(file, "rb"); if (!f) { printf("no %s\n", file); return 2; }
    Rec r0; while (fread(&r0, sizeof r0, 1, f) == 1) rs.push_back(r0); fclose(f);
    if (rs.empty()) { printf("%s: empty\n", file); return 2; }
    const Cfg c{mode, dock, rs[0].b[0], rs[0].b[1], rs[0].b[2], rs[0].b[3], (rs[0].f >> 4) & 1};
    std::vector<std::vector<unsigned>> in, out; std::vector<unsigned> cur; std::vector<int> words;
    int errs = 0;
    for (int pass = 0; pass < 4; pass++) {
        bool pde = false, pvde = false; int word_after = -1;
        for (int k = -8; k < (int)rs.size(); k++) {
            Rec r = k < 0 ? Rec{0, {rs[0].b[0], rs[0].b[1], rs[0].b[2], rs[0].b[3]}, (uint8_t)(rs[0].f & 0x30), {0, 0, 0}} : rs[k];   // (the gap: nothing, no sync)
            const bool de = r.f & 1, skip = (r.f >> 3) & 1, woven = (r.f >> 4) & 1;
            t->screen_mode = mode; t->docked = dock; t->pic_x = r.b[0]; t->pic_y = r.b[1]; t->pic_w = r.b[2]; t->pic_h = r.b[3];
            t->woven = woven; t->ann = (r.f >> 5) & 1; t->rgb = r.px; t->de = de; t->hs = (r.f >> 1) & 1; t->vs = (r.f >> 2) & 1; t->skip = skip;
            tick();
            if (pass == 0 && k >= 0) {
                if (de && (!skip || woven)) cur.push_back(r.px);
                if (pde && !de) { in.push_back(cur); cur.clear(); }
                pde = de;
            }
            if (pass == 3 && k >= 0) {
                const bool vde = t->video_de;
                if (vde && (!t->video_skip || woven)) cur.push_back(t->video_rgb);
                if (vde && !pvde) cur.clear(), cur.push_back(t->video_rgb);
                if (!vde && pvde) { out.push_back(cur); word_after = 1; }
                else if (word_after == 1 && !vde) { words.push_back((t->video_rgb >> 13) & 7); word_after = 0; }
                pvde = vde;
            }
        }
    }
    const int ps = choose(c); const Rect r = rect(c, ps);
    const bool whole = ps <= 2 || c.woven;
    const int want_lines = whole ? (int)in.size() : r.h;
    printf("  bounds %d,%d %dx%d%s mode %d%s: slot %d", c.L, c.T, c.W, c.H, c.woven ? " woven" : "", mode, dock ? " dock" : "", ps);
    if ((int)out.size() != want_lines) { printf("\n    %zu lines out, expected %d\n", out.size(), want_lines); return 1; }
    for (int j = 0; j < want_lines && !errs; j++) {
        const int w = whole ? (int)in[j].size() : r.w;
        if ((int)out[j].size() != w) { printf("\n    line %d: %zu pixels, expected %d\n", j, out[j].size(), w); errs++; break; }
        for (int i = 0; i < w; i++) {
            const unsigned e = whole ? in[j][i] : in[r.y0 + j][r.x0 + i];
            if (out[j][i] != e) { printf("\n    (%d,%d) got %06x expected %06x\n", i, j, out[j][i], e); errs++; break; }
        }
    }
    if (words.empty()) { printf("\n    no slot words\n"); errs++; }
    for (int w : words) if (w != ps) { printf("\n    slot word %d, expected %d\n", w, ps); errs++; break; }
    if (!errs) printf("  ok (%d x %d)\n", whole ? (int)out[0].size() : r.w, want_lines);
    return errs != 0;
}

int main(int argc, char **argv) {
    if (argc > 4 && !strcmp(argv[1], "replay")) {
        Verilated::commandArgs(argc, argv);
        t = new Vpocket_frame;
        t->rst_vid = 1; for (int i = 0; i < 4; i++) tick(); t->rst_vid = 0;
        for (int i = 0; i < 8; i++) tick();
        const int rc = replay(argv[2], atoi(argv[3]), atoi(argv[4]));
        t->final(); delete t; return rc;
    }
    Verilated::commandArgs(argc, argv);
    t = new Vpocket_frame;
    t->rst_vid = 1; for (int i = 0; i < 4; i++) tick(); t->rst_vid = 0;
    for (int i = 0; i < 8; i++) tick();
    //               mode dock  L  T    W    H woven
    run("original",   Cfg{0, 0,  0, 0, 640, 240, 0});
    run("fit",        Cfg{2, 0,  0, 0, 640, 240, 0});
    run("stretch240", Cfg{1, 0,  0, 0, 640, 240, 0});
    run("stretch224", Cfg{1, 0,  0, 8, 640, 224, 0});
    run("stretch216", Cfg{1, 0,  0, 12, 640, 216, 0});
    run("stretch638", Cfg{1, 0,  2, 0, 638, 240, 0});
    run("stretch320", Cfg{1, 0,  0, 0, 320, 240, 0});      // (no preset: Original)
    // a 237-line window (libultra's, SM64's) at the default Crop Vertical 8, and the crop's other sizes
    run("stretch221", Cfg{1, 0,  0, 8, 638, 221, 0});
    run("stretch232", Cfg{1, 0,  0, 4, 638, 232, 0});
    run("overscale221", Cfg{3, 0,  0, 8, 638, 221, 0});
    run("overscale237", Cfg{3, 0,  0, 0, 638, 237, 0});
    run("hybrid221", Cfg{4, 0,  0, 8, 638, 221, 0});
    run("hybrid-dock221", Cfg{4, 1,  0, 8, 638, 221, 0});
    run("overscale",  Cfg{3, 0,  0, 0, 640, 240, 0});
    run("overscale-d", Cfg{3, 1,  0, 0, 640, 240, 0});
    run("overscale224", Cfg{3, 0,  0, 8, 640, 224, 0});
    run("overscale216", Cfg{3, 0,  0, 12, 640, 216, 0});
    run("overscale-narrow", Cfg{3, 0,  50, 0, 540, 240, 0});
    run("hybrid",     Cfg{4, 0,  0, 0, 640, 240, 0});
    run("hybrid-narrow", Cfg{4, 0,  17, 0, 600, 240, 0});
    run("hybrid-dock", Cfg{4, 1,  0, 0, 640, 240, 0});
    run("hybrid-short", Cfg{4, 0,  0, 8, 640, 224, 0});
    // a change: the first frame of new bounds is black in the old frame's shape, the next is right
    {
        Cfg a{3, 0, 0, 0, 640, 240, 0}, b{3, 0, 0, 8, 640, 224, 0};
        frame(a); frame(a);
        check("change-a-b", b, a, false);       // announced for a: black
        check("change-b", b, b, true);         // (announced on b while a's shape was sent: right now)
    }
    t->final(); delete t;
    printf(errs ? "FAILED: %d errors\n" : "pocket_frame: ok\n", errs);
    return errs != 0;
}
