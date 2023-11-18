`timescale 1ns / 1ps
`default_nettype none

module dot_product_tb();

  logic clk_in;
  logic rst_in;
  
logic signed [31:0] x0, x1, x2, x3; //Q16.16
logic signed [31:0] y0, y1, y2, y3; //Q16.16
logic signed [31:0] out; //Q16.16


dotProduct#(.FIXED_POINT(1), .WIDTH(32)) dot_product  (
    .clk_in(clk_in),
    .x0(x0),
    .x1(x1),
    .x2(x2),
    .x3(x3),
    .y0(y0),
    .y1(y1),
    .y2(y2),
    .y3(y3),
    .out(out)
);

localparam SF = $pow(2.0, -16.0);
  always begin
      #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
      clk_in = !clk_in;
  end
  //initial block...this is our test simulation
  initial begin
    $dumpfile("dot_product_tb.vcd"); //file to store value change dump (vcd)
    $dumpvars(0,dot_product_tb);
    $display("Starting Sim"); //print nice message at start
    clk_in = 0;
    rst_in = 0;
    x0 = 32'b0000_0000_0000_0001_0000_0000_0000_0000; // 1 in Q16.16
    x1 = 32'b0000_0000_0000_0010_0000_0000_0000_0000; // 2
    x2 = 32'b0000_0000_0000_0011_0000_0000_0000_0000; // 3
    x3 = 32'b0000_0000_0000_0100_0000_0000_0000_0000; // 4
    y0 = 32'b0000_0000_0000_0001_1000_0000_0000_0000; // 1.5
    y1 = 32'b0000_0000_0000_0100_1100_0000_0000_0000; // 4.75
    y2 = 32'b0000_0000_0000_1000_1101_0000_0000_0000; // 8.8125
    y3 = 32'b0000_0000_0001_0000_0000_0000_0000_0000; // 16.0
    // Wait 1 cycle
    #10;
    x0 = 32'b1111_1111_1111_1010_1000_0000_0000_0000; // -5.5
    // set y3 to -16.5 in Q16.16
    y3 = 32'b1111_1111_1110_1111_1000_0000_0000_0000; // -16.5
    // Print inputs
    // $display("x0 = %f", $itor(x0) * SF);
    // $display("x1 = %f", $itor(x1) * SF);
    // $display("x2 = %f", $itor(x2) * SF);
    // $display("x3 = %f", $itor(x3) * SF);
    // $display("y0 = %f", $itor(y0) * SF);
    // $display("y1 = %f", $itor(y1) * SF);
    // $display("y2 = %f", $itor(y2) * SF);
    // $display("y3 = %f", $itor(y3) * SF);
    #20; // Wait 2 cycle
    // 1*1.5+2*4.75+3*8.8125+4*16 = 101.4375
    $display("out = %f", $itor(out) * SF);
    $display("Expected out = %f", 101.4375);
    #20; // Wait 1 cycle
    // -5.5*1.5+2*4.75+3*8.8125+4*-16.5 = -38.3125
    $display("out = %f", $itor(out) * SF);
    $display("Expected out = %f", -38.3125);
    
    $display("Simulation finished");
    $finish;
  end
endmodule
`default_nettype wire