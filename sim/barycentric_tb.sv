`timescale 1ns / 1ps
`default_nettype none

module barycentric_tb();

  logic clk_in;
  logic rst_in;
  
logic signed [2:0][31:0] p, a, b, c;
logic init, valid, valid_in, init_done, busy, done;

logic [31:0] u, v, w;

computeBarycentric #(.COORD_WIDTH(32)) barycentric (
  .clk_in(clk_in),
  .rst_in(rst_in),
  .p(p),
  .a(a),
  .b(b),
  .c(c),
  .valid_in(valid_in),
  .init(init),
  .u(u),
  .v(v),
  .w(w),
  .valid(valid),
  .init_done(init_done),
  .busy(busy),
  .done(done)
);

localparam SF = $pow(2.0, -16.0);
  always begin
      #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
      clk_in = !clk_in;
  end
  //initial block...this is our test simulation
  initial begin
    $dumpfile("barycentric_tb.vcd"); //file to store value change dump (vcd)
    $dumpvars(0,barycentric_tb);
    $display("Starting Sim"); //print nice message at start
    clk_in = 0;
    rst_in = 0;
    init = 0;
    valid_in = 0;
    p[0] = 32'h00000000;
    p[1] = 32'h00000000;
    p[2] = 32'h00000000;

    a[0] = 32'hffff0000;
    a[1] = 32'h00000000;
    a[2] = 32'hffff0000;

    b[0] = 32'h00010000;
    b[1] = 32'h00000000;
    b[2] = 32'hffff0000;

    c[0] = 32'h00010000;
    c[1] = 32'h00000000;
    c[2] = 32'h00010000;

    #10;
    rst_in = 1;
    #10;
    rst_in = 0;
    init = 1;
    #10;
    init = 0;
    #1000;
    p[2] = 32'hffff8000;
    p[0] = 32'h00008000;
    valid_in = 1;
    #10;
    valid_in = 0;
    #10;
    p[2] = 32'hffff8000;
    p[0] = 32'h00004000;
    valid_in = 1;
    #10;
    valid_in = 0;
    #10;
    p[2] = 32'h00008000;
    p[1] = 32'h00010000;
    p[0] = 32'h00002000;
    valid_in = 1;
    #10;
    valid_in = 0;
    #1000;
    $display("Simulation finished");
    $finish;
  end
endmodule
`default_nettype wire