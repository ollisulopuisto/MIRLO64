// A behavioural stand-in for Altera's dcfifo (the parameters target/pocket/sync_fifo.sv sets: 4 words, show-ahead off, 5-stage
// synchronisers on both sides), enough for the Icarus bench. The write side counts words in its clock, the read side sees the count
// through a 5-flop synchroniser (so `rdempty` falls a few read clocks after a write, as the real one's does); `q` is registered: it
// takes the word on the edge `rdreq` is high, as with show-ahead off. Not cycle-exact: it is a model.
module dcfifo (
    input  wire [127:0] data,
    input  wire         rdclk, wrclk, rdreq, wrreq, aclr,
    output reg  [127:0] q,
    output wire         rdempty, rdfull, wrempty, wrfull,
    output wire [1:0]   rdusedw, wrusedw,
    output wire [1:0]   eccstatus
);
    parameter intended_device_family = "", lpm_numwords = 4, lpm_showahead = "OFF", lpm_type = "dcfifo", lpm_width = 32, lpm_widthu = 2;
    parameter overflow_checking = "ON", rdsync_delaypipe = 5, underflow_checking = "ON", use_eab = "ON", wrsync_delaypipe = 5;
    reg [127:0] mem [0:3];
    initial q = 0;
    reg [2:0] wp = 0, rp = 0;                       // pointers, 3 bits: full/empty by compare
    reg [2:0] wp_s [0:4];                           // the write pointer through the read side's synchroniser
    integer i;
    reg ovf_shown = 0;
    initial for (i = 0; i < 5; i = i + 1) wp_s[i] = 0;
    always @(posedge wrclk) if (wrreq) begin
        if (wp - rp >= 3'd4) begin
            if (!ovf_shown) $display("dcfifo model: OVERFLOW (a write into a full FIFO is dropped, as overflow_checking ON)");
            ovf_shown <= 1'b1;
        end else begin
            mem[wp[1:0]] <= data;
            wp <= wp + 3'd1;
        end
    end
    always @(posedge rdclk) begin
        wp_s[0] <= wp;
        for (i = 1; i < 5; i = i + 1) wp_s[i] <= wp_s[i - 1];
        if (rdreq && !rdempty) begin                   // (underflow_checking ON: a request of an empty FIFO is ignored; the template's
                                                        // read state machine makes one more request than it needs)
            q <= mem[rp[1:0]];
            rp <= rp + 3'd1;
        end
    end
    assign rdempty = wp_s[4] == rp;
    assign rdfull = 1'b0; assign wrempty = 1'b0; assign wrfull = 1'b0; assign rdusedw = 2'd0; assign wrusedw = 2'd0; assign eccstatus = 2'd0;
endmodule
