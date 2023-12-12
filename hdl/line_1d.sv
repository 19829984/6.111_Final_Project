`timescale 1ns / 1ps
`default_nettype none

module line1D #(parameter COORD_WIDTH = 16) (
    input wire clk_in,
    input wire rst_in,
    input wire start_draw,
    input wire oe,
    input wire signed [COORD_WIDTH-1:0] x0, x1,
    output logic signed [COORD_WIDTH-1:0] x,
    output logic drawing,
    output logic busy,
    output logic done
);
    enum {IDLE, DRAW} state;
    assign drawing = state == DRAW;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    busy <= 0;
                    if (start_draw) begin
                        state <= DRAW;
                        busy <= 1;
                        x <= x0;
                    end
                end
                DRAW: begin
                    if (oe) begin
                        if (x == x1) begin
                            state <= IDLE;
                            done <= 1;
                            busy <= 0;
                        end else
                            x <= x + 1;
                    end
                end
            endcase
        end
    end

endmodule
`default_nettype wire