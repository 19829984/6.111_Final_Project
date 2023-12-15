`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //crystal reference clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches
  output logic [15:0] led, //16 green output LEDs (located right above switches)
  output logic [2:0] rgb0, //rgb led
  output logic [2:0] rgb1, //rgb led
  output logic [3:0] ss0_an,//anode control for upper four digits of seven-seg display
  output logic [3:0] ss1_an,//anode control for lower four digits of seven-seg display
  output logic [6:0] ss0_c, //cathode controls for the segments of upper four digits
  output logic [6:0] ss1_c, //cathod controls for the segments of lower four digits
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

  //clock manager...creates 74.25 MHz and 5 times 74.25 MHz for pixel and TMDS
  hdmi_clk_wiz_720p mhdmicw (
      .reset(0),
      .locked(locked),
      .clk_ref(clk_100mhz),
      .clk_pixel(clk_pixel),
      .clk_tmds(clk_5x),
      .clk_sys(sys_clk));
 
  //7-segment display-related concepts:
  logic [31:0] val_to_display; //either the spi data or the btn_count data (default)
  logic [6:0] ss_c; //used to grab output cathode signal for 7s leds
 
  seven_segment_controller mssc(.clk_in(clk_pixel),
                                .rst_in(sys_rst),
                                .val_in(val_to_display),
                                .cat_out(ss_c),
                                .an_out({ss0_an, ss1_an}));
  assign ss0_c = ss_c; //control upper four digit's cathodes!
  assign ss1_c = ss_c; //same as above but for lower four digits!


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

  localparam COORD_WIDTH = 32;
  logic signed [COORD_WIDTH-1:0] x, y;
  logic drawing;

  // Double Frame Buffer and its state machine
  localparam FB_BIT_WIDTH = 8;
  localparam FB_WIDTH = 320;
  localparam FB_HEIGHT = 180;
  localparam FB_NUM_PIXELS = FB_WIDTH * FB_HEIGHT;
  localparam FB_ADDR_WIDTH = $clog2(FB_NUM_PIXELS);
  logic [FB_BIT_WIDTH-1:0] fb_read, fb_read_1, fb_read_2;
  logic [FB_BIT_WIDTH-1:0] fb_write_color, fb_clear_color, fb_render_color;
  logic [FB_ADDR_WIDTH-1:0] fb_write_addr, fb_clear_addr, fb_render_addr;
  logic [FB_ADDR_WIDTH-1:0] fb_read_addr;
  logic fb_we, fb_front;

  localparam DEPTH_BIT_WIDTH = 16;
  logic [DEPTH_BIT_WIDTH-1:0] depth_read;
  logic [DEPTH_BIT_WIDTH-1:0] depth_write_num;
  logic [FB_ADDR_WIDTH-1:0] depth_write_addr;
  logic [FB_ADDR_WIDTH-1:0] depth_read_addr;
  logic dp_we, dp_re;
  assign depth_write_addr = fb_write_addr;

  logic [DEPTH_BIT_WIDTH-1:0] raster_depth;
  logic [DEPTH_BIT_WIDTH-1:0] clearing_depth;
  assign depth_write_num = fb_state == CLEARING ? clearing_depth : raster_depth;

  assign fb_read_addr = hcount_scaled + FB_WIDTH*vcount_scaled;
  assign fb_render_addr = x + FB_WIDTH*y;

  // piped vars
  logic fb_we_piped;
  logic dp_we_piped;
  logic dp_re_piped;
  logic fb_front_piped;
  logic [FB_ADDR_WIDTH-1:0] fb_write_addr_piped;
  logic [FB_BIT_WIDTH-1:0] fb_write_color_piped;
  logic [FB_ADDR_WIDTH-1:0] depth_write_addr_piped;
  logic [DEPTH_BIT_WIDTH-1:0] depth_write_num_piped;
  logic [FB_ADDR_WIDTH-1:0] depth_read_addr_piped;

  logic drawing_store;

  // Frame Buffer for 640x360 8 bit frame
  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(FB_BIT_WIDTH),
    .RAM_DEPTH(FB_NUM_PIXELS))
    frame_buffer_1 (
    .addra(fb_write_addr_piped), //pixels are stored using this math
    .clka(clk_pixel),
    .wea(fb_we_piped && fb_front_piped),
    .dina(fb_write_color_piped),
    .ena(1'b1),
    .regcea(1'b1),
    .rsta(sys_rst),
    .douta(), //never read from this side
    .addrb(fb_read_addr),//transformed lookup pixel
    .dinb(8'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(valid_scaled_addr),
    .rstb(sys_rst),
    .regceb(1'b1),
    .doutb(fb_read_1)
  );

  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(FB_BIT_WIDTH),
    .RAM_DEPTH(FB_NUM_PIXELS))
    frame_buffer_2 (
    .addra(fb_write_addr_piped), //pixels are stored using this math
    .clka(clk_pixel),
    .wea(fb_we_piped && ~fb_front_piped),
    .dina(fb_write_color_piped),
    .ena(1'b1),
    .regcea(1'b1),
    .rsta(sys_rst),
    .douta(), //never read from this side
    .addrb(fb_read_addr),//transformed lookup pixel
    .dinb(8'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(valid_scaled_addr),
    .rstb(sys_rst),
    .regceb(1'b1),
    .doutb(fb_read_2)
  );
  
  // Data stored in Q8.8 format
  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(DEPTH_BIT_WIDTH),
    .RAM_DEPTH(FB_NUM_PIXELS))
    depth_buffer (
     .addra(depth_write_addr_piped), 
     .clka(clk_pixel),
     .wea(dp_we_piped),
     .dina(depth_write_num_piped),
     .ena(1'b1),
     .regcea(1'b1),
     .rsta(sys_rst),
     .douta(), //never read from this side
     .addrb(depth_read_addr_piped),
     .dinb(16'b0),
     .clkb(clk_pixel),
     .web(1'b0),
     .enb(dp_re_piped),
     .rstb(sys_rst),
     .regceb(1'b1),
     .doutb(depth_read)
  );

  depth_writer #(.FB_BIT_WIDTH(FB_BIT_WIDTH), .DEPTH_BIT_WIDTH(DEPTH_BIT_WIDTH), .FB_ADDR_WIDTH(FB_ADDR_WIDTH)) depth_pipe (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .render_depth_buffer(sw[0]),
    .drawing_in(drawing_store),
    .fb_we_in(fb_we), 
    .dp_we_in(dp_we), 
    .dp_re_in(dp_re), 
    .fb_front_in(fb_front),
    .fb_write_in(fb_write_addr),
    .fb_value_in(fb_write_color),
    .dp_read_in(depth_read),
    .dp_write_in(depth_write_addr),
    .dp_value_in(depth_write_num),
    .fb_we_out(fb_we_piped), 
    .dp_we_out(dp_we_piped), 
    .dp_re_out(dp_re_piped), 
    .fb_front_out(fb_front_piped),
    .fb_write_out(fb_write_addr_piped),
    .fb_value_out(fb_write_color_piped),
    .dp_read_addr_out(depth_read_addr_piped),
    .dp_write_out(depth_write_addr_piped),
    .dp_value_out(depth_write_num_piped)
  );


  // WORLD LOGIC
  localparam WORLD_SIZE=128;
  localparam WORLD_BITS=$clog2(WORLD_SIZE);

  logic signed [COORD_WIDTH-1:0] x_input;
  logic signed [COORD_WIDTH-1:0] y_input;
  logic signed [COORD_WIDTH-1:0] z_input;
  logic signed [COORD_WIDTH-1:0] rot_angle;
  logic signed [COORD_WIDTH-1:0] side_angle;
  logic signed [2:0][COORD_WIDTH-1:0] velocity; // unused
  logic signed [2:0][COORD_WIDTH-1:0] acc; // unused

  logic signed [3*COORD_WIDTH/2:0] world_read;
  logic [WORLD_BITS-1:0] world_read_addr;
  logic [WORLD_BITS-1:0] world_read_addr_draw;
  logic [WORLD_BITS-1:0] world_read_addr_update;
  assign world_read_addr = fb_state == UPDATE ? world_read_addr_update : world_read_addr_draw;

  logic signed [COORD_WIDTH-1:0] x_corner;
  logic signed [COORD_WIDTH-1:0] y_corner;
  logic signed [COORD_WIDTH-1:0] z_corner;

  logic world_drawn;
  logic signed [1:0][5:0] world_populator;
  always_ff @(posedge clk_pixel) begin
    if (new_frame) begin
        if (world_populator[0] < 63) begin // draw 16 cubes
            world_drawn <= 0;
            world_populator[0] = world_populator[0] + 1;
            world_populator[1] = world_populator[1] + 1;
        end else begin
            world_drawn <= 1;
        end
    end
  end
  logic [WORLD_BITS-1:0] world_write_addr;
  logic [WORLD_BITS-1:0] world_write_addr_update;
  logic signed [3*COORD_WIDTH/2:0] world_write_val;
  logic signed [3*COORD_WIDTH/2:0] world_write_val_update;
  assign world_write_addr = world_drawn ? world_write_addr_update : world_populator[0];
  assign world_write_val = world_drawn ? world_write_val_update : {1'b1, 13'b0, world_populator[1][5:4], 1'b0, 13'b0, world_populator[1][3:2], 1'b0, 13'b0, world_populator[1][1:0], 1'b0};
  //assign world_write_val = world_drawn ? world_write_val_update : {1'b1, 14'b0, world_populator[1][5:4], 14'b1, world_populator[1][3:2], 14'b0, world_populator[1][1:0]};

  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(3*COORD_WIDTH/2+1), // valid bit then x y z ints
    .RAM_DEPTH(WORLD_SIZE))
    world_bram (
    .addra(world_write_addr), 
    .clka(clk_pixel),
    .wea(1'b1),
    .dina(world_write_val),
    .ena(1'b1),
    .regcea(1'b1),
    .rsta(sys_rst),
    .douta(), //never read from this side
    .addrb(world_read_addr),
    .web(1'b0),
    .dinb(8'b0),
    .clkb(clk_pixel),
    .enb(1'b1),
    .rstb(sys_rst),
    .regceb(1'b1),
    .doutb(world_read)
  );

  logic signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix;
  logic signed [2:0][COORD_WIDTH-1:0] forward_vec;
  logic start_view_matrix;
  logic view_done;
  view_matrix_calculator #(.COORD_WIDTH(COORD_WIDTH)) view_matrix_calc (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .start(start_view_matrix),
    .x_in(x_input),
    .y_in(y_input),
    .z_in(z_input),
    .rot_angle(rot_angle),
    .side_angle(side_angle),
    .done(view_done),
    .view_matrix(view_matrix),
    .forward_vec(forward_vec)
  );

  enum {IDLE, INIT, CLEARING, DRAW, UPDATE, DONE} fb_state;
  logic start_render;
  logic render_done;

  logic start_update;
  logic update_busy;
  logic update_done;

  logic [2:0] state_status;
  logic[8:0] test_incr;
  always_ff @(posedge clk_pixel) begin
    if (sys_rst) begin
      fb_state <= IDLE;
    end else begin
      case (fb_state)
        IDLE: begin
          if (new_frame) begin
            fb_state <= INIT;
          end
          state_status <= 0;
        end
        INIT: begin
          fb_state <= CLEARING;
          fb_front <= ~fb_front;
          fb_clear_addr <= 0;
          fb_clear_color <= 8'h00;
          state_status <= 1;

          // depth_write_addr <= 0;
          clearing_depth <= 16'hFFFF;
          // clearing_depth <= 16'h0000 + test_incr;
          // test_incr <= 0;//test_incr + 1;
          //depth_write_num <= 16'hFFFF;
        end
        CLEARING: begin
          fb_clear_addr <= fb_clear_addr + 1;
          // clearing_depth <= 16'h0000 + test_incr;
          // test_incr <= test_incr + 1;
          // depth_write_addr <= depth_write_addr + 1;
          if (fb_clear_addr == FB_NUM_PIXELS - 1) begin
            fb_state <= DRAW;
            start_view_matrix <= 1;
          end
          state_status <= 2;
        end
        DRAW: begin
          start_render <= view_done;
          if (render_done) begin
            fb_state <= UPDATE;
            start_update <= 1;
          end

          start_view_matrix <= 0;
          state_status <= 3;
        end
        UPDATE: begin
            if (update_busy) begin
                start_update <= 0;
            end
            if (update_done) begin
                fb_state <= DONE;
            end
            state_status <= 4;
        end
        DONE: begin
          start_render <= 0;
          fb_state <= IDLE;
          state_status <= 5;
        end
        default: begin
          if (new_frame) begin
            fb_state <= INIT;
          end
        end
      endcase
    end
  end

  // control world state
  world_changer #(.COORD_WIDTH(COORD_WIDTH), .WORLD_BITS(WORLD_BITS), .WORLD_SIZE(WORLD_SIZE)) world_controller (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .start(start_update),
    .sw(sw),
    .btn(btn),
    .forward_vec(forward_vec),
    .world_read(world_read),
    .looked_at_cube(looked_at_cube),
    .looked_at_normal(looked_at_normal),
    .x_input(x_input),
    .y_input(y_input),
    .z_input(z_input),
    .rot_angle(rot_angle),
    .side_angle(side_angle),
    .world_read_addr(world_read_addr_update),
    .world_write_addr(world_write_addr_update),
    .world_write(world_write_val_update),
    .busy(update_busy),
    .done(update_done)
  );

  always_ff @(posedge clk_pixel) begin
    dp_re <= 1;

    fb_write_addr <= (fb_state == CLEARING) ? fb_clear_addr : fb_render_addr;
    fb_write_color <= (fb_state == CLEARING) ? fb_clear_color : fb_render_color;
    fb_read <= fb_front ? fb_read_2 : fb_read_1;
    fb_we <= (fb_state == CLEARING) || (drawing);
    dp_we <= (fb_state == CLEARING) || (drawing);
    drawing_store <= drawing;
  end

  logic [2:0] raster_state;
  logic [31:0] raster_test;
  logic signed [31:0] u, v, w;
  logic [1:0] proj_status;
  logic [1:0][31:0] cycles_per_frame;
  logic cycles;

  // debugging
  always_ff @(posedge clk_pixel) begin
    //val_to_display[2:0] <= state_status;
    //val_to_display[5:4] <= proj_status;
    //val_to_display[10:8] <= raster_state;
    if (sw[15] && sw[14] && sw[13]) begin
      val_to_display <= looked_at_cube;
    end else if (sw[14] && sw[15]) begin
      val_to_display <= raster_depth;
    end else if (sw[14]) begin
      val_to_display <= y_input;
    end else if (sw[1] && sw[13]) begin
      val_to_display <= cycles_per_frame[1];
    end else if (sw[1]) begin
      //val_to_display <= cycles;
      val_to_display <= rot_angle;
    end else if (sw[13]) begin
      //val_to_display <= z_input;
      val_to_display <= world_write_addr;
    end else if (sw[15]) begin
      //val_to_display <= x_input;
      val_to_display <= world_read[48:33];
    end else begin
    // Display average cycles per frame over 2 frames.
    val_to_display <= (cycles_per_frame[0] + cycles_per_frame[1]) >> 1;
    end
  end

  // Rendering
  localparam NORMAL_WIDTH = 2;
  logic [6:0] world_debug;
  logic [WORLD_BITS-1:0] looked_at_cube; //TODO: Fix this
  logic [2:0][NORMAL_WIDTH-1:0] looked_at_normal;
  world_drawer #(.COORD_WIDTH(COORD_WIDTH), .DEPTH_BIT_WIDTH(DEPTH_BIT_WIDTH), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT), .FB_BIT_WIDTH(FB_BIT_WIDTH), .WORLD_SIZE(WORLD_SIZE), .WORLD_BITS(WORLD_BITS), .NORMAL_WIDTH(NORMAL_WIDTH)) world_draw (
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .start(start_render),
    .world_read(world_read),
    .view_matrix(view_matrix),
    .world_read_addr(world_read_addr_draw),
    .x_cor(x_corner),
    .y_cor(y_corner),
    .z_cor(z_corner),
    .test(world_debug),
    .x(x),
    .y(y),
    .depth(raster_depth),
    .color(fb_render_color),
    .looked_at_cube(looked_at_cube),
    .looked_at_normal(looked_at_normal),
    .drawing(drawing),
    .busy(),
    .done(render_done)
  );

  always_ff @(posedge clk_pixel) begin
    cycles_per_frame[1] <= cycles_per_frame[1] + 1;
    cycles <= cycles + 1;
    if (render_done) begin
        cycles <= 0;
        cycles_per_frame <= {0, cycles_per_frame[1]};
    end
  end
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
  
  // color_conversion col_converter(
  //   .clk_in(clk_pixel),
  //   .red_in(fb_read),
  //   .green_in(fb_read),
  //   .blue_in(fb_read),
  //   .red_out(converted_r),
  //   .green_out(converted_g),
  //   .blue_out(converted_b)
  // );

  always_comb begin
    if (~sw[2])begin //if switch 2 pushed use shapes signal from part 2, else defaults
      red = tp_r;
      green = tp_g;
      blue = tp_b;
    end else begin
      // red = converted_r;
      // green = converted_g;
      // blue = converted_b;
      red = fb_read;
      green = fb_read;
      blue = fb_read;
    end
  end
 
  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic tmds_signal [2:0]; //output of each TMDS serializer!
 
  //three tmds_encoders (blue, green, red)
  //note green should have no control signal like red
  //the blue channel DOES carry the two sync signals:
  //  * control_in[0] = horizontal sync signal
  //  * control_in[1] = vertical sync signal
 
  localparam COLOR_LATENCY = 6; // 1 from choosing between two buffers, 2 from memory read, 3 from color conversion
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
