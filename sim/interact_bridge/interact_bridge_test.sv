// The template's read path pushes data when the address CHANGES (core_top.sv): a write of word W while the last-read address is R pushes q(W),
// then q(R), back to back, and the read state machine (sync_fifo.sv) can keep q(W). A read of R next, with no other address between, then
// returns q(W). A fixed order of entries every frame (ORDER=0) cannot do that: the first entry read in a frame is not the last of the one
// before. ORDER=1 shows it happens when they are.
// The Pocket's cycle on the core's settings, end to end (Icarus): the interact part of target/pocket/core_top.sv (copied below: keep it in
// step), the real sync_fifo.sv (with a behavioural dcfifo), and the real rtl/soc/mirlo_regs.sv, against a model of the Pocket doing what
// Analogue's docs say -- every frame it reads each entry's 32-bit bridge address (unless writeonly), applies the user's change and writes
// the value back. What is checked, for a range of spacings between the Pocket's bridge accesses and two orders of the accesses:
//   * what a read returns is what the register holds (so the Pocket's menu shows the true selection),
//   * writing every value back every frame leaves every register as it was (no corruption), and a change lands where it should and
//     nowhere else,
//   * the defaults read back as the defaults (the reset values are the menu's),
//   * the actions flip their bits once per press, whatever the traffic around them.
// `elements.svh` is gen_elements.py's table of pkg/pocket/Cores/tortuga.Mirlo64/interact.json.   sim/interact_bridge/run.sh
`timescale 1ns/1ps
module interact_bridge_test;
    `include "elements.svh"
    parameter int S = 40;                              // clk_74a cycles between the Pocket's bridge accesses
    parameter int MODE = 0;                            // 0: read then write each entry; 1: read them all, then write them all
    parameter int FRAMES = 300;
    parameter int ORDER = 0;                           // 0: the entries in one fixed order every frame (the Pocket's), 1: shuffled each frame (a stress: the same
                                                       // entry last in one frame and first in the next is a hazard of the template's read path, below)
    logic clk_74a = 0, clk_sys = 0;
    always #6.734 clk_74a = ~clk_74a;
    always #8     clk_sys = ~clk_sys;
    logic rst = 1;

    // ---- the bridge (the Pocket's side)
    logic [31:0] bridge_addr = 0, bridge_wr_data = 0;
    logic        bridge_rd = 0, bridge_wr = 0;
    // ---- core_top.sv, the interact CSR section (verbatim) ----------------------------------------------------------------------
    // (Icarus wants a wire declared before it is used: the declarations are in that order here, nothing else differs)
    wire [5:0] interact_rd_addr;
    wire [5:0] interact_wr_addr;
    wire interact_region = bridge_addr >= 32'h1000_0100 && bridge_addr < 32'h1000_0200;
    wire interact_rd;
    wire interact_wr;
    wire [5:0] interact_addr = interact_wr ? interact_wr_addr : interact_rd_addr;
    wire [31:0] interact_data;
    wire [31:0] interact_q;
    wire [31:0] interact_read_data;
    sync_fifo #(.WIDTH(38)) interact_write_sync_fifo (
        .clk_write(clk_74a), .clk_read(clk_sys),
        .write_en(interact_region && bridge_wr), .data({bridge_addr[7:2], bridge_wr_data}),
        .data_s({interact_wr_addr, interact_data}), .write_en_s(interact_wr));
    sync_fifo #(.WIDTH(6)) interact_read_addr_sync_fifo (
        .clk_write(clk_74a), .clk_read(clk_sys),
        .write_en(interact_region && bridge_rd), .data(bridge_addr[7:2]),
        .data_s(interact_rd_addr), .write_en_s(interact_rd));
    reg interact_q_rd = 0;
    sync_fifo #(.WIDTH(32)) interact_read_data_sync_fifo (
        .clk_write(clk_sys), .clk_read(clk_74a),
        .write_en(interact_q_rd), .data(interact_q),
        .data_s(interact_read_data));
    reg [5:0] prev_interact_addr = 0;
    always @(posedge clk_sys) begin
        prev_interact_addr <= interact_addr;
        interact_q_rd <= 0;
        if (interact_addr != prev_interact_addr) begin
            interact_q_rd <= 1;
        end
    end
    // ---- (end of the copy) -----------------------------------------------------------------------------------------------------
    wire [31:0] bridge_rd_data = interact_read_data;   // (core_top's mux, for 0x1000_01XX)

    wire [3:0][31:0] cont0 = '0;
    wire  [4:0] unused_crop_v; wire [1:0] unused_crop_r;
    mirlo_regs regs (.clk(clk_sys), .rst, .r_req(1'b0), .r_we(1'b0), .r_addr(16'd0), .r_wdata(32'd0),
        .ia_address(interact_addr), .ia_data(interact_data), .ia_wr(interact_wr), .ia_q(interact_q),
        .ia_crop_v(unused_crop_v), .ia_crop_r(unused_crop_r),
        .aud_fill(12'd0), .br_file_size(32'd0), .br_complete_trigger(1'b0), .br_current_address(32'd0), .br_command_result_code(3'd0),
        .br_host_reset_n(1'b1), .br_host_loaded(1'b1), .cont_key(cont0), .cont_joy(cont0), .cont_trig(cont0),
        .vblank(1'b0), .tv_pal(1'b0), .bus_errors(16'd0), .su_valid(1'b0), .su_data(32'd0), .cmd_ready(1'b1),
        .mrdp_sync_count(32'd0), .mrdp_load_count(32'd0), .mrdp_unknown_ops(16'd0), .mrdp_idle(1'b1),
        .uart_txfull(1'b0), .uart_rx_byte(8'd0), .uart_rxempty(1'b1), .mon_sp(1'b0), .mon_field(1'b0), .mon_dp(1'b0),
        .mi_w_mi(1'b0), .mi_w_pi(1'b0), .mi_w_we(1'b0), .mi_w_a(2'd0), .mi_w_wd(32'd0), .d_rdata(32'd0), .d_ack(1'b0),
        .io_req(1'b0), .io_we(1'b0), .io_adr(25'd0), .io_wd(32'd0), .vi_irq(1'b0), .vi_chg(1'b0), .vi_clr(1'b0),
        .ai_irq(1'b0), .ai_clr(1'b0), .ai_chg(1'b0), .ai_dac(14'd0), .si_irq(1'b0), .si_clr(1'b0), .si_ev(1'b0),
        .gbc_busy(1'b0), .gbc_rdata(8'd0));

    // what the register file holds at a bus word (the model's view of the truth)
    function automatic int regval(input int w);
        case (w)
        2: regval = regs.ia0[4:0];    3: regval = regs.ia0[9:5];    4: regval = regs.ia0[14:10];  5: regval = regs.ia0[19:15];
        6: regval = regs.ia0[24:20];  7: regval = regs.ia0[29:25];  8: regval = regs.ia1[4:0];    9: regval = regs.ia1[9:5];
        10: regval = regs.ia1[14:10]; 11: regval = regs.ia1[19:15]; 12: regval = regs.ia1[21:20]; 13: regval = regs.ia1[23:22];
        14: regval = regs.ia1[24];    15: regval = regs.ia1[25];
        16, 17, 18, 19, 20: regval = regs.iaf[w - 16];
        default: regval = -1;
        endcase
    endfunction

    int errors = 0, reads = 0, stale = 0;
    string oplog [0:7]; int opn = 0;
    task automatic logop(input string s); oplog[opn % 8] = s; opn++; endtask
    int exp_v [0:NE-1];
    bit exp_a, exp_b;
    task automatic fail(input string s);
        errors++;
        if (errors <= 6) $display("  S=%0d MODE=%0d: %s", S, MODE, s);
        if (errors == 1) for (int k = 0; k < 8; k++) $display("      op -%0d: %s", 8 - k, oplog[(opn + k) % 8]);
    endtask
    task automatic gap(); repeat (S) @(posedge clk_74a); endtask
    task automatic bus_read(input int w, output logic [31:0] v);
        logop($sformatf("read word %0d", w));
        @(posedge clk_74a); bridge_addr <= 32'h1000_0100 + 32'(w) * 4; bridge_rd <= 1;
        @(posedge clk_74a); bridge_rd <= 0;
        repeat (S - 1) @(posedge clk_74a);                // "up until the next read strobe to drive bridge_rd_data"
        v = bridge_rd_data;
    endtask
    task automatic bus_write(input int w, input logic [31:0] v);
        logop($sformatf("write word %0d = %0d", w, v));
        @(posedge clk_74a); bridge_addr <= 32'h1000_0100 + 32'(w) * 4; bridge_wr_data <= v; bridge_wr <= 1;
        @(posedge clk_74a); bridge_wr <= 0;
        gap();
    endtask
    task automatic check_state(input string when);
        for (int e = 0; e < NE; e++) if (!EACT(e) && regval(EWORD(e)) != exp_v[e])
            fail($sformatf("%s: word %0d holds %0d, expected %0d", when, EWORD(e), regval(EWORD(e)), exp_v[e]));
        if (regs.ia_act_a !== exp_a || regs.ia_act_b !== exp_b) fail($sformatf("%s: action bits %b%b, expected %b%b", when, regs.ia_act_a, regs.ia_act_b, exp_a, exp_b));
    endtask
    task automatic press(input int e);                    // an action: one write of its value
        bus_write(EWORD(e), 32'(EVAL(e, 0)));
        if (EVAL(e, 0) & 1) exp_a = !exp_a;
        if (EVAL(e, 0) & 2) exp_b = !exp_b;
    endtask

    logic [31:0] rv;
    int order [0:NE-1], nw [0:NE-1], pick, newv, e, j, t, a;
    initial begin
        for (int e = 0; e < NE; e++) exp_v[e] = EDEF(e);
        exp_a = 0; exp_b = 0;
        repeat (4) @(posedge clk_sys);
        rst = 0;
        repeat (20) @(posedge clk_sys);
        check_state("after reset");
        // the defaults read back as the defaults
        for (int e = 0; e < NE; e++) if (EREAD(e)) begin
            bus_read(EWORD(e), rv); reads++;
            if (rv !== 32'(EDEF(e))) fail($sformatf("default of word %0d reads %0d, expected %0d", EWORD(e), rv, EDEF(e)));
        end
        for (int f = 0; f < FRAMES; f++) begin
            // the user's change this frame: one entry to a random legal value (a third of the frames), an action press (a tenth)
            pick = -1; newv = 0;
            if ($urandom_range(2) == 0) begin
                pick = $urandom_range(NE - 1);
                if (EACT(pick)) pick = -1; else newv = EVAL(pick, $urandom_range(ENV(pick) - 1));
            end
            for (int e = 0; e < NE; e++) order[e] = e;
            if (ORDER) for (e = NE - 1; e > 0; e--) begin j = $urandom_range(e); t = order[e]; order[e] = order[j]; order[j] = t; end
            for (int e = 0; e < NE; e++) nw[e] = -1;
            if (MODE == 0) begin
                for (int i = 0; i < NE; i++) begin
                    e = order[i];
                    if (!EACT(e)) begin
                        bus_read(EWORD(e), rv); reads++;
                        if (rv !== 32'(exp_v[e])) begin stale++; fail($sformatf("frame %0d: read of word %0d returned %0d, the register holds %0d", f, EWORD(e), rv, exp_v[e])); end
                        if (e == pick) exp_v[e] = newv;
                        bus_write(EWORD(e), (e == pick) ? 32'(newv) : rv);          // the value read, written back
                    end
                end
            end else begin
                for (int i = 0; i < NE; i++) begin
                    e = order[i];
                    if (!EACT(e)) begin
                        bus_read(EWORD(e), rv); reads++;
                        if (rv !== 32'(exp_v[e])) begin stale++; fail($sformatf("frame %0d: read of word %0d returned %0d, the register holds %0d", f, EWORD(e), rv, exp_v[e])); end
                        nw[e] = (e == pick) ? newv : int'(rv);
                    end
                end
                for (int i = 0; i < NE; i++) begin
                    e = order[i];
                    if (nw[e] >= 0) begin if (e == pick) exp_v[e] = newv; bus_write(EWORD(e), 32'(nw[e])); end
                end
            end
            if ($urandom_range(9) == 0) begin
                a = $urandom_range(NE - 1);
                if (EACT(a)) press(a);
            end
            repeat (4) gap();                                // (the rest of the frame)
            check_state($sformatf("frame %0d", f));
        end
        if (errors) $display("interact_bridge S=%0d MODE=%0d ORDER=%0d: FAIL (%0d errors, %0d stale reads of %0d)", S, MODE, ORDER, errors, stale, reads);
        else        $display("interact_bridge S=%0d MODE=%0d ORDER=%0d: PASS (%0d reads)", S, MODE, ORDER, reads);
        $finish;
    end
endmodule
