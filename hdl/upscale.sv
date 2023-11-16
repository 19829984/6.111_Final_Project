`timescale 1ns / 1ps
`default_nettype none

module upScale(
  input wire [10:0] hcount_in,
  input wire [9:0] vcount_in,
  output logic [10:0] scaled_hcount_out,
  output logic [9:0] scaled_vcount_out,
  output logic valid_addr_out
);
  always_comb begin
    valid_addr_out = hcount_in < 1280 && vcount_in < 720;
    scaled_hcount_out = hcount_in >> 2;
    scaled_vcount_out = vcount_in >> 2;
  end
endmodule


`default_nettype wire

