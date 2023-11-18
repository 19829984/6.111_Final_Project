`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //crystal reference clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches
  output logic [15:0] led, //16 green output LEDs (located right above switches)
  output logic [2:0] rgb0, //rgb led
  output logic [2:0] rgb1, //rgb led
  output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic hdmi_clk_p, hdmi_clk_n //differential hdmi clock
  );
 
  assign led = sw; //to verify the switch values
  //shut up those rgb LEDs (active high):
  assign rgb1= 0;
  assign rgb0 = 0;
  /* have btnd control system reset */
  logic sys_rst;
  assign sys_rst = btn[0];
 
  logic sys_clk, clk_pixel, clk_5x; //clock lines
  logic locked; //locked signal (we'll leave unused but still hook it up)

  //clock manager...creates 74.25 Hz and 5 times 74.25 MHz for pixel and TMDS
  hdmi_clk_wiz_720p mhdmicw (
      .reset(0),
      .locked(locked),
      .clk_ref(clk_100mhz),
      .clk_pixel(clk_pixel),
      .clk_tmds(clk_5x),
      .clk_sys(sys_clk));
 
  logic [10:0] hcount; //hcount of system!
  logic [9:0] vcount; //vcount of system!
  logic hor_sync; //horizontal sync signal
  logic vert_sync; //vertical sync signal
  logic active_draw; //ative draw! 1 when in drawing region.0 in blanking/sync
  logic new_frame; //one cycle active indicator of new frame of info!
  logic [5:0] frame_count; //0 to 59 then rollover frame counter
 
  //default instantiation so making signals for 720p
  video_sig_gen mvg(
      .clk_pixel_in(clk_pixel),
      .rst_in(sys_rst),
      .hcount_out(hcount),
      .vcount_out(vcount),
      .vs_out(vert_sync),
      .hs_out(hor_sync),
      .ad_out(active_draw),
      .nf_out(new_frame),
      .fc_out(frame_count));

  logic [10:0] hcount_scaled;
  logic [9:0] vcount_scaled;
  logic valid_scaled_addr;

  upScale(
    .hcount_in(hcount),
    .vcount_in(vcount),
    .scaled_hcount_out(hcount_scaled),
    .scaled_vcount_out(vcount_scaled),
    .valid_addr_out(valid_scaled_addr)
  );

  localparam COORD_WIDTH = 16;
  logic signed [COORD_WIDTH-1:0] x, y;
  logic drawing;

  // bresenhamLine #(.COORD_WIDTH(COORD_WIDTH)) draw_bresenham (
  //     .clk_in(clk_pixel),
  //     .rst_in(sys_rst),
  //     .start_draw(btn[1]),
  //     .oe(1),
  //     .x0(50),
  //     .y0(50),
  //     .x1(300),
  //     .y1(150),
  //     .x(x),
  //     .y(y),
  //     .drawing(drawing),
  //     .busy(),
  //     .done()
  // );

  // Double Frame Buffer and its state machine
  localparam FB_BIT_WIDTH = 21;
  localparam FB_WIDTH = 320;
  localparam FB_HEIGHT = 180;
  localparam FB_NUM_PIXELS = FB_WIDTH * FB_HEIGHT;
  localparam FB_ADDR_WIDTH = $clog2(FB_NUM_PIXELS);
  logic [FB_BIT_WIDTH-1:0] fb_read, fb_read_1, fb_read_2;
  logic [FB_BIT_WIDTH-1:0] fb_write_color, fb_clear_color, fb_render_color;
  logic [FB_ADDR_WIDTH-1:0] fb_write_addr, fb_clear_addr, fb_render_addr;
  logic [FB_ADDR_WIDTH-1:0] fb_read_addr;
  logic fb_we, fb_front;

  assign fb_read_addr = hcount_scaled + FB_WIDTH*vcount_scaled;
  assign fb_render_addr = x + FB_WIDTH*y;
  assign fb_render_color = 21'b111111111111111111111;
  // Frame Buffer for 320x180 5656RGBA frame
  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(FB_BIT_WIDTH),
    .RAM_DEPTH(FB_NUM_PIXELS))
    frame_buffer_1 (
    .addra(fb_write_addr), //pixels are stored using this math
    .clka(clk_pixel),
    .wea(fb_we && fb_front),
    .dina(fb_write_color),
    .ena(1'b1),
    .regcea(1'b1),
    .rsta(sys_rst),
    .douta(), //never read from this side
    .addrb(fb_read_addr),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(valid_scaled_addr),
    .rstb(sys_rst),
    .regceb(1'b1),
    .doutb(fb_read_1)
  );

  // Frame Buffer for 320x180 5656RGBA frame
  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(FB_BIT_WIDTH),
    .RAM_DEPTH(FB_NUM_PIXELS))
    frame_buffer_2 (
    .addra(fb_write_addr), //pixels are stored using this math
    .clka(clk_pixel),
    .wea(fb_we && ~fb_front),
    .dina(fb_write_color),
    .ena(1'b1),
    .regcea(1'b1),
    .rsta(sys_rst),
    .douta(), //never read from this side
    .addrb(fb_read_addr),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(valid_scaled_addr),
    .rstb(sys_rst),
    .regceb(1'b1),
    .doutb(fb_read_2)
  );
  
  enum {IDLE, INIT, CLEARING, DRAW, DONE} fb_state;
  logic start_render;
  logic render_done;
  always_ff @(posedge clk_pixel) begin
    if (sys_rst) begin
      fb_state <= IDLE;
    end else begin
      case (fb_state)
        IDLE: begin
          if (new_frame) begin
            fb_state <= INIT;
          end
        end
        INIT: begin
          fb_state <= CLEARING;
          fb_front <= ~fb_front;
          fb_clear_addr <= 0;
          fb_clear_color <= 21'b000000000000000000000;
        end
        CLEARING: begin
          fb_clear_addr <= fb_clear_addr + 1;
          if (fb_clear_addr == FB_NUM_PIXELS - 1) begin
            fb_state <= DRAW;
            start_render <= 1;
          end
        end
        DRAW: begin
          if (render_done) begin
            fb_state <= DONE;
          end
          start_render <= 0;
        end
        DONE: begin
          fb_state <= IDLE;
        end
        default: begin
          if (new_frame) begin
            fb_state <= INIT;
          end
        end
      endcase
    end
  end
  logic [COORD_WIDTH-1:0] x_input;
  logic [COORD_WIDTH-1:0] y_input;
  always_ff @(posedge clk_pixel) begin
    fb_write_addr <= (fb_state == CLEARING) ? fb_clear_addr : fb_render_addr;
    fb_write_color <= (fb_state == CLEARING) ? fb_clear_color : fb_render_color;
    fb_read <= fb_front ? fb_read_2 : fb_read_1;
    fb_we <= (fb_state == CLEARING) || (drawing);
    if (new_frame) begin
      if (sw[3]) begin
        x_input <= x_input + 1;
      end
      if (sw[4]) begin
        x_input <= x_input - 1;
      end
      if (sw[5]) begin
        y_input <= y_input + 1;
      end
      if (sw[6]) begin
        y_input <= y_input - 1;
      end
    end
  end

  // Rendering
  bresenhamTriangleFill #(.COORD_WIDTH(COORD_WIDTH)) draw_triangle (
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .start_draw(start_render),
      .oe(1),
      .x0(x_input),
      .y0(y_input),
      .x1(300),
      .y1(50),
      .x2(200),
      .y2(170),
      .x(x),
      .y(y),
      .drawing(drawing),
      .busy(),
      .done(render_done)
  );

  logic [7:0] tp_r, tp_g, tp_b; //color values as generated by test_pattern module

  test_pattern_generator mtpg(
      .sel_in(sw[1:0]),
      .hcount_in(hcount_scaled),
      .vcount_in(vcount_scaled),
      .red_out(tp_r),
      .green_out(tp_g),
      .blue_out(tp_b));

  logic [7:0] red, green, blue, depth; //red green and blue pixel values for output
  logic [7:0] converted_r, converted_g, converted_b; //converted values for output
  
  color_conversion col_converter(
    .clk_in(clk_pixel),
    .red_in(fb_read[20:16]),
    .green_in(fb_read[16:10]),
    .blue_in(fb_read[10:6]),
    .red_out(converted_r),
    .green_out(converted_g),
    .blue_out(converted_b)
  );

  always_comb begin
    if (~sw[2])begin //if switch 2 pushed use shapes signal from part 2, else defaults
      red = tp_r;
      green = tp_g;
      blue = tp_b;
    end else begin
      red = converted_r;
      green = converted_g;
      blue = converted_b;
      // depth = fb_read_1[5:0];
    end
  end
 

  //uncomment the test pattern generator for the latter portion of part 1
  //and use it to drive tp_r,g, and b once you know that your video
  //pipeline is working (by seeing the 6.205 pink color)
  
  // test_pattern_generator mtpg(
  //     .sel_in(sw[1:0]),
  //     .hcount_in(hcount),
  //     .vcount_in(vcount),
  //     .red_out(tp_r),
  //     .green_out(tp_g),
  //     .blue_out(tp_b));
  
 
  // //uncomment for Part 2 of lab!:
  
  // shape_party msp (
  //     .clk_in(clk_pixel),
  //     .rst_in(sys_rst),
  //     .b_con_in(sw[15:12]),
  //     .c_con_in(sw[11:8]),
  //     .nf_in(new_frame),
  //     .hcount_in(hcount),
  //     .vcount_in(vcount),
  //     .red_out(sp_r),
  //     .green_out(sp_g),
  //     .blue_out(sp_b));
 
  // always_comb begin
  //   if (~sw[2])begin //if switch 2 pushed use shapes signal from part 2, else defaults
  //     red = tp_r;
  //     green = tp_g;
  //     blue = tp_b;
  //   end else begin
  //     red = sp_r;
  //     green = sp_g;
  //     blue = sp_b;
  //   end
  // end
 
  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic tmds_signal [2:0]; //output of each TMDS serializer!
 
  //three tmds_encoders (blue, green, red)
  //note green should have no control signal like red
  //the blue channel DOES carry the two sync signals:
  //  * control_in[0] = horizontal sync signal
  //  * control_in[1] = vertical sync signal
 
  localparam COLOR_LATENCY = 5; // 2 from memory read, 3 from color conversion
  logic [COLOR_LATENCY-1:0] active_draw_pipe;
  logic [COLOR_LATENCY-1:0] hor_sync_pipe;
  logic [COLOR_LATENCY-1:0] vert_sync_pipe;
  always_ff @(posedge clk_pixel) begin
    active_draw_pipe <= {active_draw, active_draw_pipe[COLOR_LATENCY-1:1]};
    hor_sync_pipe <= {hor_sync, hor_sync_pipe[COLOR_LATENCY-1:1]};
    vert_sync_pipe <= {vert_sync, vert_sync_pipe[COLOR_LATENCY-1:1]};
  end

  tmds_encoder tmds_red(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(red),
      .control_in(2'b0),
      .ve_in(active_draw_pipe[0]),
      .tmds_out(tmds_10b[2]));

  tmds_encoder tmds_green(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(green),
      .control_in(2'b0),
      .ve_in(active_draw_pipe[0]),
      .tmds_out(tmds_10b[1]));

  tmds_encoder tmds_blue(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(blue),
      .control_in({hor_sync_pipe[0], vert_sync_pipe[0]}),
      .ve_in(active_draw_pipe[0]),
      .tmds_out(tmds_10b[0]));
 
  //three tmds_serializers (blue, green, red):
  tmds_serializer red_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst),
      .tmds_in(tmds_10b[2]),
      .tmds_out(tmds_signal[2]));
      
  tmds_serializer green_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst),
      .tmds_in(tmds_10b[1]),
      .tmds_out(tmds_signal[1]));
      
  tmds_serializer blue_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst),
      .tmds_in(tmds_10b[0]),
      .tmds_out(tmds_signal[0]));
 
  //output buffers generating differential signals:
  //three for the r,g,b signals and one that is at the pixel clock rate
  //the HDMI receivers use recover logic coupled with the control signals asserted
  //during blanking and sync periods to synchronize their faster bit clocks off
  //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
  //the slower 74.25 MHz clock)
  OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));
 
endmodule // top_level
`default_nettype wire