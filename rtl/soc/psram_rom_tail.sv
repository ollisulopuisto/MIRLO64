// The last 16 MiB of a 64 MiB ROM (ROM offsets 48 MiB to 64 MiB) in the Pocket's PSRAM die 1, for the SoC's bridge port
// (mirlo_mips.sv, parameter ROM_TAIL). HARDWARE VERSION, not yet fitted or run on a Pocket; simulated (sim/psram_rom_tail).
//
// The two PSRAMs (cram0, cram1: 16 bits each) are one 32-bit memory of 4 M words (16 MiB) per die, the upper half of a word on
// cram0. Die 1 holds the tail; die 0 is the display's frame store (target/pocket/pocket_video_psram.sv). The two dies share every
// pin but CE#, so there is ONE controller: pocket_video_psram, whose X port (parameter X_EN) does die 1's single asynchronous
// word accesses between the display's bursts, taking turns with them. This module is the SoC's client of that port:
//   rd_*  the PI engine's word read (a copy's source, or the game CPU's lw of the ROM: rcp_mi.sv's P_RD / P_PRIME / P_IO)
//   wr_*  the Pocket bridge's word write while it loads the ROM
// each held until its ack; one at a time (a write first). A read's data is held (rd_sel) from its ack until the SDRAM port's
// next read, so the engine's write of the word, a cycle or more after, still has it (mirlo_mips.sv: pa_dat_r).
`default_nettype none

module psram_rom_tail (
    input  wire         clk, rst,
    input  wire         rd_req,
    input  wire  [21:0] rd_adr,             // word in die 1
    input  wire         wr_req,
    input  wire  [21:0] wr_adr,
    input  wire  [31:0] wr_data,
    input  wire  [3:0]  wr_sel,
    input  wire         sdr_rd,             // the SDRAM's port starts a read (rd_data is no longer the port's data)
    output logic        rd_ack,
    output wire         rd_sel,
    output wire  [31:0] rd_data,
    output logic        wr_ack,
    output wire         ready,
    // pocket_video_psram's X port
    output wire         x_valid, x_we,
    output wire  [21:0] x_addr,
    output wire  [31:0] x_wdata,
    output wire  [3:0]  x_be,
    input  wire         x_ack,
    input  wire  [31:0] x_rdata,
    input  wire         x_ready             // the PSRAMs are set up
);
assign x_valid = wr_req || rd_req;
assign x_we    = wr_req;
assign x_addr  = wr_req ? wr_adr : rd_adr;
assign x_wdata = wr_data;
assign x_be    = wr_sel;
assign rd_data = x_rdata;
assign ready   = x_ready;
logic sel_q;
assign rd_sel  = rd_ack || sel_q;
always_comb begin rd_ack = x_ack && !wr_req; wr_ack = x_ack && wr_req; end
always_ff @(posedge clk) begin
    if (rd_ack) sel_q <= 1'b1; else if (sdr_rd) sel_q <= 1'b0;
    if (rst) sel_q <= 1'b0;
end
endmodule
`default_nettype wire
