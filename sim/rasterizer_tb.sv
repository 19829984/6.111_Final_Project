`timescale 1ns / 1ps
`default_nettype none

module rasterizer_tb();

logic clk_in;
logic rst_in;
logic start_render;
logic drawing, done;
logic signed [31:0] x_in, y_in, z_in;
logic signed [3:0][3:0][32-1:0] view_matrix;
logic [31:0] x, y;

  
  rasterizer #(.COORD_WIDTH(32), .DEPTH_BIT_WIDTH(16)) rasterize (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start(start_render),
    .x_in(x_in),
    .y_in(y_in),
    .z_in(z_in),
    .view_matrix(view_matrix),
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
    x_in = 32'hFFFF0628;
    y_in = 32'hFFFFF156;
    z_in = 32'hFFFEC464;
    view_matrix[0][0] = 32'h00010000; // 1 in Q16.16
    view_matrix[0][1] = 0;
    view_matrix[0][2] = 0;
    view_matrix[0][3] = x_in;
    view_matrix[1][0] = 0;
    view_matrix[1][1] = 32'h00010000;
    view_matrix[1][2] = 0;
    view_matrix[1][3] = y_in;
    view_matrix[2][0] = 0;
    view_matrix[2][1] = 0; 
    view_matrix[2][2] = 32'h00010000;
    view_matrix[2][3] = z_in; //-6
    view_matrix[3][0] = 0; 
    view_matrix[3][1] = 0;
    view_matrix[3][2] = 0; 
    view_matrix[3][3] = 32'h00010000;
    #5;
    rst_in = 1;
    #10;
    rst_in = 0;
    #20;
    start_render = 1;
    #10;
    start_render = 0;
    #500000;
    $display("Simulation finished");
    $finish;
  end
endmodule
`default_nettype wire