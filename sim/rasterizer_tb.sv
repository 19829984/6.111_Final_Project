`timescale 1ns / 1ps
`default_nettype none

module rasterizer_tb();

logic clk_in;
logic rst_in;
logic start_render;
logic drawing, done;
logic [31:0] x, y;
  
  rasterizer #(.COORD_WIDTH(32)) rasterize (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start(start_render),
    .x(x),
    .y(y),
    .drawing(drawing),
    .busy(),
    .done(done)
  );

  always begin
      #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
      clk_in = !clk_in;
  end
  //initial block...this is our test simulation
  initial begin
    $dumpfile("rasterizer_tb.vcd"); //file to store value change dump (vcd)
    $dumpvars(0,rasterizer_tb);
    $display("Starting Sim"); //print nice message at start
    clk_in = 0;
    rst_in = 0;
    start_render = 0;
    #5;
    rst_in = 1;
    #10;
    rst_in = 0;
    #20;
    start_render = 1;
    #10;
    start_render = 0;
    #300000;
    $display("Simulation finished");
    $finish;
  end
endmodule
`default_nettype wire