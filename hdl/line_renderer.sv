// `timescale 1ns / 1ps
// `default_nettype none

// module line_renderer #(
//     parameter COORD_WIDTH = 16
//     )(
//         input wire clk_in,
//         input wire rst_in,
//         input wire oe,
//         input wire start_draw,
//         input wire signed [COORD_WIDTH-1:0] x0, y0,
//         input wire signed [COORD_WIDTH-1:0] x1, y1,
//         output logic signed [COORD_WIDTH-1:0] x, y,
//         output logic drawing,
//         output logic done
//     );

// logic draw_start, draw_done;

// enum {IDLE, INIT, DRAW, DONE} state;
// always_ff @(posedge clk_in) begin

// end

// bresenhamLine #(.COORD_WIDTH(COORD_WIDTH)) draw_bresenham (
//     .clk_in(clk_in),
//     .rst_in(rst_in),
//     .start_draw(draw_start),
//     .oe(oe),
//     .x0(x0),
//     .y0(y0),
//     .x1(x1),
//     .y1(y1),
//     .x(x),
//     .y(y),
//     .drawing(drawing),
//     .busy(),
//     .done(draw_done)
// )

// endmodule

// `default_nettype wire