`timescale 1ns / 1ps
`default_nettype none

// 3 Cycle Delay
module dotProduct #(parameter FIXED_POINT = 0, parameter WIDTH = 32) (
    input wire clk_in,
    
    input wire signed [WIDTH-1:0] x0, x1, x2, x3,
    
    input wire signed [WIDTH-1:0] y0, y1, y2, y3,

    output logic signed [WIDTH-1:0] out
);
localparam FP_HIGH = WIDTH*2 - WIDTH/2 - 1;
localparam FP_LOW = WIDTH/2;;
(* dont_touch = "yes" *) logic signed [2*WIDTH-1:0] xy0, xy1, xy2, xy3;
logic signed [WIDTH-1:0] sum, sum_01, sum_23;

assign out = sum;

always_ff @(posedge clk_in) begin
    // Step 1
    xy0 <= x0 * y0;
    xy1 <= x1 * y1;
    xy2 <= x2 * y2;
    xy3 <= x3 * y3;

    // Step 2
    if (FIXED_POINT) begin
        sum_01 <= xy0[FP_HIGH:FP_LOW] + xy1[FP_HIGH:FP_LOW];
        sum_23 <= xy2[FP_HIGH:FP_LOW] + xy3[FP_HIGH:FP_LOW];
    end
    else begin
        sum_01 <= xy0 + xy1;
        sum_23 <= xy2 + xy3;
    end
    
    // Step 3
    sum <= sum_01 + sum_23;
end
endmodule
`default_nettype wire