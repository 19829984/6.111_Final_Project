`timescale 1ns / 1ps
`default_nettype none

// This module performs a multiplication of m1 4x4 matrix and v1 4x1 vector
// Index of the matrix is [row][column]
// Index of the vector is [row]
// Takes 6 cycles from start pulse
module matrixVectorMultiply #(parameter FIXED_POINT = 1, parameter WIDTH = 32) (
    input wire clk_in,
    input wire rst_in,
    input wire start,
    input wire signed [3:0][3:0][WIDTH-1:0] m1,
    input wire signed [3:0][WIDTH-1:0] v1,

    output logic signed [3:0][WIDTH-1:0] v_out,
    output logic busy,
    output logic done
);
// Register the input matrices
logic signed [3:0][3:0][WIDTH-1:0] m1_reg;
logic signed [3:0][WIDTH-1:0] v1_reg;

logic signed [3:0][WIDTH-1:0] dp0_x_vec;
logic signed [3:0][WIDTH-1:0] dp0_y_vec;
logic signed [3:0][WIDTH-1:0] dp1_x_vec;
logic signed [3:0][WIDTH-1:0] dp1_y_vec;
logic signed [3:0][WIDTH-1:0] dp2_x_vec;
logic signed [3:0][WIDTH-1:0] dp2_y_vec;
logic signed [3:0][WIDTH-1:0] dp3_x_vec;
logic signed [3:0][WIDTH-1:0] dp3_y_vec;

logic signed [WIDTH-1:0] dp0_out, dp1_out, dp2_out, dp3_out;

enum {IDLE, INIT, PIPE_1, PIPE_2, PIPE_3, DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        state <= IDLE;
        busy <= 0;
        done <= 0;
        m1_reg <= 0;
        v1_reg <= 0;
        v_out <= 0;

        // Set all dp variables to 0
        dp0_x_vec <= 0;
        dp0_y_vec <= 0;
        dp1_x_vec <= 0;
        dp1_y_vec <= 0;
        dp2_x_vec <= 0;
        dp2_y_vec <= 0;
        dp3_x_vec <= 0;
        dp3_y_vec <= 0;
    end
    else begin
        case (state)
            IDLE: begin
                if (start) begin
                    state <= INIT;
                    busy <= 1;
                    m1_reg <= m1;
                    v1_reg <= v1;
                end
                else begin
                    state <= IDLE;
                    busy <= 0;
                end
                done <= 0;
            end
            INIT: begin
                state <= PIPE_1;
                // Row 1 with DP0
                dp0_x_vec <= m1_reg[0];
                // Row 1 with DP1
                dp1_x_vec <= m1_reg[1];
                // Row 1 with DP2
                dp2_x_vec <= m1_reg[2];
                // Row 1 with DP 3
                dp3_x_vec <= m1_reg[3];

                // Column 1 with DP0
                dp0_y_vec <= {v1_reg[3], v1_reg[2], v1_reg[1], v1_reg[0]};
                // Column 2 with DP1
                dp1_y_vec <= {v1_reg[3], v1_reg[2], v1_reg[1], v1_reg[0]};
                // Column 3 with DP2
                dp2_y_vec <= {v1_reg[3], v1_reg[2], v1_reg[1], v1_reg[0]};
                // Column 4 with DP 3
                dp3_y_vec <= {v1_reg[3], v1_reg[2], v1_reg[1], v1_reg[0]};
            end
            PIPE_1: state <= PIPE_2;
            PIPE_2: state <= PIPE_3;
            PIPE_3: state <= DONE;
            DONE: begin
                // Retrieve results from INIT_ROW_4
                v_out <= {dp3_out, dp2_out, dp1_out, dp0_out};

                state <= IDLE;
                busy <= 0;
                done <= 1;
            end
        endcase
    end
end

// 4 Dot product modules
dotProduct #(.FIXED_POINT(FIXED_POINT), .WIDTH(WIDTH)) dp0 (
    .clk_in(clk_in),
    .x0(dp0_x_vec[0]),
    .x1(dp0_x_vec[1]),
    .x2(dp0_x_vec[2]),
    .x3(dp0_x_vec[3]),
    .y0(dp0_y_vec[0]),
    .y1(dp0_y_vec[1]),
    .y2(dp0_y_vec[2]),
    .y3(dp0_y_vec[3]),
    .out(dp0_out)
);

dotProduct #(.FIXED_POINT(FIXED_POINT), .WIDTH(WIDTH)) dp1 (
    .clk_in(clk_in),
    .x0(dp1_x_vec[0]),
    .x1(dp1_x_vec[1]),
    .x2(dp1_x_vec[2]),
    .x3(dp1_x_vec[3]),
    .y0(dp1_y_vec[0]),
    .y1(dp1_y_vec[1]),
    .y2(dp1_y_vec[2]),
    .y3(dp1_y_vec[3]),
    .out(dp1_out)
);

dotProduct #(.FIXED_POINT(FIXED_POINT), .WIDTH(WIDTH)) dp2 (
    .clk_in(clk_in),
    .x0(dp2_x_vec[0]),
    .x1(dp2_x_vec[1]),
    .x2(dp2_x_vec[2]),
    .x3(dp2_x_vec[3]),
    .y0(dp2_y_vec[0]),
    .y1(dp2_y_vec[1]),
    .y2(dp2_y_vec[2]),
    .y3(dp2_y_vec[3]),
    .out(dp2_out)
);

dotProduct #(.FIXED_POINT(FIXED_POINT), .WIDTH(WIDTH)) dp3 (
    .clk_in(clk_in),
    .x0(dp3_x_vec[0]),
    .x1(dp3_x_vec[1]),
    .x2(dp3_x_vec[2]),
    .x3(dp3_x_vec[3]),
    .y0(dp3_y_vec[0]),
    .y1(dp3_y_vec[1]),
    .y2(dp3_y_vec[2]),
    .y3(dp3_y_vec[3]),
    .out(dp3_out)
);

endmodule
`default_nettype wire