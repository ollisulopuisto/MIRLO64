// The interact side of mirlo_regs (rtl/soc/mirlo_regs.sv) under Icarus: the Pocket's writes of the core's settings -- the two slots'
// fields (2-15) and the controller remap table (16-46) with its two actions (47) -- and what the CPU reads of them (INTERACT0-7),
// against a model of the packing written here from docs/control.md.   sim/interact/run.sh
`timescale 1ns/1ps
module interact_test;
    `include "mirlo_regs.svh"
    logic clk = 0;
    always #8 clk = ~clk;                      // clk_sys, 62.5 MHz
    logic rst = 1;
    logic r_req = 0, r_we = 0;
    logic [15:0] r_addr = 0;
    logic [31:0] r_wdata = 0;
    wire  [31:0] r_rdata;
    logic ia_wr = 0;
    logic [5:0]  ia_address = 0;
    logic [31:0] ia_data = 0;
    wire  [31:0] ia_q;
    wire  [4:0]  ia_crop_v;
    wire  [1:0]  ia_crop_r;
    wire         ia_fps_en;
    wire  [3:0][31:0] cont0 = '0;             // the four pads: nothing pressed
    mirlo_regs regs (.clk, .rst, .r_req, .r_we, .r_addr, .r_wdata, .r_rdata,
        .ia_address, .ia_data, .ia_wr, .ia_q, .ia_crop_v, .ia_crop_r, .ia_fps_en,
        .aud_fill(12'd0), .br_file_size(32'd0), .br_complete_trigger(1'b0), .br_current_address(32'd0), .br_command_result_code(3'd0),
        .br_host_reset_n(1'b1), .br_host_loaded(1'b1), .cont_key(cont0), .cont_joy(cont0), .cont_trig(cont0),
        .vblank(1'b0), .tv_pal(1'b0), .bus_errors(16'd0), .su_valid(1'b0), .su_data(32'd0), .cmd_ready(1'b1),
        .mrdp_sync_count(32'd0), .mrdp_load_count(32'd0), .mrdp_unknown_ops(16'd0), .mrdp_idle(1'b1),
        .uart_txfull(1'b0), .uart_rx_byte(8'd0), .uart_rxempty(1'b1), .mon_sp(1'b0), .mon_field(1'b0), .mon_dp(1'b0),
        .mi_w_mi(1'b0), .mi_w_pi(1'b0), .mi_w_we(1'b0), .mi_w_a(2'd0), .mi_w_wd(32'd0), .d_rdata(32'd0), .d_ack(1'b0),
        .io_req(1'b0), .io_we(1'b0), .io_adr(24'd0), .io_wd(32'd0), .vi_irq(1'b0), .vi_chg(1'b0), .vi_clr(1'b0),
        .ai_irq(1'b0), .ai_clr(1'b0), .ai_chg(1'b0), .ai_dac(14'd0), .si_irq(1'b0), .si_clr(1'b0), .si_ev(1'b0),
        .gbc_busy(1'b0), .gbc_rdata(8'd0));

    int errors = 0;
    task check(input string what, input logic [31:0] got, input logic [31:0] want);
        if (got !== want) begin errors++; $display("FAIL %s: got %08x, want %08x", what, got, want); end
    endtask
    // the Pocket writes an interact.json address (a bus word), as core_top's interact FIFO delivers it: one cycle of ia_wr
    task ia_write(input logic [5:0] word, input logic [31:0] data);
        @(negedge clk); ia_address = word; ia_data = data; ia_wr = 1;
        @(negedge clk); ia_wr = 0; ia_data = 32'hDEADBEEF;
    endtask
    // what the Pocket would read back of a word (ia_q follows ia_address a cycle later)
    task ia_read(input logic [5:0] word, output logic [31:0] q);
        @(negedge clk); ia_address = word;
        @(negedge clk); q = ia_q;
    endtask
    // the CPU's read of a register (one access port: the data the cycle after r_req)
    task csr_read(input logic [15:0] addr, output logic [31:0] q);
        @(negedge clk); r_req = 1; r_we = 0; r_addr = addr;
        @(negedge clk); r_req = 0; q = r_rdata;
    endtask
    task csr_write(input logic [15:0] addr, input logic [31:0] data);
        @(negedge clk); r_req = 1; r_we = 1; r_addr = addr; r_wdata = data;
        @(negedge clk); r_req = 0; r_we = 0;
    endtask
    // the model: field f of the table (bus word 16 + f) is bits [5(f%6)+4 : 5(f%6)] of INTERACT2 + f/6 (docs/control.md)
    logic [4:0] model [0:30];
    function logic [31:0] packed_word(input int w);
        packed_word = 0;
        for (int i = 0; i < 6; i++) if (6 * w + i <= 30) packed_word |= 32'(model[6 * w + i]) << (5 * i);
    endfunction
    task check_table(input string when);
        logic [31:0] q;
        for (int w = 0; w < 5; w++) begin
            csr_read(R_APF_INTERACT_INTERACT2 + 16'(4 * w), q);
            check($sformatf("%s: INTERACT%0d", when, 2 + w), q, packed_word(w));
        end
        csr_read(R_APF_INTERACT_INTERACT7, q);
        check($sformatf("%s: INTERACT7 controls", when), q & 32'h1F, 32'(model[30]));
    endtask

    logic [31:0] q;
    initial begin
        for (int i = 0; i <= 30; i++) model[i] = 0;
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);
        // after reset: the table, the actions and the slots are 0
        check_table("reset");
        csr_read(R_APF_INTERACT_INTERACT7, q); check("reset: INTERACT7", q, 0);
        csr_read(R_APF_INTERACT_INTERACT0, q); check("reset: INTERACT0", q, 0);

        // every field of the table, a distinct value each (bits above [4:0] are ignored)
        for (int f = 0; f <= 30; f++) begin
            model[f] = 5'((f * 7 + 3) % 32);
            ia_write(6'(16 + f), 32'hFFFF_FFE0 | 32'(model[f]));
        end
        check_table("31 fields written");
        // one field rewritten: only it changes
        model[13] = 5'd30; ia_write(6'(16 + 13), 32'd30);
        check_table("field 13 rewritten");
        // words 48-63 are nobody's: nothing changes (the select is address[5] ^ address[4])
        for (int w = 48; w < 64; w++) ia_write(6'(w), 32'h1F);
        check_table("words 48-63 written");
        // the CPU cannot write the table
        csr_write(R_APF_INTERACT_INTERACT2, 32'hFFFF_FFFF);
        csr_write(R_APF_INTERACT_INTERACT7, 32'hFFFF_FFFF);
        check_table("CPU writes to INTERACT2 and 7");
        csr_read(R_APF_INTERACT_INTERACT7, q); check("CPU write: no action bits", q & 32'h300, 0);

        // the actions: 1 flips SAVE (bit 8), 2 flips FORGET (bit 9), in the value's low five bits as every field's; other values do
        // nothing; the Controls field is untouched
        ia_write(47, 1); csr_read(R_APF_INTERACT_INTERACT7, q); check("save pressed", q, 32'h100 | 32'(model[30]));
        ia_write(47, 2); csr_read(R_APF_INTERACT_INTERACT7, q); check("forget pressed", q, 32'h300 | 32'(model[30]));
        ia_write(47, 1); csr_read(R_APF_INTERACT_INTERACT7, q); check("save pressed again", q, 32'h200 | 32'(model[30]));
        ia_write(47, 3); ia_write(47, 0); ia_write(47, 32'h20);
        csr_read(R_APF_INTERACT_INTERACT7, q); check("other values written to 47", q, 32'h200 | 32'(model[30]));
        ia_write(47, 2); csr_read(R_APF_INTERACT_INTERACT7, q); check("forget pressed again", q, 32'(model[30]));
        check_table("after the actions");

        // the Pocket reads none of 16-47 back (every entry is writeonly): 0
        for (int w = 16; w < 48; w++) begin ia_read(6'(w), q); check($sformatf("ia_q of word %0d", w), q, 0); end

        // the legacy fields still work as before: Crop Vertical (3), the old C-layer bit (14), Show FPS (15), and their readback
        ia_write(3, 8);  check("crop_v", 32'(ia_crop_v), 8);
        ia_write(5, 1);  check("crop_r", 32'(ia_crop_r), 1);
        ia_write(14, 1); ia_write(15, 1); check("fps_en", 32'(ia_fps_en), 1);
        ia_write(15, 0); check("fps_en off", 32'(ia_fps_en), 0);
        ia_read(3, q);  check("ia_q of field 3", q, 8);
        ia_read(14, q); check("ia_q of field 14", q, 1);
        ia_write(4, 6);                                           // Modifier = Select
        csr_read(R_APF_INTERACT_INTERACT0, q); check("INTERACT0 fields", q, 32'd6 << 10 | 32'd8 << 5 | 32'd1 << 15);
        csr_read(R_APF_INTERACT_INTERACT1, q); check("INTERACT1 fields", q, 32'd1 << 24);
        // a whole-slot write sets CHANGED, the CPU's read of the slot clears it
        ia_write(1, 32'h0123_4567);
        csr_read(R_APF_INTERACT_INTERACT_CHANGED1, q); check("CHANGED1 set", q, 1);
        csr_read(R_APF_INTERACT_INTERACT1, q);         check("INTERACT1 whole", q, 32'h0123_4567);
        csr_read(R_APF_INTERACT_INTERACT_CHANGED1, q); check("CHANGED1 cleared", q, 0);
        ia_read(1, q); check("ia_q of slot 1", q, 32'h0123_4567);
        check_table("after the legacy fields");                   // (the slots and the table do not touch each other)

        // reset clears everything
        ia_write(47, 1);
        @(negedge clk); rst = 1; @(negedge clk); rst = 0; @(negedge clk);
        for (int i = 0; i <= 30; i++) model[i] = 0;
        check_table("second reset");
        csr_read(R_APF_INTERACT_INTERACT7, q); check("second reset: INTERACT7", q, 0);
        csr_read(R_APF_INTERACT_INTERACT0, q); check("second reset: INTERACT0", q, 0);

        if (errors) begin $display("interact_test: FAIL (%0d)", errors); $finish(1); end
        $display("interact_test: PASS");
        $finish;
    end
endmodule
