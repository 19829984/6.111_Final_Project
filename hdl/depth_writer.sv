`timescale 1ns / 1ps
`default_nettype none

module depth_writer #(parameter FB_BIT_WIDTH = 16, parameter DEPTH_BIT_WIDTH = 16, parameter FB_ADDR_WIDTH = 100) (
    input wire clk_in,
    input wire rst_in,
    input wire render_depth_buffer,
    input wire drawing_in,
    input wire fb_we_in, 
    input wire dp_we_in, 
    input wire dp_re_in,
    input wire fb_front_in,
    input wire [FB_ADDR_WIDTH-1:0] fb_write_in,
    input wire [FB_BIT_WIDTH-1:0] fb_value_in,
    input wire [DEPTH_BIT_WIDTH-1:0] dp_read_in,
    input wire [FB_ADDR_WIDTH-1:0] dp_write_in,
    input wire [DEPTH_BIT_WIDTH-1:0] dp_value_in,
    output logic fb_we_out, 
    output logic dp_we_out, 
    output logic dp_re_out, 
    output logic fb_front_out,
    output logic [FB_ADDR_WIDTH-1:0] fb_write_out,
    output logic [FB_BIT_WIDTH-1:0] fb_value_out,
    output logic [FB_ADDR_WIDTH-1:0] dp_read_addr_out,
    output logic [FB_ADDR_WIDTH-1:0] dp_write_out,
    output logic [DEPTH_BIT_WIDTH-1:0] dp_value_out
);

    logic drawing_mid_1;
    logic fb_we_mid_1; 
    logic dp_we_mid_1; 
    logic fb_front_mid_1;
    logic [FB_ADDR_WIDTH-1:0] fb_write_mid_1;
    logic [FB_BIT_WIDTH-1:0] fb_value_mid_1;
    logic [FB_ADDR_WIDTH-1:0] dp_write_mid_1;
    logic [DEPTH_BIT_WIDTH-1:0] dp_value_mid_1;

    logic drawing_mid_2;
    logic fb_we_mid_2; 
    logic dp_we_mid_2; 
    logic fb_front_mid_2;
    logic [FB_ADDR_WIDTH-1:0] fb_write_mid_2;
    logic [FB_BIT_WIDTH-1:0] fb_value_mid_2;
    logic [FB_ADDR_WIDTH-1:0] dp_write_mid_2;
    logic [DEPTH_BIT_WIDTH-1:0] dp_value_mid_2;

    logic drawing_mid_3;
    logic fb_we_mid_3; 
    logic dp_we_mid_3; 
    logic fb_front_mid_3;
    logic [FB_ADDR_WIDTH-1:0] fb_write_mid_3;
    logic [FB_BIT_WIDTH-1:0] fb_value_mid_3;
    logic [FB_ADDR_WIDTH-1:0] dp_write_mid_3;
    logic [DEPTH_BIT_WIDTH-1:0] dp_value_mid_3;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            fb_we_out <= 0;
            dp_we_out <= 0;
            dp_re_out <= 0;
            fb_front_out <= 0;
            fb_write_out <= 0;
            fb_value_out <= 0;
            dp_read_addr_out <= 0;
            dp_write_out <= 0;
            dp_value_out <= 0;
        end else begin
            drawing_mid_1 <= drawing_in;
            fb_we_mid_1 <= fb_we_in;
            dp_we_mid_1 <= dp_we_in;
            fb_front_mid_1 <= fb_front_in;
            fb_write_mid_1 <= fb_write_in;
            fb_value_mid_1 <= fb_value_in;
            dp_write_mid_1 <= dp_write_in;
            dp_value_mid_1 <= dp_value_in;

            drawing_mid_2 <= drawing_mid_1;
            fb_we_mid_2 <= fb_we_mid_1;
            dp_we_mid_2 <= dp_we_mid_1;
            fb_front_mid_2 <= fb_front_mid_1;
            fb_write_mid_2 <= fb_write_mid_1;
            fb_value_mid_2 <= fb_value_mid_1;
            dp_write_mid_2 <= dp_write_mid_1;
            dp_value_mid_2 <= dp_value_mid_1;

            drawing_mid_3 <= drawing_mid_2;
            fb_we_mid_3 <= fb_we_mid_2;
            dp_we_mid_3 <= dp_we_mid_2;
            fb_front_mid_3 <= fb_front_mid_2;
            fb_write_mid_3 <= fb_write_mid_2;
            fb_value_mid_3 <= fb_value_mid_2;
            dp_write_mid_3 <= dp_write_mid_2;
            dp_value_mid_3 <= dp_value_mid_2;

            if (drawing_mid_3) begin
                if (dp_read_in < dp_value_mid_3) begin // don't write
                    fb_we_out <= 0;
                    dp_we_out <= 0;
                    dp_write_out <= dp_write_mid_3;
                    dp_value_out <= dp_read_in;
                end else begin // do write
                    fb_we_out <= fb_we_mid_3;
                    dp_we_out <= dp_we_mid_3;
                    fb_front_out <= fb_front_mid_3;
                    fb_write_out <= fb_write_mid_3;
                    // 16 bit to 8 bit conversion
                    if (render_depth_buffer) begin
                        fb_value_out <= dp_value_mid_3[15:8];
                    end else begin
                        fb_value_out <= fb_value_mid_3;
                    end
                    dp_write_out <= dp_write_mid_3;
                    dp_value_out <= dp_value_mid_3;
                end
            end else begin
                // if write-enabled, we're clearing, so
                // directly pipe everything
                fb_we_out <= fb_we_mid_3;
                dp_we_out <= dp_we_mid_3;
                fb_front_out <= fb_front_mid_3;
                fb_write_out <= fb_write_mid_3;
                fb_value_out <= fb_value_mid_3;
                dp_write_out <= dp_write_mid_3;
                dp_value_out <= dp_value_mid_3;
            end

            dp_read_addr_out <= fb_write_in;
            dp_re_out <= dp_re_in;
        end
    end
endmodule
`default_nettype wire
