`timescale 1ns/1ps
module fps_test;
    logic clk = 0, clk_vid = 0;
    always #5 clk = ~clk;
    always #25 clk_vid = ~clk_vid;
    logic rst = 1, rst_vid = 1, fps_en = 0;
    logic [25:0] origin = 0;
    logic ia_wr = 0;
    logic [5:0] ia_address = 0;
    logic [31:0] ia_data = 0;
    wire ia_fps_en;
    mirlo_regs regs (.clk, .rst, .r_req(1'b0), .r_we(1'b0), .r_addr(16'd0), .r_wdata(32'd0),
        .ia_address, .ia_data, .ia_wr, .ia_fps_en);
    task write_field(input logic [5:0] address, input logic [31:0] data);
        @(negedge clk); ia_address = address; ia_data = data; ia_wr = 1;
        @(negedge clk); ia_wr = 0;
    endtask
    logic injected_frame = 0, injected_pal = 0;
    wire [7:0] r, g, b;
    wire de, tv_pal;
    n64_video video (
        .clk, .clk_vid, .rst, .rst_vid, .enable(1'b0), .vi_origin(origin),
        .vi_width(12'd320), .vi_tall(1'b0), .vi_black(1'b0), .vi_pal(1'b0), .tv_pal,
        .gamma(1'b0), .vi_aa(1'b0), .vi_divot(1'b0), .vi_dedither(1'b0),
        .crop_v(5'd0), .crop_r(2'd0), .vi_lines(9'd240), .vi_x0(6'd0), .vi_y0(6'd0), .vi_rows(9'd240),
        .osd_en(1'b0), .fps_en, .osd_val('0), .m_ready(1'b0), .m_rvalid(1'b0), .m_rdata(32'd0),
        .vga_r(r), .vga_g(g), .vga_b(b), .vga_de(de)
    );
    task tick;
        @(negedge clk); @(posedge clk); #1;
    endtask
    task sample(input int frames, input int changes, input bit pal_mode, input int expected);
        rst = 1; tick(); rst = 0; injected_pal = pal_mode;
        for (int i = 0; i < frames; i++) begin
            if (i < changes) begin origin += 26'd256; tick(); end
            injected_frame = 1; tick(); injected_frame = 0; tick();
        end
        if (video.fps_bcd !== 8'(expected)) $fatal(1, "FPS expected BCD %x got %x", expected, video.fps_bcd);
    endtask
    task capture(input string path, input bit on);
        int fd, pixels, white;
        fps_en = on;
        // Start at a complete active frame, using the output DE's rising rows.
        wait (!de); wait (de); wait (!de);
        // Wait through vblank and into the next first row.
        wait (video.vcount > 10'd240);
        wait (de);
        fd = $fopen(path, "w");
        if (fd == 0) $fatal(1, "Cannot create %s", path);
        $fwrite(fd, "P3\n320 240\n255\n");
        pixels = 0; white = 0;
        while (pixels < 320 * 240) begin
            @(negedge clk_vid);
            if (de) begin
                $fwrite(fd, "%0d %0d %0d\n", r, g, b);
                if ({r, g, b} != 24'd0) white++;
                pixels++;
            end
        end
        $fclose(fd);
        if (on && white == 0) $fatal(1, "Enabled FPS did not draw");
        if (!on && white != 0) $fatal(1, "Disabled FPS drew %0d pixels", white);
        $display("Captured %s (%0d lit pixels)", path, white);
    endtask
    initial begin
        force video.vi_frame = injected_frame;
        force video.tv_pal = injected_pal;
        repeat (4) tick();
        rst_vid = 0; rst = 0;
        if (ia_fps_en !== 0) $fatal(1, "Debug (FPS) reset must be off");
        write_field(14, 1);                  // independent controller bit must survive
        write_field(9, 1);                   // Debug: FPS
        if (ia_fps_en !== 1 || regs.ia1[24] !== 1) $fatal(1, "FPS field enable clobbered controller bit");
        write_field(9, 2);                   // Debug: Graph only (the runtime's): the counter is off
        if (ia_fps_en !== 0 || regs.ia1[24] !== 1) $fatal(1, "Graph only left the FPS counter on");
        write_field(9, 3);
        if (ia_fps_en !== 1) $fatal(1, "FPS and graph did not enable the counter");
        write_field(9, 0);
        if (ia_fps_en !== 0 || regs.ia1[24] !== 1) $fatal(1, "FPS field disable clobbered controller bit");
        sample(60, 30, 0, 'h30);
        sample(50, 25, 1, 'h25);
        sample(60, 0, 0, 'h00);
        sample(60, 60, 0, 'h60);
        sample(60, 30, 0, 'h30);
        capture("fps-on.ppm", 1);
        capture("fps-off.ppm", 0);
        $display("fps_test: PASS (NTSC/PAL counts, zero, BCD carry, overlay on/off)");
        $finish;
    end
    initial begin #50000000; $fatal(1, "Test timeout"); end
endmodule
