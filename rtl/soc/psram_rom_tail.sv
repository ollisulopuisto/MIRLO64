// The last 16 MiB of a 64 MiB ROM (ROM offsets 48 MiB to 64 MiB) in the Pocket's PSRAM die 1, for the SoC's bridge port
// (mirlo_mips.sv, parameter ROM_TAIL). PROTOTYPE: simulated (sim/psram_rom_tail), never fitted, never on hardware.
//
// The two PSRAMs (cram0, cram1: 16 bits each, two 64 Mbit CellularRAM dies per chip) are one 32-bit memory of 4 M words per
// die, the upper half of a word on cram0. Die 1 (CE1#) is used here, asynchronously (the chips' power-up mode, 70 ns parts);
// die 0 is the display's (target/pocket/pocket_video_psram.sv: the two share every pin but CE#, see below).
//
// Two clients, one access at a time, each held until its ack:
//   rd_*  the PI engine's word read (a copy's source, or the game CPU's lw of the ROM: rcp_mi.sv's P_RD / P_PRIME / P_IO)
//   wr_*  the Pocket bridge's word write while it loads the ROM
// An access, in cycles of clk from the one that takes it (t = 0 is the first cycle the pads show it):
//   t = 0     CE1# low, ADV# low, A[21:16], the address's low 16 bits on the multiplexed bus
//   t = 1     ADV# high; a read: bus released, OE# low;  a write: data and lane enables, WE# low
//   write     WE# high after T_WR cycles (the data held to it); done
//   read      the pads taken T_RD cycles after the address (data valid tAA = 70 ns after ADV# rises, tOE 20 ns after OE#)
//   then the ack (a read's data with it, held until the next read), and two idle cycles (the clients drop their requests)
// With clk at 62.5 MHz (16 ns): T_RD = 7 (the pads as of 96 ns after the address, 80 from ADV# rising: tAA 70 ns; 6 is the least that
// passes the simulation, with 4 ns of delay each way at the pads), T_WR = 4 (64 ns, tWP 46 ns).
// At reset, after the chips' 150 us, die 1's BCR and RCR are written (CRE high; its value on the address lines) so a die another
// core left in burst mode is asynchronous again, the refresh whole.
`default_nettype none

module psram_rom_tail #(
    parameter int T_INIT = 12000,           // clk cycles before the first access (150 us)
    parameter int T_RD   = 7,
    parameter int T_WR   = 4
) (
    input  wire         clk, rst,
    // the PI engine's read (ROM offset word; the caller says it is die 1's)
    input  wire         rd_req,
    input  wire  [21:0] rd_adr,             // word in die 1
    // the bridge's write
    input  wire         wr_req,
    input  wire  [21:0] wr_adr,
    input  wire  [31:0] wr_data,
    input  wire  [3:0]  wr_sel,
    input  wire         sdr_rd,             // the SDRAM's port starts a read (rd_data is no longer the port's data)
    output logic        rd_ack,
    output wire         rd_sel,             // rd_data is the port's data now (from the ack until the SDRAM port's next read)
    output logic [31:0] rd_data,
    output logic        wr_ack,
    output logic        ready,
    // the pads' registers (to a psram_phy: A[21:16], {cram0, cram1} data, the controls; CE0# stays high: die 0 is not ours)
    output logic [5:0]  o_a,
    output logic [31:0] o_dq,
    output logic        o_dq_oe,
    output logic        o_adv_n, o_oe_n, o_we_n, o_cre, o_ce1_n,
    output logic [3:0]  o_bm_n,             // {cram0 UB#, LB#, cram1 UB#, LB#}
    input  wire  [31:0] i_dq
);
localparam logic [15:0] BCR_ASYNC = 16'h9D1F;   // the power-up value: asynchronous
localparam logic [15:0] RCR_ALL   = 16'h0010;   // the whole array refreshed
localparam logic [5:0]  A_BCR     = 6'b001000;  // A[19:18] = 10 (the RCR: 00)

typedef enum logic [2:0] { S_INIT, S_IDLE, S_ASYNC, S_AEND, S_GAP } st_t;
st_t         st;
logic [14:0] t;
logic        a_cfg, a_we, cfg_n, sel_q;
logic        rd_ack_q;
assign rd_sel = rd_ack || sel_q;
always_ff @(posedge clk) begin
    if (rd_ack) sel_q <= 1'b1; else if (sdr_rd) sel_q <= 1'b0;
    if (rst) sel_q <= 1'b0;
end

always_ff @(posedge clk) begin
    rd_ack <= 1'b0; wr_ack <= 1'b0;
    if (rst) begin
        st <= S_INIT; t <= '0; ready <= 1'b0; cfg_n <= 1'b0;
        o_ce1_n <= 1'b1; o_adv_n <= 1'b1; o_oe_n <= 1'b1; o_we_n <= 1'b1; o_cre <= 1'b0; o_dq_oe <= 1'b0;
        o_bm_n <= 4'h0; o_a <= '0; o_dq <= '0;
    end else case (st)
    S_INIT: begin
        t <= t + 15'd1;
        if (t == 15'(T_INIT)) begin
            a_cfg <= 1'b1; a_we <= 1'b1;
            o_ce1_n <= 1'b0; o_adv_n <= 1'b0; o_cre <= 1'b1;
            o_a <= cfg_n ? 6'd0 : A_BCR; o_dq <= {2{cfg_n ? RCR_ALL : BCR_ASYNC}}; o_dq_oe <= 1'b1;
            t <= 15'd0; st <= S_ASYNC;
        end
    end
    S_IDLE: begin
        t <= 15'd0;
        o_bm_n <= 4'h0;
        if (!ready) begin st <= S_INIT; t <= 15'(T_INIT); end
        else if (wr_req || rd_req) begin
            a_cfg <= 1'b0; a_we <= wr_req;
            o_ce1_n <= 1'b0; o_adv_n <= 1'b0;
            o_a <= wr_req ? wr_adr[21:16] : rd_adr[21:16];
            o_dq <= {2{wr_req ? wr_adr[15:0] : rd_adr[15:0]}}; o_dq_oe <= 1'b1;
            st <= S_ASYNC;
        end
    end
    S_ASYNC: begin
        t <= t + 15'd1;
        o_adv_n <= 1'b1;
        if (t == 15'd1) begin
            if (a_we) begin if (!a_cfg) begin o_dq <= wr_data; o_bm_n <= ~wr_sel; end o_we_n <= 1'b0; end
            else begin o_dq_oe <= 1'b0; o_oe_n <= 1'b0; end
        end
        if (t == 15'(T_WR + 1)) o_we_n <= 1'b1;
        if (t == (a_we ? 15'(T_WR + 1) : 15'(T_RD))) begin
            if (!a_we) begin rd_data <= i_dq; o_oe_n <= 1'b1; o_ce1_n <= 1'b1; end
            st <= S_AEND;
        end
    end
    S_AEND: begin
        o_ce1_n <= 1'b1; o_dq_oe <= 1'b0; o_cre <= 1'b0; o_bm_n <= 4'h0;
        t <= 15'd0;
        if (a_cfg) begin
            cfg_n <= 1'b1;
            if (cfg_n) ready <= 1'b1;
            st <= S_IDLE;
        end else begin
            if (a_we) wr_ack <= 1'b1; else rd_ack <= 1'b1;
            st <= S_GAP;
        end
    end
    S_GAP: begin t <= t + 15'd1; if (t[0]) st <= S_IDLE; end
    default: st <= S_IDLE;
    endcase
end
endmodule
`default_nettype wire
