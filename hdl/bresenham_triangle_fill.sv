`timescale 1ns / 1ps
`default_nettype none

module bresenhamTriangleFill #(parameter COORD_WIDTH = 16) (
    input wire clk_in,
    input wire rst_in,
    input wire start_draw,
    input wire oe,
    input wire signed [COORD_WIDTH-1:0] x0, y0,
    input wire signed [COORD_WIDTH-1:0] x1, y1,
    input wire signed [COORD_WIDTH-1:0] x2, y2,
    output logic signed [COORD_WIDTH-1:0] x, y,
    output logic drawing, // Essentially a valid_out signal
    output logic busy,
    output logic done
);

// Sorted vertices
logic signed [COORD_WIDTH-1:0] sorted_x0, sorted_y0, sorted_x1, sorted_y1, sorted_x2, sorted_y2;

// Registers for line drawers
// Longest line drawer (A)
logic signed [COORD_WIDTH-1:0] x0a, y0a, x1a, y1a, xa, ya; 
// Shortest line drawer (B)
logic signed [COORD_WIDTH-1:0] x0b, y0b, x1b, y1b, xb, yb; 
// Horizontal line drawer
logic signed [COORD_WIDTH-1:0] x0h, x1h, xh;

// Y value of last line drawn
logic signed [COORD_WIDTH-1:0] prev_y;

// X values of the endpoints of the last line drawn
logic signed [COORD_WIDTH-1:0] prev_xa, prev_xb;

// Line Drawer Control Signals
logic oe_a, oe_b, oe_h;
logic drawing_h;
logic busy_a, busy_b, busy_h;
logic drawing_third_edge;

// Pipeline these signals to account for delay in coordinate output
// such that they update the cycle after the final coordinate
logic busy_pipe, done_pipe;

always_ff @(posedge clk_in) begin
    x <= xh;
    y <= prev_y;
    drawing <= drawing_h;
    busy <= busy_pipe;
    done <= done_pipe;
end


/* SORT_0 to SORT_3 sorts the vertices by ascending y value.
* INIT_A to INIT_B1 initializes the line drawers with the sorted vertices.
* START_A, START_B, START_H starts the line drawers, acts like pulses.
* DRAW_EDGE waits til line drawers A and B have both advanced to the next y value or are not busy, then updates the horizontal drawer's input.
* DRAW_H_LINE waits til the horizontal drawer is done and updates the previous value variables.
*/
enum {IDLE, SORT_0, SORT_1, SORT_2, INIT_A, INIT_B0, INIT_B1, INIT_H,
        START_A, START_B, START_H, DRAW_EDGE, DRAW_H_LINE, DONE} state;
always_ff @(posedge clk_in) begin
    if (rst_in) begin
        state <= IDLE;
        busy_pipe <= 0;
        done_pipe <= 0;
        drawing_third_edge <= 0;
    end

    case (state)
        IDLE: begin
            if (start_draw) begin
                state <= SORT_0;
                busy_pipe <= 1;
            end
            done_pipe <= 0;
            busy_pipe <= 0;
        end
        SORT_0: begin
            state <= SORT_1;
            if (y0 > y2) begin
                sorted_x0 <= x2;
                sorted_y0 <= y2;
                sorted_x2 <= x0;
                sorted_y2 <= y0;
            end else begin
                sorted_x0 <= x0;
                sorted_y0 <= y0;
                sorted_x2 <= x2;
                sorted_y2 <= y2;
            end
        end
        SORT_1: begin
            state <= SORT_2;
            if (sorted_y0 > y1) begin
                sorted_x0 <= x1;
                sorted_y0 <= y1;
                sorted_x1 <= sorted_x0;
                sorted_y1 <= sorted_y0;
            end else begin
                sorted_x1 <= x1;
                sorted_y1 <= y1;
            end
        end
        SORT_2: begin
            state <= INIT_A;
            if (sorted_y1 > sorted_y2) begin
                sorted_x1 <= sorted_x2;
                sorted_y1 <= sorted_y2;
                sorted_x2 <= sorted_x1;
                sorted_y2 <= sorted_y1;
            end
        end
        INIT_A: begin
            x0a <= sorted_x0;
            y0a <= sorted_y0;
            x1a <= sorted_x2;
            y1a <= sorted_y2;
            prev_xa <= sorted_x0;
            prev_xb <= sorted_x0;
            state <= INIT_B0;
        end
        INIT_B0: begin
            x0b <= sorted_x0;
            y0b <= sorted_y0;
            x1b <= sorted_x1;
            y1b <= sorted_y1;
            state <= START_A;
            drawing_third_edge <= 0;
            prev_y <= sorted_y0;
        end
        INIT_B1: begin
            x0b <= sorted_x1;
            y0b <= sorted_y1;
            x1b <= sorted_x2;
            y1b <= sorted_y2;
            state <= START_A;
            drawing_third_edge <= 1;
            prev_y <= sorted_y1;
        end
        START_A: state <= START_B;
        START_B: state <= DRAW_EDGE;
        DRAW_EDGE: begin
            if ((ya != prev_y || !busy_a) && (yb != prev_y || !busy_b)) begin
                state <= START_H;
                x0h <= (prev_xa > prev_xb) ? prev_xb : prev_xa;
                x1h <= (prev_xa > prev_xb) ? prev_xa : prev_xb;
            end
        end
        START_H: state <= DRAW_H_LINE;
        DRAW_H_LINE: begin
            if (!busy_h) begin
                prev_y <= yb;
                prev_xa <= xa;
                prev_xb <= xb;

                // Check if we're done drawing one of the short edges
                // If so go to INIT_B1 to draw the third edge
                if (!busy_b) begin
                    state <= (busy_a && drawing_third_edge == 0) ? INIT_B1 : DONE;
                end else state <= DRAW_EDGE;
            end
        end
        DONE: begin
            state <= IDLE;
            done_pipe <= 1;
            busy_pipe <= 0;
        end
    endcase
end

always_comb begin
    // Only continue drawing on A and B when prev_y is updated to their last y output
    // This makes it so that they stop when they advance to the next y value
    oe_a = (state == DRAW_EDGE && ya == prev_y);
    oe_b = (state == DRAW_EDGE && yb == prev_y);
    oe_h = oe;
end

bresenhamLine #(.COORD_WIDTH(COORD_WIDTH)) line_drawer_a (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start_draw(state == START_A),
    .oe(oe_a),
    .x0(x0a),
    .y0(y0a),
    .x1(x1a),
    .y1(y1a),
    .x(xa),
    .y(ya),
    .drawing(),
    .busy(busy_a),
    .done()
);

bresenhamLine #(.COORD_WIDTH(COORD_WIDTH)) line_drawer_b (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start_draw(state == START_B),
    .oe(oe_b),
    .x0(x0b),
    .y0(y0b),
    .x1(x1b),
    .y1(y1b),
    .x(xb),
    .y(yb),
    .drawing(),
    .busy(busy_b),
    .done()
);

line1D #(.COORD_WIDTH(COORD_WIDTH)) line_drawer_h (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start_draw(state == START_H),
    .oe(oe_h),
    .x0(x0h),
    .x1(x1h),
    .x(xh),
    .drawing(drawing_h),
    .busy(busy_h),
    .done()
);

endmodule
`default_nettype wire
