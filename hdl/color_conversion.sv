`timescale 1ns / 1ps
`default_nettype none

//Converts 565 RGB to 888 RGB with 3 cycle delay
module color_conversion 
(
    input wire clk_in,
    input wire [4:0] red_in,
    input wire [5:0] green_in,
    input wire [4:0] blue_in,
    output wire [7:0] red_out,
    output wire [7:0] green_out,
    output wire [7:0] blue_out
);
    (* dont_touch = "yes" *) logic [15:0] r_multiply, g_multiply, b_multiply;
    (* dont_touch = "yes" *) logic [15:0] r_add, g_add, b_add;
    logic [7:0] red_shift, green_shift, blue_shift;
    assign red_out = red_shift;
    assign green_out = green_shift;
    assign blue_out = blue_shift;

    always_ff @(posedge clk_in) begin
        //Step 1
        r_multiply <= red_in * 527;
        g_multiply <= green_in * 259;
        b_multiply <= blue_in * 527;

        //Step 2
        r_add <= r_multiply + 23;
        g_add <= g_multiply + 33;
        b_add <= b_multiply + 23;

        //Step 3
        red_shift <= r_add >> 6;
        green_shift <= g_add >> 6;
        blue_shift <= b_add >> 6;
    end


endmodule
`default_nettype wire