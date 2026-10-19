// The Pocket's Screen Size setting (fork), without a frame store: the scan-out's own stream, cut to the preset the setting
// asks for. Every preset but the woven one is a rectangle of the 640 x 240 field -- the picture's window, a centred part of
// it, or all of it -- so the rectangle's pixels go out in place and DE is dropped outside it (a preset's rows and columns are
// what the scaler counts). Which preset is announced to the Pocket, as upstream's slot word does, one frame ahead, on the
// bounds the frame being sent has; the frame that has other bounds than the announcement made is sent black.
//
//   mode  Screen Size            preset (video.json), by the picture's bounds (x y w h)
//   0     Original               0: 640 x 240, as the scan-out sends it
//   1     Fill (stretch)         w 600 .. 640: 4: 640 x 216 (h <= 216), 3: 640 x 224 (h <= 224), 2: 640 x 240 (h <= 240) -- the first
//                                that holds the picture's lines (from its first line y, inside the field); else 0
//   2     Fit (keep aspect)      0
//   3     Fill (overscale)       5: 520 x 234 (h 234 .. 240, w >= 520), 6: 480 x 216 (h 216 .. 233, w >= 480), centred in the
//                                picture -- else 0; docked: 0
//   4     Hybrid                 7: 588 x 240 (h 200 .. 240, w >= 588): the field's lines, the picture's columns -- else 0
//   woven frame (640 x 480)      1, whatever the setting: the scan-out's stream as it is
//
// The picture's bounds are the window less the crop options (n64_video's picture_x .. picture_h), in the field's own
// pixels and lines: the first line is 0, the first pixel 0.
`default_nettype none
module pocket_frame (
    input  wire         clk_vid, rst_vid,
    input  wire [2:0]   screen_mode,                // clk_sys: static
    input  wire         docked,                     // static
    input  wire [9:0]   pic_x, pic_y, pic_w, pic_h, // the picture's bounds, clk_vid
    input  wire         woven, ann,                 // the frame being sent is a woven one; the one before it was
    input  wire [23:0]  rgb,
    input  wire         de, hs, vs, skip,
    output logic [23:0] video_rgb = 0,
    output logic        video_de = 0, video_hs = 0, video_vs = 0, video_skip = 0
);
    (* async_reg = "true" *) logic [3:0] set_m, set_s;
    always_ff @(posedge clk_vid) begin set_m <= {docked, screen_mode}; set_s <= set_m; end

    function automatic [2:0] choose(input [3:0] s, input [9:0] y, w, h);
        begin
            choose = 3'd0;
            case (s[2:0])
            3'd1: if (w >= 600 && w <= 640 && h != 0) begin
                      if (h <= 216 && y + 10'd216 <= 240) choose = 3'd4;
                      else if (h <= 224 && y + 10'd224 <= 240) choose = 3'd3;
                      else if (h <= 240) choose = 3'd2;
                  end
            3'd3: if (!s[3]) begin
                      if (h >= 234 && h <= 240 && w >= 520) choose = 3'd5;
                      else if (h >= 216 && h < 234 && w >= 480) choose = 3'd6;
                  end
            3'd4: if (h >= 200 && h <= 240 && w >= 588) choose = 3'd7;
            default: ;
            endcase
        end
    endfunction

    // The announcement: the slot of the next frame, taken as each line's DE ends on the pads, so the last line's is the one
    // the Pocket keeps. The bounds it was made on are kept to check the frame it announces.
    logic [2:0]  ann_slot = 0, act_slot = 0;
    logic [39:0] ann_b = 0, act_b = 0;
    wire  [39:0] live_b = {pic_x, pic_y, pic_w, pic_h};
    wire  [2:0]  next_slot = ann ? 3'd1 : choose(set_s, pic_y, pic_w, pic_h);
    logic vs_d = 0, de_d = 0, vde_d = 0;
    wire  frame_start = vs && !vs_d;
    wire  bypass = woven || act_slot <= 3'd2;      // (a woven frame, or a preset that is the whole field: 0, 1 and 2)

    // The active preset's rectangle: x0 .. x0 + rw - 1, y0 .. y0 + rh - 1 of the field.
    wire [9:0] bl = act_b[39:30], bt = act_b[29:20], bw = act_b[19:10], bh = act_b[9:0];
    logic [9:0] rx0, rw, ry0, rh;
    always_comb begin
        rx0 = 0; rw = 640; ry0 = 0; rh = 240;
        case (act_slot)
        3'd3: begin ry0 = bt; rh = 224; end
        3'd4: begin ry0 = bt; rh = 216; end
        3'd5: begin rx0 = bl + ((bw - 10'd520) >> 1); rw = 520; ry0 = bt + ((bh - 10'd234) >> 1); rh = 234; end
        3'd6: begin rx0 = bl + ((bw - 10'd480) >> 1); rw = 480; ry0 = bt + ((bh - 10'd216) >> 1); rh = 216; end
        3'd7: begin rx0 = bl + ((bw - 10'd588) >> 1); rw = 588; ry0 = 0; rh = 240; end
        default: ;
        endcase
    end

    // Where the stream is: the pixel (two clocks of a progressive frame; the second is the skip) and the line.
    logic [9:0] col = 0, row = 0;
    wire in_rect = col >= rx0 && col < rx0 + rw && row >= ry0 && row < ry0 + rh;
    wire show = bypass || in_rect;
    wire good = bypass || live_b == act_b;
    always_ff @(posedge clk_vid) begin
        if (rst_vid) begin
            ann_slot <= 0; act_slot <= 0; ann_b <= 0; act_b <= 0; col <= 0; row <= 0; vs_d <= 0; de_d <= 0; vde_d <= 0;
            video_rgb <= 0; video_de <= 0; video_hs <= 0; video_vs <= 0; video_skip <= 0;
        end else begin
            vs_d <= vs; de_d <= de; vde_d <= video_de;
            if (frame_start) begin act_slot <= ann_slot; act_b <= ann_b; row <= 0; end
            else if (de_d && !de) row <= row + 10'd1;
            if (!de) col <= 0;
            else if (skip || woven) col <= col + 10'd1;
            // (the pads' next clock)
            video_de <= de && show;
            video_skip <= skip && show;
            video_hs <= hs;
            video_vs <= vs;
            video_rgb <= de && show ? (good ? rgb : 24'd0) : vs ? 24'd0 : {8'd0, ann_slot, 13'd0};
            if (vde_d && !video_de) begin ann_slot <= next_slot; ann_b <= live_b; end
        end
    end
endmodule
`default_nettype wire
