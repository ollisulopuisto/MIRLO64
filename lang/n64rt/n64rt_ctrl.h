/* The controller layouts a game can have (n64rt_pad.h's remap table with the settings that go with it): the preset families, which
 * family a cartridge is, the record a game's own layout is saved as (the Pocket's Controls slot, a file per game next to its .sav) and
 * which of the three the "Controls" setting picks. Pure functions of their arguments (no hardware), so that test/ctrl_host.c can run
 * them on the host (test/ctrl_test.py).
 *
 * A layout is: the Modifier (set0 [14:10]), the "C buttons" [14:10], "Stick" [19:15] and "D-pad" [23:22] settings (set1) and the table's
 * 30 fields (map[5]). Every other setting (crops, pak, Show FPS) stays the menu's. A family sets the Modifier and the table (and "C buttons"
 * where it says so), not "Stick" or "D-pad": the menu's choice of which analog stick moves stays; a game's saved layout has all of them.
 *
 * "Controls" (INTERACT2 [24:20], interact.json's first controller entry): 0 Menu (the live table: the menu's Remap entries edit it), 1 Auto
 * (the game's saved layout, else the family it is in, else the menu), 2.. a family, whatever the game: 2 Standard, 3 Platformer /
 * adventure, 4 Shooter, 5 Skate, 6 Racing, 7 Fighter; anything else the menu. The actions: Apply (the editor's choice into the live table),
 * Save (the live table and the menu's settings for this game), Forget. */
#ifndef N64RT_CTRL_H
#define N64RT_CTRL_H
#include <stdint.h>
#include <string.h>

typedef struct { uint32_t set0, set1, m1, map[5]; int mod_default; } n64rt_ctrl_t;   /* m1: which bits of set1 the layout owns (a family's: only "C buttons", and only
                                                                                        * when it sets it); mod_default: its Modifier is a default, the menu's wins if it names one */
#define N64RT_CTRL_MASK0 (31u << 10)
#define N64RT_CTRL_MASK1 ((31u << 10) | (31u << 15) | (3u << 22))
#define N64RT_CTRL_BYTES 64u                     /* the Controls slot's file */
#define N64RT_CTRL_MAGIC 0x4D435431u             /* "MCT1" */

enum { N64RT_FAM_STANDARD, N64RT_FAM_PLATFORMER, N64RT_FAM_SHOOTER, N64RT_FAM_SKATE, N64RT_FAM_RACING, N64RT_FAM_FIGHTER,
       N64RT_FAMILIES };

/* the table's fields (n64rt_pad.h) */
enum { F_A, F_B, F_X, F_Y, F_L, F_R, F_ZL, F_ZR, F_SELECT, F_START, F_L3, F_R3, F_DPAD, F_LSTICK, F_RSTICK, F_HELD = 15 };
/* the outputs of a key's field, and a group's */
enum { O_DFLT = 0, O_A, O_B, O_Z, O_START, O_L, O_R, O_CU, O_CD, O_CL, O_CR, O_DU, O_DD, O_DL, O_DR, O_SAME, O_NONE = 31 };
enum { G_SETTINGS = 0, G_STICK, G_HALF, G_DPAD, G_C, G_NONE, G_SAME };
#define N64RT_MOD_SELECT 6u                      /* the Modifier setting's code for the Pocket's Select */

static inline void n64rt_ctrl_pack(n64rt_ctrl_t *c, const uint8_t f[30])
{
    for (int w = 0; w < 5; w++) {
        uint32_t v = 0;
        for (int i = 0; i < 6; i++) v |= (uint32_t)(f[6 * w + i] & 31u) << (5 * i);
        c->map[w] = v;
    }
}

/* family `fam`'s layout. They are starting points for the Pocket's keys, not a verified setup per game: the Modifier is Select (so
 * that the shoulders keep their jobs); holding it gives the second layer. */
static inline void n64rt_ctrl_preset(unsigned fam, n64rt_ctrl_t *c)
{
    uint8_t f[30];
    memset(f, 0, sizeof f);
    memset(c, 0, sizeof *c);
    c->mod_default = 1;                          /* the family's Modifier (Select) is for a player who has not chosen one in the menu */
    switch (fam) {
    case N64RT_FAM_PLATFORMER:                   /* Mario 64, Banjo, Zelda ... : A, B, C-left (Y), C-right (X); Select + X / Y / D-pad: the rest */
    case N64RT_FAM_SHOOTER:                      /* the same, and the trigger on R (Z), L is the N64's R (aim) */
        c->set0 = N64RT_MOD_SELECT << 10;
        c->set1 = 1u << 10; c->m1 = 31u << 10;   /* the right stick of a dock pad is the C buttons too */
        f[F_HELD + F_X] = O_CU;
        f[F_HELD + F_Y] = O_CD;
        f[F_HELD + F_A] = O_SAME; f[F_HELD + F_B] = O_SAME;      /* (the Held layer's own A, B are C-right, C-down) */
        f[F_HELD + F_L] = O_L;                   /* Select + L: the N64's L */
        f[F_HELD + F_DPAD] = G_C;                /* Select + D-pad: the C buttons */
        if (fam == N64RT_FAM_SHOOTER) { f[F_R] = O_Z; f[F_L] = O_R; }
        break;
    case N64RT_FAM_SKATE:                        /* Tony Hawk ...: the C buttons on the face keys, Select + A / B: the N64's A / B */
        c->set0 = N64RT_MOD_SELECT << 10;
        f[F_A] = O_CR; f[F_B] = O_CD; f[F_X] = O_CU; f[F_Y] = O_CL;
        f[F_HELD + F_A] = O_A; f[F_HELD + F_B] = O_B;
        f[F_HELD + F_X] = O_CU; f[F_HELD + F_Y] = O_CL;
        break;
    case N64RT_FAM_RACING:                       /* Mario Kart ...: the default keys; Select + D-pad steers gently, Select + X / Y: C-up / C-down */
        c->set0 = N64RT_MOD_SELECT << 10;
        f[F_HELD + F_A] = O_SAME; f[F_HELD + F_B] = O_SAME;
        f[F_HELD + F_X] = O_CU;
        f[F_HELD + F_Y] = O_CD;
        break;
    case N64RT_FAM_FIGHTER:                      /* Smash ...: C-up (jump) on X, Z (grab) on L and Y */
        f[F_X] = O_CU;
        f[F_Y] = O_Z;
        f[F_ZL] = O_L;
        break;
    default: break;                              /* Standard: the settings' defaults, with no Modifier */
    }
    n64rt_ctrl_pack(c, f);
}

/* ---- which family a cartridge is: its ID's first three characters (the fourth is the region) ---- */
typedef struct { char id[4]; uint8_t fam; } n64rt_ctrl_game_t;
#define N64RT_CG(i, f) { i, f }
static const n64rt_ctrl_game_t n64rt_ctrl_games[] = {
    /* platformers and adventures */
    N64RT_CG("NSM", N64RT_FAM_PLATFORMER), N64RT_CG("NBK", N64RT_FAM_PLATFORMER), N64RT_CG("NB7", N64RT_FAM_PLATFORMER), N64RT_CG("NDO", N64RT_FAM_PLATFORMER),
    N64RT_CG("NFU", N64RT_FAM_PLATFORMER), N64RT_CG("NGV", N64RT_FAM_PLATFORMER), N64RT_CG("NY2", N64RT_FAM_PLATFORMER), N64RT_CG("NYS", N64RT_FAM_PLATFORMER),
    N64RT_CG("NK4", N64RT_FAM_PLATFORMER), N64RT_CG("NMQ", N64RT_FAM_PLATFORMER), N64RT_CG("CZL", N64RT_FAM_PLATFORMER), N64RT_CG("NZL", N64RT_FAM_PLATFORMER),
    N64RT_CG("NZS", N64RT_FAM_PLATFORMER), N64RT_CG("NG5", N64RT_FAM_PLATFORMER), N64RT_CG("NBC", N64RT_FAM_PLATFORMER), N64RT_CG("NSC", N64RT_FAM_PLATFORMER),
    N64RT_CG("NFX", N64RT_FAM_PLATFORMER), N64RT_CG("NPW", N64RT_FAM_PLATFORMER), N64RT_CG("ND3", N64RT_FAM_PLATFORMER), N64RT_CG("ND4", N64RT_FAM_PLATFORMER),
    N64RT_CG("NBH", N64RT_FAM_PLATFORMER), N64RT_CG("NBM", N64RT_FAM_PLATFORMER), N64RT_CG("NBD", N64RT_FAM_PLATFORMER),
    /* shooters */
    N64RT_CG("NGE", N64RT_FAM_SHOOTER), N64RT_CG("NPD", N64RT_FAM_SHOOTER), N64RT_CG("NT2", N64RT_FAM_SHOOTER), N64RT_CG("NTU", N64RT_FAM_SHOOTER),
    N64RT_CG("NTK", N64RT_FAM_SHOOTER), N64RT_CG("NRW", N64RT_FAM_SHOOTER), N64RT_CG("NDM", N64RT_FAM_SHOOTER), N64RT_CG("NQK", N64RT_FAM_SHOOTER),
    N64RT_CG("NQ2", N64RT_FAM_SHOOTER), N64RT_CG("NHX", N64RT_FAM_SHOOTER), N64RT_CG("NDN", N64RT_FAM_SHOOTER), N64RT_CG("NDZ", N64RT_FAM_SHOOTER),
    N64RT_CG("NJF", N64RT_FAM_SHOOTER), N64RT_CG("NAR", N64RT_FAM_SHOOTER), N64RT_CG("NRS", N64RT_FAM_SHOOTER), N64RT_CG("NSD", N64RT_FAM_SHOOTER),
    N64RT_CG("NWD", N64RT_FAM_SHOOTER), N64RT_CG("NHV", N64RT_FAM_SHOOTER),
    /* skate and snowboard tricks */
    N64RT_CG("NTF", N64RT_FAM_SKATE), N64RT_CG("NTQ", N64RT_FAM_SKATE), N64RT_CG("N3T", N64RT_FAM_SKATE), N64RT_CG("NTE", N64RT_FAM_SKATE),
    N64RT_CG("NSK", N64RT_FAM_SKATE), N64RT_CG("NK2", N64RT_FAM_SKATE), N64RT_CG("NSB", N64RT_FAM_SKATE),
    /* racing */
    N64RT_CG("NKT", N64RT_FAM_RACING), N64RT_CG("NDY", N64RT_FAM_RACING), N64RT_CG("NFZ", N64RT_FAM_RACING), N64RT_CG("CFZ", N64RT_FAM_RACING),
    N64RT_CG("NWR", N64RT_FAM_RACING), N64RT_CG("NR2", N64RT_FAM_RACING), N64RT_CG("NSF", N64RT_FAM_RACING), N64RT_CG("NRU", N64RT_FAM_RACING),
    N64RT_CG("NB8", N64RT_FAM_RACING), N64RT_CG("NNS", N64RT_FAM_RACING), N64RT_CG("NRZ", N64RT_FAM_RACING), N64RT_CG("NEG", N64RT_FAM_RACING),
    N64RT_CG("NG2", N64RT_FAM_RACING), N64RT_CG("NTR", N64RT_FAM_RACING), N64RT_CG("NL2", N64RT_FAM_RACING), N64RT_CG("NGR", N64RT_FAM_RACING),
    N64RT_CG("NRC", N64RT_FAM_RACING), N64RT_CG("NWP", N64RT_FAM_RACING), N64RT_CG("NHW", N64RT_FAM_RACING), N64RT_CG("NCR", N64RT_FAM_RACING),
    N64RT_CG("NCU", N64RT_FAM_RACING), N64RT_CG("NCW", N64RT_FAM_RACING), N64RT_CG("NXO", N64RT_FAM_RACING), N64RT_CG("NLG", N64RT_FAM_RACING),
    N64RT_CG("NMX", N64RT_FAM_RACING), N64RT_CG("NVL", N64RT_FAM_RACING), N64RT_CG("NVY", N64RT_FAM_RACING), N64RT_CG("NPR", N64RT_FAM_RACING),
    N64RT_CG("NGB", N64RT_FAM_RACING),
    /* fighters */
    N64RT_CG("NAL", N64RT_FAM_FIGHTER), N64RT_CG("NM4", N64RT_FAM_FIGHTER), N64RT_CG("NMK", N64RT_FAM_FIGHTER), N64RT_CG("NKI", N64RT_FAM_FIGHTER),
    N64RT_CG("NKA", N64RT_FAM_FIGHTER), N64RT_CG("NFG", N64RT_FAM_FIGHTER), N64RT_CG("NDK", N64RT_FAM_FIGHTER), N64RT_CG("NWA", N64RT_FAM_FIGHTER),
    N64RT_CG("NME", N64RT_FAM_FIGHTER), N64RT_CG("NC2", N64RT_FAM_FIGHTER), N64RT_CG("NCF", N64RT_FAM_FIGHTER), N64RT_CG("NW2", N64RT_FAM_FIGHTER),
    N64RT_CG("NW4", N64RT_FAM_FIGHTER), N64RT_CG("NWN", N64RT_FAM_FIGHTER), N64RT_CG("NWM", N64RT_FAM_FIGHTER), N64RT_CG("NWW", N64RT_FAM_FIGHTER),
    N64RT_CG("NTI", N64RT_FAM_FIGHTER), N64RT_CG("NWV", N64RT_FAM_FIGHTER), N64RT_CG("NWX", N64RT_FAM_FIGHTER), N64RT_CG("NMY", N64RT_FAM_FIGHTER),
    N64RT_CG("NRD", N64RT_FAM_FIGHTER), N64RT_CG("N22", N64RT_FAM_FIGHTER), N64RT_CG("NBF", N64RT_FAM_FIGHTER),
};
#undef N64RT_CG
/* the family of the cartridge whose ID is `id` (four characters), or -1 */
static inline int n64rt_ctrl_family(const unsigned char id[4])
{
    for (unsigned i = 0; i < sizeof n64rt_ctrl_games / sizeof n64rt_ctrl_games[0]; i++)
        if ((unsigned char)n64rt_ctrl_games[i].id[0] == id[0] && (unsigned char)n64rt_ctrl_games[i].id[1] == id[1]
            && (unsigned char)n64rt_ctrl_games[i].id[2] == id[2]) return n64rt_ctrl_games[i].fam;
    return -1;
}

/* ---- a game's saved layout: 16 words (64 bytes) of the Controls slot: the magic, set0 and set1 (masked), the table, a checksum ---- */
static inline uint32_t n64rt_ctrl_sum(const uint32_t *w)
{
    uint32_t s = 0x4C525443u;
    for (int i = 0; i < 8; i++) s = (s << 5 | s >> 27) ^ w[i];
    return s;
}
static inline void n64rt_ctrl_store(volatile uint32_t *mem, const n64rt_ctrl_t *c)
{
    uint32_t w[16];
    memset(w, 0, sizeof w);
    w[0] = N64RT_CTRL_MAGIC;
    w[1] = c->set0 & N64RT_CTRL_MASK0;
    w[2] = c->set1 & N64RT_CTRL_MASK1;
    for (int i = 0; i < 5; i++) w[3 + i] = c->map[i];
    w[8] = n64rt_ctrl_sum(w);
    for (int i = 0; i < 16; i++) mem[i] = w[i];
}
/* 1 and the layout, or 0 (no file, another format, a damaged one) */
static inline int n64rt_ctrl_load(const volatile uint32_t *mem, unsigned file_bytes, n64rt_ctrl_t *c)
{
    if (file_bytes < 36u) return 0;
    uint32_t w[9];
    for (int i = 0; i < 9; i++) w[i] = mem[i];
    if (w[0] != N64RT_CTRL_MAGIC || w[8] != n64rt_ctrl_sum(w)) return 0;
    c->set0 = w[1] & N64RT_CTRL_MASK0;
    c->set1 = w[2] & N64RT_CTRL_MASK1;
    c->m1 = N64RT_CTRL_MASK1;
    c->mod_default = 0;
    for (int i = 0; i < 5; i++) c->map[i] = w[3 + i];
    return 1;
}

/* the layout the "Controls" setting `src` picks: `saved` (a game's, or NULL), `family` (the cartridge's, or -1); fills `tmp` for a
 * family; NULL: the menu's own */
static inline const n64rt_ctrl_t *n64rt_ctrl_select(unsigned src, const n64rt_ctrl_t *saved, int family, n64rt_ctrl_t *tmp)
{
    if (src == 1u) {
        if (saved) return saved;
        if (family < 0) return 0;
        n64rt_ctrl_preset((unsigned)family, tmp);
        return tmp;
    }
    if (src >= 2u && src < 2u + N64RT_FAMILIES) { n64rt_ctrl_preset(src - 2u, tmp); return tmp; }
    return 0;
}
/* ---- the menu's editor: five entries (interact.json has 16 at most) choose one field of the table and what to put in it ----
 * layer 0 Base, 1 Held; key 0-14: A, B, X, Y, L, R, ZL, ZR, Select, Start, L3, R3, then the groups D-pad keys, Left stick, Right stick;
 * gives (a key's output): 0 default, 31 none, 1-14 the outputs (A, B, Z, Start, L, R, C-up/down/left/right, D-up/down/left/right);
 * special: 0 use "gives" (for a group: 0 default / 31 none only), 1 same as Base (the Held layer), 2 Stick, 3 Half stick, 4 N64 D-pad,
 * 5 C buttons (the groups only). -> 1 if the table changed, 0 if the choice means nothing (a key with a group's target, "same as Base" in the
 * Base layer, a group with a key's output) and nothing was written. */
static inline int n64rt_ctrl_edit(n64rt_ctrl_t *c, unsigned layer, unsigned key, unsigned gives, unsigned special)
{
    if (layer > 1u || key >= 15u) return 0;
    const unsigned f = (layer ? F_HELD : 0u) + key;
    uint32_t v;
    if (key >= F_DPAD) {                                /* a group: 0 settings, 1 stick, 2 half, 3 D-pad, 4 C buttons, 5 none, 6 same */
        if (special == 1u) { if (!layer) return 0; v = G_SAME; }
        else if (special >= 2u && special <= 5u) v = special - 1u;
        else if (special == 0u && gives == O_DFLT) v = G_SETTINGS;
        else if (special == 0u && gives == O_NONE) v = G_NONE;
        else return 0;
    } else {                                            /* a key: an output, or 15 (same as Base) */
        if (special == 1u) { if (!layer) return 0; v = O_SAME; }
        else if (special == 0u && (gives == O_DFLT || gives == O_NONE || (gives >= O_A && gives <= O_DR))) v = gives;
        else return 0;
    }
    c->map[f / 6u] = (c->map[f / 6u] & ~(31u << (5u * (f % 6u)))) | (v << (5u * (f % 6u)));
    return 1;
}
/* the settings the pad mapping reads: the menu's words with the layout's parts put in */
static inline void n64rt_ctrl_apply(const n64rt_ctrl_t *c, uint32_t *set0, uint32_t *set1, uint32_t map[5])
{
    if (!c) return;
    if (!(c->mod_default && ((*set0 >> 10) & 31u) != 0u))      /* (the menu's Modifier, if it names a key, over a family's) */
        *set0 = (*set0 & ~N64RT_CTRL_MASK0) | c->set0;
    *set1 = (*set1 & ~c->m1) | (c->set1 & c->m1);
    for (int i = 0; i < 5; i++) map[i] = c->map[i];
}
#endif
