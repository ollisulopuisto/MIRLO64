// The ROM's tail in PSRAM die 1 (rtl/soc/psram_rom_tail.sv), simulated: a 64 MiB ROM image written through the bridge's wishbone
// master model, then read back by the game CPU's cart reads (the PI engine's P_IO) and by PI DMA copies across the 48 MiB boundary,
// each word compared with the image's expected value. The real rcp_mi.sv (PI engine), port_apf and psram_rom_tail are in it; the
// SDRAM behind the port is a sparse memory with a few cycles of latency; the PSRAMs are a behavioral model of two async
// CellularRAMs (70 ns: a read's data is wrong -- the complement -- before tAA / tOE, a write's WE# pulse is checked).
// The bridge / port mux below is a copy of the corresponding lines of mirlo_mips.sv (ROM_TAIL = 1): keep the two alike.
`timescale 1ns/1ps
module tb_psram_rom_tail;
parameter int T_RD = 7, T_WR = 4;
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
logic [5:0] ts_a; logic [31:0] ts_dq, ts_i_dq; logic ts_dq_oe, ts_adv_n, ts_oe_n, ts_we_n, ts_cre, ts_ce1_n; logic [3:0] ts_bm_n;
psram_rom_tail #(.T_INIT(40), .T_RD(T_RD), .T_WR(T_WR)) ts (.clk, .rst, .rd_req(ts_hit), .rd_adr(pd_adr[21:0]),
    .wr_req(br_ps_req && !pa_dma), .wr_adr({wishbone_master_adr[21:18] - 4'd1, wishbone_master_adr[17:0]}),
    .wr_data(wishbone_master_dat_w), .wr_sel(wishbone_master_sel), .sdr_rd(p_valid && !p_we),
    .rd_ack(ts_rd_ack), .rd_sel(ts_rd_sel), .rd_data(ts_rd_data), .wr_ack(ts_wr_ack), .ready(ts_ready),
    .o_a(ts_a), .o_dq(ts_dq), .o_dq_oe(ts_dq_oe), .o_adv_n(ts_adv_n), .o_oe_n(ts_oe_n), .o_we_n(ts_we_n), .o_cre(ts_cre),
    .o_ce1_n(ts_ce1_n), .o_bm_n(ts_bm_n), .i_dq(ts_i_dq));
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
assign #4 we_n_c = ts_we_n;   assign #4 ce_n_c = ts_ce1_n;  assign #4 cre_c = ts_cre;     assign #4 a_c = ts_a;   assign #4 bm_c = ts_bm_n;
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
always_ff @(posedge clk) ts_i_dq <= #4 pad;

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
task automatic cart_read(input int unsigned w, output logic [31:0] q);   // the CPU's lw of ROM word w (X_CART's io_*)
    io_adr <= {1'b1, w[23:0]}; io_req <= 1; tick();
    while (!io_ack) tick();
    q = pa_dat_r; io_req <= 0; tick(2);
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

int unsigned wins [8];
initial begin
    logic [31:0] q;
    tick(4); rst <= 0;
    while (!ts_ready) tick();
    tick(5);
    check("BCR and RCR written", cfg_writes, 2);
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
    $display("tb_psram_rom_tail: %0d checks, %0d psram writes, %0d errors, T_RD=%0d T_WR=%0d: %s", checks, mem_writes, errors, T_RD, T_WR,
             errors == 0 ? "PASS" : "FAIL");
    $finish;
end
initial begin #200ms; $display("tb_psram_rom_tail: FAIL timeout"); $finish; end
endmodule
