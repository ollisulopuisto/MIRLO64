// The ROM's tail in PSRAM die 1 (rtl/soc/psram_rom_tail.sv), simulated: a 64 MiB ROM image written through the bridge's wishbone
// master model, then read back by the game CPU's cart reads (the PI engine's P_IO) and by PI DMA copies across the 48 MiB boundary,
// each word compared with the image's expected value. The real rcp_mi.sv (PI engine), port_apf and psram_rom_tail are in it; the
// SDRAM behind the port is a sparse memory with a few cycles of latency; the PSRAMs are a behavioral model of two async
// CellularRAMs (70 ns: a read's data is wrong -- the complement -- before tAA / tOE, a write's WE# pulse is checked).
// The bridge / port mux below is a copy of the corresponding lines of mirlo_mips.sv (ROM_TAIL = 1): keep the two alike.
`timescale 1ns/1ps
module tb_psram_rom_tail;
parameter int T_RD = 7;
localparam int MIB = 262144;                    // words
logic clk = 0, rst = 1;
always #8 clk = ~clk;                           // 62.5 MHz
int errors = 0, checks = 0;

// ---------------------------------------------------------------- the image: the ROM's word at a word offset
function automatic logic [31:0] rom_w(input int unsigned w);
    return (w * 32'h9E3779B1) ^ (w << 7) ^ 32'h5A5A1234 ^ (w >> 9);
endfunction
task automatic check(input string what, input logic [31:0] got, input logic [31:0] exp);
    checks++;
    if (got !== exp) begin errors++; if (errors < 20) $display("tb_psram_rom_tail: FAIL %s: got %08x expected %08x", what, got, exp); end
endtask

// ---------------------------------------------------------------- the SDRAM (sparse), behind port_apf's p_* port
logic [31:0] sdram [int];
logic        p_valid, p_we, p_ready, p_rvalid;
logic [23:0] p_addr; logic [31:0] p_wdata, p_rdata; logic [3:0] p_be;
logic [2:0]  rvs; logic [31:0] rq;
assign p_ready = p_valid;
always_ff @(posedge clk) begin
    rvs <= {rvs[1:0], p_valid && !p_we};
    if (p_valid) begin
        if (p_we) begin
            logic [31:0] o;
            o = sdram.exists(int'(p_addr)) ? sdram[int'(p_addr)] : 32'hCCCC_CCCC;
            for (int b = 0; b < 4; b++) if (p_be[b]) o[8*b +: 8] = p_wdata[8*b +: 8];
            sdram[int'(p_addr)] = o;
        end else rq <= sdram.exists(int'(p_addr)) ? sdram[int'(p_addr)] : 32'hCCCC_CCCC;
    end
end
assign p_rvalid = rvs[2]; assign p_rdata = rq;

// ---------------------------------------------------------------- the PI engine (real), the game CPU's cart reads, the CSRs
logic        dst_we = 0, src_we = 0, len_we = 0; logic [25:0] csr_wd = 0;
logic        d_req, d_we, d_ack, io_req = 0, io_ack; logic [24:0] d_adr, io_adr = 0; logic [3:0] d_sel; logic [31:0] d_wdata, pa_dat_r;
logic        pi_busy; logic [20:0] pi_cnt; logic [5:0] intr, mask_o; logic [31:0] w_rd; logic mi_line;
rcp_mi #(.PI(1), .PI2(1)) mi (.clk, .rst, .sp_lvl(1'b0), .vi_pulse(1'b0), .dp_pulse(1'b0), .vi_clr(1'b0), .ai_pulse(1'b0), .ai_clr(1'b0),
    .si_pulse(1'b0), .si_clr(1'b0), .raise_we(1'b0), .clr_we(1'b0), .csr_bits(6'd0), .dst_we, .src_we, .len_we, .csr_wd,
    .intr, .mask_o, .pi_busy, .pi_cnt, .w_mi(1'b0), .w_pi(1'b0), .w_we(1'b0), .w_a(2'd0), .w_wd(32'd0), .w_rd, .line(mi_line),
    .d_req, .d_we, .d_adr, .d_sel, .d_wdata, .d_rdata(pa_dat_r), .d_ack,
    .io_req, .io_we(1'b0), .io_adr, .io_wd(32'd0), .io_ack);

// ---------------------------------------------------------------- the bridge port's mux (a copy of mirlo_mips.sv's, ROM_TAIL = 1)
logic        wishbone_master_cyc = 0, wishbone_master_stb = 0, wishbone_master_we = 0, wishbone_master_ack;
logic [29:0] wishbone_master_adr = 0; logic [31:0] wishbone_master_dat_w = 0; logic [3:0] wishbone_master_sel = 0;
logic        pa_ack, pa_ack_sdr, pa_done, br_ps_ack, br_ps_ackd, pa_dma;
wire  [6:0]  br_mib    = wishbone_master_adr[24:18];
wire         br_ps     = br_mib[6:4] == 3'd3 ? br_mib[3:0] != 4'd0 : br_mib == 7'h40;
wire         br_rd     = br_mib[6:3] == 4'b0111;
wire         br_x      = br_ps && wishbone_master_we;
wire         br_ps_req = wishbone_master_cyc && wishbone_master_stb && br_x && (!br_rd || pa_done) && !br_ps_ack && !br_ps_ackd;
wire         pa_ai = 1'b0, pa_si = 1'b0;
always_ff @(posedge clk) begin
    if (rst) pa_dma <= 1'b0;
    else if (pa_dma) begin if (pa_ack) pa_dma <= 1'b0; end
    else if (d_req && !wishbone_master_cyc) pa_dma <= 1'b1;
end
assign d_ack = pa_dma && pa_ack && !pa_ai && !pa_si;
wire         pd_req = d_req;
wire  [24:0] pd_adr = d_adr;
logic        ts_rd_ack, ts_rd_sel, ts_wr_ack, ts_ready; logic [31:0] ts_rd_data, pa_dat_sdr;
wire         ts_hit  = pa_dma && !pa_ai && !pa_si && d_req && !d_we && pd_adr[24] && pd_adr[23:22] == 2'b11;
wire  [23:0] sdr_adr = pd_adr[24] ? {pd_adr[23:18] + 6'd1, pd_adr[17:0]} : pd_adr[23:0];
logic [5:0] ts_a; logic [31:0] ts_dq, ts_i_dq; logic ts_dq_oe, ts_adv_n, ts_oe_n, ts_we_n, ts_cre; logic [1:0] ts_ce_n; logic [3:0] ts_bm_n;
wire  ts_ce1_n = ts_ce_n[1];
bit x_stress = 0;                  // the X port asks all the time (a stress of the arbitration; its answers go nowhere)
logic x_valid, x_we, x_ack, x_ready; logic [21:0] x_addr; logic [31:0] x_wdata, x_rdata; logic [3:0] x_be;
psram_rom_tail ts (.clk, .rst, .rd_req(ts_hit), .rd_adr(pd_adr[21:0]),
    .wr_req(br_ps_req && !pa_dma), .wr_adr({wishbone_master_adr[21:18] - 4'd1, wishbone_master_adr[17:0]}),
    .wr_data(wishbone_master_dat_w), .wr_sel(wishbone_master_sel), .sdr_rd(p_valid && !p_we),
    .rd_ack(ts_rd_ack), .rd_sel(ts_rd_sel), .rd_data(ts_rd_data), .wr_ack(ts_wr_ack), .ready(ts_ready),
    .x_valid, .x_we, .x_addr, .x_wdata, .x_be, .x_ack(x_ack && !x_stress), .x_rdata, .x_ready);
// the display's controller, the only one for both dies (target/pocket/pocket_video_psram.sv), and the display's traffic on die 0
logic z_valid = 0, z_we = 0, z_last = 0, z_ready, z_rvalid, z_idle, ctl_ready, ts_clk_en; logic [21:0] z_addr = 0; logic [31:0] z_wdata = 0, z_rdata;
pocket_video_psram #(.T_INIT(40), .X_EN(1'b1), .X_T_RD(T_RD)) ctl (.clk, .rst,
    .z_valid, .z_ready, .z_we, .z_addr, .z_wdata, .z_wmask(4'hF), .z_last, .z_rvalid, .z_rdata, .z_idle,
    .x_valid(x_valid || x_stress), .x_we(x_we && !x_stress), .x_addr(x_stress ? 22'h1234 : x_addr), .x_wdata, .x_be, .x_ack, .x_rdata,
    .cfg(4'b0101), .cfg_wr(1'b0), .ready(ctl_ready), .wait_err(),
    .o_a(ts_a), .o_dq(ts_dq), .o_dq_oe(ts_dq_oe), .o_adv_n(ts_adv_n), .o_oe_n(ts_oe_n), .o_we_n(ts_we_n), .o_cre(ts_cre),
    .o_ce_n(ts_ce_n), .o_bm_n(ts_bm_n), .o_clk_en(ts_clk_en), .i_dq(ts_i_dq), .i_wait(2'b00));
assign x_ready = ctl_ready;
assign pa_ack   = pa_ack_sdr || ts_rd_ack;
assign pa_dat_r = ts_rd_sel ? ts_rd_data : pa_dat_sdr;
port_apf pa (.clk, .rst, .cyc(pa_dma ? pd_req && !ts_hit : wishbone_master_cyc && (!br_x || br_rd) && !pa_done), .stb(pa_dma || wishbone_master_stb),
    .we(pa_dma ? d_we : wishbone_master_we), .adr(pa_dma ? {6'd0, sdr_adr} : wishbone_master_adr),
    .dat_w(pa_dma ? d_wdata : wishbone_master_dat_w), .sel(pa_dma ? d_sel : wishbone_master_sel),
    .ack(pa_ack_sdr), .dat_r(pa_dat_sdr),
    .p_valid, .p_we, .p_addr, .p_wdata, .p_be, .p_ready, .p_rvalid, .p_rdata);
always_ff @(posedge clk) begin
    br_ps_ack  <= ts_wr_ack;
    br_ps_ackd <= br_ps_ack;
    if (!wishbone_master_cyc) pa_done <= 1'b0;
    else if (pa_ack_sdr && !pa_dma && br_x) pa_done <= 1'b1;
end
assign wishbone_master_ack = br_x ? br_ps_ack : pa_ack_sdr && !pa_dma;

// ---------------------------------------------------------------- the PSRAMs: two async CellularRAMs on die 1 (CE1#), 70 ns parts
// The pads: 4 ns out of the FPGA's registers, 4 ns back (the input register at the pad: the controller's i_dq).
logic [31:0] bus_fpga, chip_dq; logic bus_oe, adv_n_c, oe_n_c, we_n_c, ce_n_c, cre_c, chip_drv; logic [5:0] a_c; logic [3:0] bm_c;
assign #4 bus_fpga = ts_dq;   assign #4 bus_oe = ts_dq_oe;  assign #4 adv_n_c = ts_adv_n; assign #4 oe_n_c = ts_oe_n;
assign #4 we_n_c = ts_we_n;   assign #4 ce_n_c = ts_ce_n[1];  assign #4 cre_c = ts_cre;     assign #4 a_c = ts_a;   assign #4 bm_c = ts_bm_n;
logic [15:0] mem0 [int], mem1 [int];            // cram0 (a word's upper half), cram1
logic [21:0] ch_adr; realtime t_adv_r = 0, t_oe_f = 0, t_we_f = 0; int cfg_writes = 0, mem_writes = 0, bad_timing = 0;
always @(posedge adv_n_c) if (!ce_n_c) begin
    ch_adr = {a_c, bus_fpga[15:0]}; t_adv_r = $realtime;
    if (cre_c) cfg_writes++;
end
always @(negedge oe_n_c) t_oe_f = $realtime;
always @(negedge we_n_c) t_we_f = $realtime;
always @(posedge we_n_c) if (!ce_n_c && !cre_c) begin
    logic [15:0] o0, o1;
    if ($realtime - t_we_f < 46.0) begin bad_timing++; $display("tb_psram_rom_tail: WE# pulse %0.1f ns", $realtime - t_we_f); end
    o0 = mem0.exists(int'(ch_adr)) ? mem0[int'(ch_adr)] : 16'h0; o1 = mem1.exists(int'(ch_adr)) ? mem1[int'(ch_adr)] : 16'h0;
    if (!bm_c[3]) o0[15:8] = bus_fpga[31:24];
    if (!bm_c[2]) o0[7:0]  = bus_fpga[23:16];
    if (!bm_c[1]) o1[15:8] = bus_fpga[15:8];
    if (!bm_c[0]) o1[7:0]  = bus_fpga[7:0];
    mem0[int'(ch_adr)] = o0; mem1[int'(ch_adr)] = o1; mem_writes++;
end
// a read: the data valid 70 ns after ADV# rose and 20 ns after OE# fell, else wrong (the complement)
always begin
    logic [31:0] d;
    #1;
    chip_drv = !ce_n_c && !oe_n_c && we_n_c && adv_n_c && !cre_c && !bus_oe;
    d = {mem0.exists(int'(ch_adr)) ? mem0[int'(ch_adr)] : 16'hDEAD, mem1.exists(int'(ch_adr)) ? mem1[int'(ch_adr)] : 16'hBEEF};
    chip_dq = ($realtime >= t_adv_r + 70.0 && $realtime >= t_oe_f + 20.0) ? d : ~d;
    if (!ce_n_c && !oe_n_c && bus_oe && we_n_c && adv_n_c) begin bad_timing++; $display("tb_psram_rom_tail: bus contention at %0t", $time); end
end
wire [31:0] pad = bus_oe ? bus_fpga : chip_drv ? chip_dq : 32'hBAD0_BAD0;
logic [31:0] pad_q, d0_dq; logic d0_rd;
always_ff @(posedge clk) pad_q <= #4 pad;
assign ts_i_dq = d0_rd ? d0_dq : pad_q;

// ---------------------------------------------------------------- die 0: the display's frame store
// A cycle model of the controller's burst protocol at its pads (write latency 5, read 4: the data of word i at cycle L + i, back at
// L + i + 2), a sparse memory, and a master that does the display's bursts (random, within a row) and checks every word it reads.
int cyc = 0; always @(posedge clk) cyc++;
logic [31:0] d0mem [int];
logic        d0_act = 0, d0_cfg = 0, d0_wr = 0; int d0_c = 0, d0_tail = 0, d0_bursts = 0, d0_collisions = 0; logic [21:0] d0_a;
initial begin d0_rd = 0; d0_dq = 0; end
function automatic int d0_idx(input logic [21:0] a, input int i); return int'({a[21:7], 7'((int'(a[6:0]) + i) & 127)}); endfunction
always @(posedge clk) begin
    logic [31:0] o; int k;
    if (ts_ce_n == 2'b00 && ctl_ready) d0_collisions++;
    if (!ts_ce_n[0]) begin
        if (!d0_act) begin d0_act = 1; d0_c = 0; d0_tail = 0; d0_cfg = ts_cre; d0_wr = !ts_we_n; d0_a = {ts_a, ts_dq[15:0]}; if (!ts_cre) d0_bursts++; end
        else d0_c++;
    end else if (d0_act) begin d0_act = 0; d0_tail = 5; d0_c++; end
    else if (d0_tail > 0) begin d0_tail--; d0_c++; end
    if ((d0_act || d0_tail > 0) && !d0_cfg && d0_wr && d0_act && d0_c >= 5) begin
        k = d0_idx(d0_a, d0_c - 5); o = d0mem.exists(k) ? d0mem[k] : 32'h0;
        for (int b = 0; b < 4; b++) if (!ts_bm_n[b]) o[8*b +: 8] = ts_dq[8*b +: 8];
        d0mem[k] = o;
    end
    d0_rd <= (d0_act || d0_tail > 0) && !d0_cfg && !d0_wr && d0_c + 1 >= 6;
    k = d0_idx(d0_a, d0_c + 1 - 6);
    d0_dq <= d0mem.exists(k) ? d0mem[k] : 32'hDEADD0D0;
end
function automatic logic [31:0] d0pat(input int unsigned a); return rom_w(a ^ 32'h2A5A5) ^ 32'h0D0D0D0D; endfunction
logic [31:0] exq [$]; int v_max = 0, v_n = 0, v_sum = 0, v_words = 0;
always @(posedge clk) if (z_rvalid) begin
    logic [31:0] e;
    if (exq.size() == 0) begin errors++; $display("tb_psram_rom_tail: FAIL die 0 read data with no read"); end
    else begin e = exq.pop_front(); check("die 0 read", z_rdata, e); v_words++; end
end
// one burst of the display's: n words at word address a0 (in a row); the stall is the cycles from asking to the first word taken
task automatic vburst(input bit we, input int unsigned a0, input int n);
    int i = 0, t0;
    z_we <= we; z_addr <= a0[21:0]; z_wdata <= d0pat(a0); z_last <= n == 1; z_valid <= 1; t0 = cyc;
    forever begin
        @(posedge clk);
        if (z_ready) begin
            if (i == 0) begin v_n++; v_sum += cyc - t0; if (cyc - t0 > v_max) v_max = cyc - t0; end
            if (!we) exq.push_back(d0pat(a0 + i));
            i++;
            if (i == n) begin z_valid <= 0; z_last <= 0; break; end
            z_wdata <= d0pat(a0 + i); z_last <= i == n - 1;
        end
    end
    @(posedge clk);                         // (a request dropped and made again in one cycle is not seen by the sim's scheduler)
endtask
bit v_go = 0, v_busy = 0;
task automatic video_random(input int bursts);
    for (int k = 0; k < bursts || bursts < 0; k++) begin
        int off, n; bit we;
        if (bursts < 0 && !v_go) break;
        off = $urandom_range(127, 0); n = $urandom_range(128 - off > 64 ? 64 : 128 - off, 1);
        we = $urandom_range(1, 0);
        vburst(we, $urandom_range(3, 0) * 128 + off, n);
        tick($urandom_range(30, 0));
    end
endtask

// ---------------------------------------------------------------- the stimuli
task automatic tick(input int n = 1); repeat (n) @(posedge clk); endtask
// the bridge: one word write (the Pocket loads the ROM at 1 MiB: the SDRAM's word is the ROM's word + 1 MiB)
task automatic bridge_write(input int unsigned sdram_word, input logic [31:0] d, input logic [3:0] sel = 4'hF);
    wishbone_master_adr <= 30'(sdram_word); wishbone_master_dat_w <= d; wishbone_master_sel <= sel; wishbone_master_we <= 1;
    wishbone_master_cyc <= 1; wishbone_master_stb <= 1;
    tick();
    while (!wishbone_master_ack) tick();
    wishbone_master_cyc <= 0; wishbone_master_stb <= 0; wishbone_master_we <= 0;
    tick(3);
endtask
task automatic rom_write(input int unsigned w);
    bridge_write(w + MIB, rom_w(w));
endtask
int t_max = 0, t_n = 0, t_sum = 0;
task automatic cart_read(input int unsigned w, output logic [31:0] q);   // the CPU's lw of ROM word w (X_CART's io_*)
    int lat, t0 = cyc;
    io_adr <= {1'b1, w[23:0]}; io_req <= 1; tick();
    while (!io_ack) tick();
    q = pa_dat_r; io_req <= 0; tick(2);
    lat = cyc - t0; if (lat > t_max) t_max = lat; t_n++; t_sum += lat;
endtask
// a PI copy of n words: a ROM source's address is the ROM's word (src_rom), else the SDRAM's
task automatic pi_copy(input int unsigned src_w, input bit src_rom, input bit half, input int unsigned dst_w, input int unsigned n);
    dst_we <= 1; csr_wd <= 26'(dst_w[23:0]); tick(); dst_we <= 0;
    src_we <= 1; csr_wd <= {src_rom, half, src_w[23:0]}; tick(); src_we <= 0;
    len_we <= 1; csr_wd <= 26'(n[20:0]); tick(); len_we <= 0;
    tick(2);
    while (pi_busy) tick();
    tick(4);
endtask

int unsigned wins [8]; int base_max, base_sum, base_n;
initial begin
    logic [31:0] q;
    tick(4); rst <= 0;
    while (!ts_ready) tick();
    tick(5);
    check("BCR and RCR written to die 1", cfg_writes, 2);
    // ---- die 0: the display's frame store: fill 4 rows, then 300 random bursts alone (the baseline of the stall)
    for (int r = 0; r < 4; r++) begin vburst(1, r * 128, 128); end
    video_random(300);
    base_max = v_max; base_sum = v_sum; base_n = v_n; v_max = 0; v_sum = 0; v_n = 0;
    // ---- and from here on the display's traffic runs alongside everything below
    v_go = 1; fork video_random(-1); join_none
    // ---- the bridge: ROM windows of 64 words: below the boundary, across it, the tail's start, ROM 55 MiB (the RDRAM's alias in the
    // SDRAM: the bridge writes 56 to 64 MiB there first), 62 MiB, the end, the start, below 48 MiB
    wins[0] = 10*MIB;       wins[1] = 48*MIB - 32;  wins[2] = 48*MIB + 1000; wins[3] = 55*MIB - 32;
    wins[4] = 62*MIB;       wins[5] = 64*MIB - 64;  wins[6] = 0;             wins[7] = 47*MIB + 5;
    foreach (wins[i]) for (int j = 0; j < 64; j++) rom_write(wins[i] + j);
    // ---- where the words went
    for (int j = 0; j < 32; j += 5) check("sdram below boundary", sdram[wins[1] + j + MIB], rom_w(wins[1] + j));
    check("ROM 48 MiB+: not in the SDRAM's slot area", sdram.exists(int'(wins[2] + 3 + MIB)) ? 1 : 0, 0);
    check("ROM 55 MiB+: the RDRAM alias has it", sdram[wins[3] + 40 + MIB], rom_w(wins[3] + 40));
    check("ROM end: not in the SDRAM", sdram.exists(int'(wins[5] + MIB)) ? 1 : 0, 0);
    check("psram holds only the tail's 288 words (4 windows of 64, 32 of the boundary's)", mem0.size(), 288);
    check("psram written once per tail word", mem_writes, 288);
    check("psram word 1000", {mem0[1000], mem1[1000]}, rom_w(wins[2]));
    check("psram last word", {mem0[16*MIB-1], mem1[16*MIB-1]}, rom_w(64*MIB - 1));
    check("psram word 0 (the boundary)", {mem0[0], mem1[0]}, rom_w(48*MIB));
    // ---- the CPU's cart reads
    for (int j = 0; j < 64; j++) begin
        cart_read(wins[1] + j, q); check($sformatf("cart read across the boundary %0d", j), q, rom_w(wins[1] + j));
        cart_read(wins[2] + j, q); check($sformatf("cart read tail %0d", j), q, rom_w(wins[2] + j));
        cart_read(wins[3] + j, q); check($sformatf("cart read 55 MiB %0d", j), q, rom_w(wins[3] + j));
        cart_read(wins[4] + j, q); check($sformatf("cart read 62 MiB %0d", j), q, rom_w(wins[4] + j));
        cart_read(wins[5] + j, q); check($sformatf("cart read end %0d", j), q, rom_w(wins[5] + j));
    end
    cart_read(wins[0] + 17, q); check("cart read 10 MiB", q, rom_w(wins[0] + 17));
    // ---- PI DMA: 40 words from 20 words below 48 MiB to the SDRAM at 0xF80000 (62 MiB: the RDRAM's place), across the boundary
    pi_copy(48*MIB - 20, 1'b1, 1'b0, 24'hF80000, 40);
    for (int j = 0; j < 40; j++) check($sformatf("dma across the boundary %0d", j), sdram[24'hF80000 + j], rom_w(48*MIB - 20 + j));
    // ---- the same, from an odd halfword (PI2's carry: the copy's word i is source half 2i+1 and 2i+2)
    pi_copy(48*MIB - 8, 1'b1, 1'b1, 24'hF90000, 24);
    for (int j = 0; j < 24; j++)
        check($sformatf("dma half across the boundary %0d", j), sdram[24'hF90000 + j],
              {rom_w(48*MIB - 8 + j)[15:0], rom_w(48*MIB - 8 + j + 1)[31:16]});
    // ---- the last words of the ROM
    pi_copy(64*MIB - 16, 1'b1, 1'b0, 24'hFA0000, 16);
    for (int j = 0; j < 16; j++) check($sformatf("dma to the ROM's end %0d", j), sdram[24'hFA0000 + j], rom_w(64*MIB - 16 + j));
    // ---- a source that is not a ROM (the accessories' area, SDRAM 49 MiB + ..., bit 25 clear) is the SDRAM's, whatever the PSRAM has
    sdram[int'(50*MIB)] = 32'h1234_5678; sdram[int'(50*MIB + 1)] = 32'h9ABC_DEF0;
    pi_copy(50*MIB, 1'b0, 1'b0, 24'hFB0000, 2);
    check("dma of a non-ROM source 0", sdram[24'hFB0000], 32'h1234_5678);
    check("dma of a non-ROM source 1", sdram[24'hFB0001], 32'h9ABC_DEF0);
    // ---- a DMA from the ROM's first 48 MiB is still the SDRAM's (+ 1 MiB)
    pi_copy(10*MIB + 3, 1'b1, 1'b0, 24'hFC0000, 8);
    for (int j = 0; j < 8; j++) check($sformatf("dma below 48 MiB %0d", j), sdram[24'hFC0000 + j], rom_w(10*MIB + 3 + j));
    check("no timing violations at the pads", bad_timing, 0);
    v_go = 0; tick(400);
    check("die 0 and die 1 never selected together", d0_collisions, 0);
    check("every die 0 read answered", exq.size(), 0);
    $display("tb_psram_rom_tail: display bursts' wait to the first word: alone max %0d avg %0d cycles (%0d bursts); with the tail's traffic max %0d avg %0d (%0d bursts, %0d words read back)",
             base_max, base_sum / base_n, base_n, v_max, v_sum / v_n, v_n, v_words);
    // ---- the worst case: the X port asks in every cycle it may, for 60 bursts of the display's
    v_max = 0; v_sum = 0; v_n = 0; x_stress = 1;
    video_random(60);
    x_stress = 0; tick(100);
    $display("tb_psram_rom_tail: with the X port asking all the time: max %0d avg %0d cycles (%0d bursts)", v_max, v_sum / v_n, v_n);
    check("the display waits at most one X access more than alone (+ 16 cycles), the X port saturated", v_max <= base_max + 16 ? 1 : 0, 1);
    $display("tb_psram_rom_tail: the CPU's cart read, request to ack: max %0d avg %0d cycles (%0d reads, display running)", t_max, t_sum / t_n, t_n);
    check("the display waits at most one X access more than alone (+ 16 cycles)", v_max <= base_max + 16 ? 1 : 0, 1);
    check("a cart read waits at most one burst (a display burst of 64 words, 5 + 2 per word, and the access) + 40", t_max <= 2*64 + 160 ? 1 : 0, 1);
    $display("tb_psram_rom_tail: %0d checks, %0d psram writes, %0d errors, T_RD=%0d: %s", checks, mem_writes, errors, T_RD,
             errors == 0 ? "PASS" : "FAIL");
    $finish;
end
initial begin #200ms; $display("tb_psram_rom_tail: FAIL timeout"); $finish; end
endmodule
