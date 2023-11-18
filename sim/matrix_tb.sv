`timescale 1ns / 1ps
`default_nettype none

module matrix_tb();

logic clk_in;
logic rst_in;
  
logic signed [3:0][3:0][31:0] m1;
logic signed [3:0][3:0][31:0] m2;
logic signed [3:0][3:0][31:0] m_out;
logic start_matrix_multiply;
logic busy, done;

matrixMultiply4x4#(.FIXED_POINT(1), .WIDTH(32)) matrix_multiply  (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start(start_matrix_multiply),
    .m1(m1),
    .m2(m2),
    .m_out(m_out),
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
    $dumpfile("matrix_tb.vcd"); //file to store value change dump (vcd)
    $dumpvars(0,matrix_tb);
    $display("Starting Sim"); //print nice message at start
    clk_in = 0;
    rst_in = 0;
    start_matrix_multiply = 0;
    #5;
    rst_in = 1;
    #5;
    rst_in = 0;
    #20;

    // In Q16.16 fixed point binary, init m1 matrix to
    // {{1, 2, 3, 4}, {5, 6.5, 7.75, 8}, {9, 10, 11.25, 12}, {13, 14.125, 15, 16}}
    m1[0][0] = 32'b0000_0000_0000_0001_0000_0000_0000_0000; // 1 in Q16.16
    m1[0][1] = 32'b0000_0000_0000_0010_0000_0000_0000_0000; // 2
    m1[0][2] = 32'b0000_0000_0000_0011_0000_0000_0000_0000; // 3
    m1[0][3] = 32'b0000_0000_0000_0100_0000_0000_0000_0000; // 4
    m1[1][0] = 32'b0000_0000_0000_0101_0000_0000_0000_0000; // 5
    m1[1][1] = 32'b0000_0000_0000_0110_1000_0000_0000_0000; // 6.5
    m1[1][2] = 32'b0000_0000_0000_0111_1100_0000_0000_0000; // 7.75
    m1[1][3] = 32'b0000_0000_0000_1000_0000_0000_0000_0000; // 8
    m1[2][0] = 32'b0000_0000_0000_1001_0000_0000_0000_0000; // 9
    m1[2][1] = 32'b0000_0000_0000_1010_0000_0000_0000_0000; // 10
    m1[2][2] = 32'b0000_0000_0000_1011_0100_0000_0000_0000; // 11.25
    m1[2][3] = 32'b0000_0000_0000_1100_0000_0000_0000_0000; // 12
    m1[3][0] = 32'b0000_0000_0000_1101_0000_0000_0000_0000; // 13
    m1[3][1] = 32'b0000_0000_0000_1110_0010_0000_0000_0000; // 14.125
    m1[3][2] = 32'b0000_0000_0000_1111_0000_0000_0000_0000; // 15
    m1[3][3] = 32'b0000_0000_0001_0000_0000_0000_0000_0000; // 16
    
    // In Q16.16 fixed point binary, init m2 matrix to
    // {{1, 2, -3.5, 4}, {5, 6.5, 7.75, 8}, {100.5, -10.25, 11.25, 12}, {-13, 14.125, 15, -16}}
    m2[0][0] = 32'b0000_0000_0000_0001_0000_0000_0000_0000; // 1 in Q16.16
    m2[0][1] = 32'b0000_0000_0000_0010_0000_0000_0000_0000; // 2
    m2[0][2] = 32'b1111_1111_1111_1100_1000_0000_0000_0000; // -3.5
    m2[0][3] = 32'b0000_0000_0000_0100_0000_0000_0000_0000; // 4
    m2[1][0] = 32'b0000_0000_0000_0101_0000_0000_0000_0000; // 5
    m2[1][1] = 32'b0000_0000_0000_0110_1000_0000_0000_0000; // 6.5
    m2[1][2] = 32'b0000_0000_0000_0111_1100_0000_0000_0000; // 7.75
    m2[1][3] = 32'b0000_0000_0000_1000_0000_0000_0000_0000; // 8
    m2[2][0] = 32'b0000_0000_0110_0100_1000_0000_0000_0000; // 100.5
    m2[2][1] = 32'b1111_1111_1111_0101_1100_0000_0000_0000; // -10.25
    m2[2][2] = 32'b0000_0000_0000_1011_0100_0000_0000_0000; // 11.25
    m2[2][3] = 32'b0000_0000_0000_1100_0000_0000_0000_0000; // 12
    m2[3][0] = 32'b1111_1111_1111_0011_0000_0000_0000_0000; // -13
    m2[3][1] = 32'b0000_0000_0000_1110_0010_0000_0000_0000; // 14.125
    m2[3][2] = 32'b0000_0000_0000_1111_0000_0000_0000_0000; // 15
    m2[3][3] = 32'b1111_1111_1111_0000_0000_0000_0000_0000; // -16

    // Expected result of m1 x m2
    // {{260.5, 40.75, 105.75, -8}, {712.375, 85.8125, 240.063, 37}, {1033.63, 137.188, 352.563, 59}, {1383.13, 190.063, 472.710, 89}}

    // Wait 1 cycle
    #10;
    start_matrix_multiply = 1;
    #10;
    start_matrix_multiply = 0;
    #120; // Wait 7 cycle
    $display("Done: %d", done);
    $display("Expected: {{260.5, 40.75, 105.75, -8}, {712.375, 85.8125, 240.063, 37}, {1033.63, 137.188, 352.563, 59}, {1383.13, 190.063, 472.719, 89}}");
    $display("Actual  : {{%.5f, %.5f, %.5f, %.5f}, {%.5f, %.5f, %.5f, %.5f}, {%.5f, %.5f, %.5f, %.5f}, {%.5f, %.5f, %.5f, %.5f}}",
        $itor(m_out[0][0]) * SF, $itor(m_out[0][1]) * SF, $itor(m_out[0][2]) * SF, $itor(m_out[0][3]) * SF,
        $itor(m_out[1][0]) * SF, $itor(m_out[1][1]) * SF, $itor(m_out[1][2]) * SF, $itor(m_out[1][3]) * SF,
        $itor(m_out[2][0]) * SF, $itor(m_out[2][1]) * SF, $itor(m_out[2][2]) * SF, $itor(m_out[2][3]) * SF,
        $itor(m_out[3][0]) * SF, $itor(m_out[3][1]) * SF, $itor(m_out[3][2]) * SF, $itor(m_out[3][3]) * SF);
    $display("Simulation finished");
    $finish;
  end
endmodule
`default_nettype wire