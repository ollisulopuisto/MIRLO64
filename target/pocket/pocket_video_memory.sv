// RGB888 frame store in the otherwise unused PSRAM. Capture uses 64-word
// bursts; scanout fetches a complete row into alternating on-chip caches.
// No game SDRAM traffic. Both frames have a 512-word pitch, 128K-word stride.
`default_nettype none
module pocket_video_memory (
    input wire clk_sys, rst_sys, clk_vid, rst_vid,
    input wire vs, de, skip,
    input wire [23:0] rgb,
    output logic capture_bank,
    output logic capture_good,
    output wire [1:0] completed,
    input wire request,
    input wire request_frame, request_cache, request_pair,
    input wire [7:0] request_y,
    output wire acknowledge,
    input wire [9:0] pixel_address,
    output logic [23:0] pixel00, pixel10, pixel01, pixel11,
    output wire m_valid, m_we, m_last,
    output wire [21:0] m_addr,
    output wire [31:0] m_wdata,
    input wire m_ready, m_rvalid, m_idle, memory_ready,
    input wire [31:0] m_rdata
);
    logic vs_d, de_d;
    logic [8:0] x;
    logic [7:0] y;
    logic take_chunk;
    logic [7:0] chunks, chunks_gray;
    wire [10:0] level;
    wire accept = de && !skip && capture_good &&
                  (x[5:0] == 0 ? level < 11'd896 : take_chunk);
    wire [41:0] head;
    wire empty, pop;
    afifo #(.W(42), .AW(10)) capture_fifo (
        .wclk(clk_vid), .wrst(rst_vid), .w_en(accept),
        .w_data({capture_bank, y, x, rgb}), .w_level(level),
        .rclk(clk_sys), .rrst(rst_sys), .r_en(pop), .r_data(head), .r_empty(empty)
    );
    always_ff @(posedge clk_vid) begin
        if (rst_vid) begin
            vs_d <= 0; de_d <= 0; x <= 0; y <= 0;
            capture_bank <= 0; capture_good <= 0; take_chunk <= 0;
            chunks <= 0; chunks_gray <= 0;
        end else begin
            vs_d <= vs; de_d <= de;
            if (vs && !vs_d) begin
                capture_bank <= !capture_bank; capture_good <= 1;
                x <= 0; y <= 0;
            end else begin
                if (de_d && !de) begin y <= y + 1'b1; x <= 0; end
                if (de && !skip) begin
                    x <= x + 1'b1;
                    if (x[5:0] == 0) begin
                        take_chunk <= level < 11'd896;
                        if (level >= 11'd896) capture_good <= 0;
                    end
                    if (accept && x[5:0] == 63) begin
                        chunks <= chunks + 1'b1;
                        chunks_gray <= (chunks + 8'd1) ^ ((chunks + 8'd1) >> 1);
                    end
                end
            end
        end
    end

    (* async_reg = "true" *) logic [7:0] chunks_meta, chunks_sync;
    (* async_reg = "true" *) logic req_meta, req_sync;
    (* async_reg = "true" *) logic [1:0] done_meta, done_sync;
    (* async_reg = "true" *) logic ack_meta, ack_sync;
    logic [1:0] done;
    logic ack;
    assign completed = done_sync;
    assign acknowledge = ack_sync;
    always_ff @(posedge clk_vid) begin
        if (rst_vid) begin done_meta <= 0; done_sync <= 0; ack_meta <= 0; ack_sync <= 0; end
        else begin done_meta <= done; done_sync <= done_meta; ack_meta <= ack; ack_sync <= ack_meta; end
    end
    logic [7:0] available;
    always_comb begin
        for (int k = 0; k < 8; k++) available[k] = ^(chunks_sync >> k);
    end
    // Mailbox payload stays stable until ack has crossed back to clk_vid.
    logic req_seen, cache;
    logic [7:0] consumed;
    logic [8:0] sent, received;
    logic [8:0] address; // frame/row; sent supplies the read column
    logic final_frame, final_bank;
    typedef enum logic [2:0] {IDLE, WRITE, WRITE_DRAIN, READ, READ_DRAIN} state_t;
    state_t state;
    // Four banks supply adjacent columns in two rows without replicating RAM.
    // Each cache holds a pair of source rows. Even/odd columns have independent
    // read ports; the pair not being displayed is filled by the system clock.
    (* ramstyle = "M10K, no_rw_check" *) logic [23:0] upper_even [0:511];
    (* ramstyle = "M10K, no_rw_check" *) logic [23:0] upper_odd  [0:511];
    (* ramstyle = "M10K, no_rw_check" *) logic [23:0] lower_even [0:511];
    (* ramstyle = "M10K, no_rw_check" *) logic [23:0] lower_odd  [0:511];
    logic lower, pair_read;
    logic [7:0] second_y;
    logic frame_read;
    // Return even/odd taps directly. The caller complements the weight on
    // odd columns instead of multiplexing four 24-bit buses. At x=319 the
    // unused even tap has zero weight, so no out-of-picture colour contributes.
    wire [8:0] even_address = {pixel_address[9], pixel_address[8:1] + {7'd0,pixel_address[0]}};
    (* keep *) wire [8:0] odd_address = {pixel_address[9], pixel_address[8:1]};
    always_ff @(posedge clk_vid) begin
        pixel00 <= upper_even[even_address]; pixel10 <= upper_odd[odd_address];
        pixel01 <= lower_even[even_address]; pixel11 <= lower_odd[odd_address];
    end
    always_ff @(posedge clk_sys) if (state == READ && m_rvalid) begin
        if (!lower && !received[0]) upper_even[{cache, received[8:1]}] <= m_rdata[23:0];
        if (!lower &&  received[0]) upper_odd [{cache, received[8:1]}] <= m_rdata[23:0];
        // Native transfers fill both rows identically, so no unused cache data
        // reaches interpolation even when its vertical fraction is zero.
        if ((lower || !pair_read) && !received[0]) lower_even[{cache, received[8:1]}] <= m_rdata[23:0];
        if ((lower || !pair_read) &&  received[0]) lower_odd [{cache, received[8:1]}] <= m_rdata[23:0];
    end

    assign m_valid = memory_ready && ((state == WRITE && !empty) || (state == READ && sent < 320));
    assign m_we = state == WRITE;
    assign m_addr = {4'd0, state == WRITE ? head[41:24] : {address, sent}};
    assign m_wdata = {8'd0, head[23:0]};
    assign m_last = state == WRITE ? sent == 63 : sent == 319;
    assign pop = m_valid && m_ready && m_we;
    always_ff @(posedge clk_sys) begin
        if (rst_sys) begin
            chunks_meta <= 0; chunks_sync <= 0; req_meta <= 0; req_sync <= 0;
            state <= IDLE; consumed <= 0; req_seen <= 0; ack <= 0; done <= 0;
            sent <= 0; received <= 0; address <= 0; cache <= 0;
            final_frame <= 0; final_bank <= 0; lower <= 0; pair_read <= 0; second_y <= 0; frame_read <= 0;
        end else begin
            chunks_meta <= chunks_gray; chunks_sync <= chunks_meta;
            req_meta <= request; req_sync <= req_meta;
            case (state)
            IDLE: if (memory_ready && m_idle) begin
                sent <= 0; received <= 0;
                if (consumed != available) begin state <= WRITE; final_frame <= 0; end
                else if (req_seen != req_sync) begin
                    req_seen <= req_sync; cache <= request_cache;
                    lower <= 0; pair_read <= request_pair; frame_read <= request_frame;
                    second_y <= request_y < 239 ? request_y + 8'd1 : 8'd239;
                    address <= {request_frame, request_y}; state <= READ;
                end
            end
            WRITE: if (pop) begin
                if (head[40:24] == 0) done[head[41]] <= 0;
                if (head[40:24] == {8'd239, 9'd319}) begin
                    final_frame <= 1; final_bank <= head[41];
                end
                sent <= sent + 1'b1;
                if (sent == 63) begin consumed <= consumed + 1'b1; state <= WRITE_DRAIN; end
            end
            WRITE_DRAIN: if (m_idle) begin
                if (final_frame) done[final_bank] <= 1;
                state <= IDLE;
            end
            READ: begin
                if (m_valid && m_ready) begin sent <= sent + 1'b1;  end
                if (m_rvalid) begin
                    received <= received + 1'b1;
                    if (received == 319) state <= READ_DRAIN;
                end
            end
            READ_DRAIN: if (m_idle) begin
                if (pair_read && !lower) begin
                    lower <= 1; sent <= 0; received <= 0;
                    address <= {frame_read, second_y}; state <= READ;
                end else begin ack <= req_seen; state <= IDLE; end
            end
            default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
