`timescale 1ns / 1ps
`default_nettype none

// This module performs the m1 X m2 matrix multiplication operation
// Has an 8 cycle delay
module matrixMultiply4x4 #(parameter FIXED_POINT = 1, parameter WIDTH = 32) (
    input wire clk_in,
    input wire rst_in,
    input wire start,
    input wire signed [3:0][3:0][WIDTH-1:0] m1,
    input wire signed [3:0][3:0][WIDTH-1:0] m2,

    output logic signed [3:0][3:0][WIDTH-1:0] m_out,
    output logic busy,
    output logic done
);
// Register the input matrices
logic signed [3:0][3:0][WIDTH-1:0] m1_reg;
logic signed [3:0][3:0][WIDTH-1:0] m2_reg;

logic signed [3:0][WIDTH-1:0] dp0_x_vec;
logic signed [3:0][WIDTH-1:0] dp0_y_vec;
logic signed [3:0][WIDTH-1:0] dp1_x_vec;
logic signed [3:0][WIDTH-1:0] dp1_y_vec;
logic signed [3:0][WIDTH-1:0] dp2_x_vec;
logic signed [3:0][WIDTH-1:0] dp2_y_vec;
logic signed [3:0][WIDTH-1:0] dp3_x_vec;
logic signed [3:0][WIDTH-1:0] dp3_y_vec;

logic signed [WIDTH-1:0] dp0_out, dp1_out, dp2_out, dp3_out;

enum {IDLE, INIT_ROW_1, INIT_ROW_2, INIT_ROW_3, INIT_ROW_4, ROW_1_DONE, ROW_2_DONE, ROW_3_DONE, DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        state <= IDLE;
        busy <= 0;
        done <= 0;
        m1_reg <= 0;
        m2_reg <= 0;
        m_out <= 0;

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
                    state <= INIT_ROW_1;
                    busy <= 1;
                    m1_reg <= m1;
                    m2_reg <= m2;
                end
                else begin
                    state <= IDLE;
                    busy <= 0;
                end
                done <= 0;
            end
            INIT_ROW_1: begin
                state <= INIT_ROW_2;
                // Row 1 with DP0
                dp0_x_vec <= m1_reg[0];
                // Row 1 with DP1
                dp1_x_vec <= m1_reg[0];
                // Row 1 with DP2
                dp2_x_vec <= m1_reg[0];
                // Row 1 with DP 3
                dp3_x_vec <= m1_reg[0];

                // Initialize Y values once
                // These dont change
                // Column 1 with DP0
                dp0_y_vec <= {m2_reg[3][0], m2_reg[2][0], m2_reg[1][0], m2_reg[0][0]};
                // Column 2 with DP1
                dp1_y_vec <= {m2_reg[3][1], m2_reg[2][1], m2_reg[1][1], m2_reg[0][1]};
                // Column 3 with DP2
                dp2_y_vec <= {m2_reg[3][2], m2_reg[2][2], m2_reg[1][2], m2_reg[0][2]};
                // Column 4 with DP 3
                dp3_y_vec <= {m2_reg[3][3], m2_reg[2][3], m2_reg[1][3], m2_reg[0][3]};
            end
            INIT_ROW_2: begin
                state <= INIT_ROW_3;
                // Row 2 and Column 1 with DP0
                dp0_x_vec <= m1_reg[1];
                // Row 2 and Column 2 with DP1
                dp1_x_vec <= m1_reg[1];
                // Row 2 and Column 3 with DP2
                dp2_x_vec <= m1_reg[1];
                // Row 2 and Column 4 with DP 3
                dp3_x_vec <= m1_reg[1];
            end
            INIT_ROW_3: begin
                state <= INIT_ROW_4;
                // Row 3 and Column 1 with DP0
                dp0_x_vec <= m1_reg[2];
                // Row 3 and Column 2 with DP1
                dp1_x_vec <= m1_reg[2];
                // Row 3 and Column 3 with DP2
                dp2_x_vec <= m1_reg[2];
                // Row 3 and Column 4 with DP 3
                dp3_x_vec <= m1_reg[2];
            end
            INIT_ROW_4: begin
                state <= ROW_1_DONE;
                // Row 4 and Column 1 with DP0
                dp0_x_vec <= m1_reg[3];
                // Row 4 and Column 2 with DP1
                dp1_x_vec <= m1_reg[3];
                // Row 4 and Column 3 with DP2
                dp2_x_vec <= m1_reg[3];
                // Row 4 and Column 4 with DP 3
                dp3_x_vec <= m1_reg[3];
            end
            ROW_1_DONE: begin
                state <= ROW_2_DONE;
                // Retrieve results from INIT_ROW_1
                m_out[0] <= {dp3_out, dp2_out, dp1_out, dp0_out};
            end
            ROW_2_DONE: begin
                state <= ROW_3_DONE;
                // Retrieve results from INIT_ROW_2
                m_out[1] <= {dp3_out, dp2_out, dp1_out, dp0_out};
            end
            ROW_3_DONE: begin
                state <= DONE;
                // Retrieve results from INIT_ROW_3
                m_out[2] <= {dp3_out, dp2_out, dp1_out, dp0_out};
            end
            DONE: begin
                // Retrieve results from INIT_ROW_4
                m_out[3] <= {dp3_out, dp2_out, dp1_out, dp0_out};

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