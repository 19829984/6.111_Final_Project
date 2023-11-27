`timescale 1ns / 1ps
`default_nettype none

module bresenhamLine #(parameter COORD_WIDTH = 16) (
    input wire clk_in,
    input wire rst_in,
    input wire start_draw,
    input wire oe, //Can be used to pause the algorithm
    input wire signed [COORD_WIDTH-1:0] x0, y0,
    input wire signed [COORD_WIDTH-1:0] x1, y1,
    output logic signed [COORD_WIDTH-1:0] x, y,
    output logic drawing,
    output logic busy,
    output logic done
);
    // Sort coordinates based on y value
    logic swap; // Swap coordinate
    logic right; // Drawing direction
    logic signed [COORD_WIDTH-1:0] xa, ya; // Line start
    logic signed [COORD_WIDTH-1:0] xb, yb; // Line end
    logic signed [COORD_WIDTH-1:0] x_end, y_end; // Store line end to avoid timing through combinational path
    always_comb begin
        swap = (y0 > y1); // If start point is lower than end point
        xa = swap ? x1 : x0;
        ya = swap ? y1 : y0;
        xb = swap ? x0 : x1;
        yb = swap ? y0 : y1;
    end

    // Begin Bresenham algorithm

    // Error value setup
    logic signed [COORD_WIDTH:0] error;
    logic signed [COORD_WIDTH:0] dx, dy;
    logic move_x, move_y; // If we need to move where we draw
    always_comb begin
        move_x = ((error << 1) >= dy);
        move_y = ((error << 1) <= dx);
    end

    // State Machine to execute algorithm
    enum {IDLE, INIT_0, INIT_1, DRAWING} state;
    always_comb drawing = (state == DRAWING && oe);

    always_ff @(posedge clk_in) begin
        case (state)
            DRAWING: begin
                if (oe) begin
                    if (x == x_end && y == y_end) begin
                        state <= IDLE;
                        done <= 1;
                        busy <= 0;
                    end else begin
                        if (move_x && move_y) begin
                            error <= error + dx + dy;
                            x <= right ? x + 1 : x - 1;
                            y <= y + 1; // We always draw lines downwards
                        end
                        else if (move_x) begin
                            error <= error + dy;
                            x <= right ? x + 1 : x - 1;
                        end
                        else if (move_y) begin
                            error <= error + dx;
                            y <= y + 1; // We always draw lines downwards
                        end
                    end
                end
            end
            INIT_0: begin // Store values in registers to avoid combinational timing
                state <= INIT_1;
                dx <= right ? xb - xa : xa - xb; // Absolute value
                dy <= ya - yb;
            end
            INIT_1: begin
                state <= DRAWING;
                error <= dx + dy;
                x <= xa;
                y <= ya;
                x_end <= xb;
                y_end <= yb;
            end
            default: begin //IDLE
                done <= 0;
                if (start_draw) begin
                    state <= INIT_0; 
                    right <= (xa < xb);
                    busy <= 1;
                end
            end
        endcase

        if (rst_in) begin
            state <= IDLE;
            done <= 0;
            busy <= 0;
        end
    end
endmodule
`default_nettype wire
