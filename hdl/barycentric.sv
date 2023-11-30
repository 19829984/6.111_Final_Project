`timescale 1ns / 1ps
`default_nettype none

// Based on this stage exchange: https://gamedev.stackexchange.com/questions/23743/whats-the-most-efficient-way-to-find-barycentric-coordinates
// Use init and fill in a, b, and c first to initialize the module with precomputed values
// Then set p to start computing, results available on the 8th cycle after p is set
module computeBarycentric #(parameter COORD_WIDTH = 32) (
    input wire clk_in,
    input wire rst_in,
    input wire signed [2:0][COORD_WIDTH-1:0] p, a, b, c, //Point p and triangle vertices a, b, c
    input wire init, // Initialize module with precalculated values

    output logic [COORD_WIDTH-1:0] u, v, w,
    output logic valid,
    output logic init_done,
    output logic busy,
    output logic done
);
localparam FP_HIGH = COORD_WIDTH*2 - COORD_WIDTH/2 - 1;
localparam FP_LOW = COORD_WIDTH/2;

logic signed [COORD_WIDTH-1:0] dp0_x0, dp0_x1, dp0_x2, dp0_y0, dp0_y1, dp0_y2, dp0_out;
logic signed [COORD_WIDTH-1:0] dp1_x0, dp1_x1, dp1_x2, dp1_y0, dp1_y1, dp1_y2, dp1_out;
logic signed [2:0][COORD_WIDTH-1:0] v0, v1, v2;
logic signed [COORD_WIDTH-1:0] d00, d01, d11, d20, d21, invDenom;

logic div0_start, div0_busy, div0_done, div0_valid;
logic signed [COORD_WIDTH-1:0] div0_dividend, div0_divider, div0_out;

(* dont_touch = "yes" *) logic signed [2*COORD_WIDTH-1:0] prod_a, prod_b, prod_c, prod_d, w_prod, v_prod;

enum {IDLE, INIT_D11, AWAIT_INIT, AWAIT_INIT_2, D00_D01_DONE, D11_DONE, START_DIV, AWAIT_DIVIDER, INIT_DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        busy <= 0;
        done <= 0;
        init_done <= 0;
        valid <= 0;
        u <= 0;
        v <= 0;
        w <= 0;
        state <= IDLE;
        prod_a <= 0;
        prod_b <= 0;
        prod_c <= 0;
        prod_d <= 0;
        v0 <= 0;
        v1 <= 0;
        v2 <= 0;
    end
    else begin
        case (state)
            IDLE: begin
                if (init) begin
                    state <= INIT_D11;
                    busy <= 1;
                    v0 <= {b[2] - a[2], b[1] - a[1], b[0] - a[0]};
                    v1 <= {c[2] - a[2], c[1] - a[1], c[0] - a[0]};

                    // Init calculating d00
                    dp0_x0 <= b[0] - a[0];
                    dp0_x1 <= b[1] - a[1];
                    dp0_x2 <= b[2] - a[2];
                    dp0_y0 <= b[0] - a[0];
                    dp0_y1 <= b[1] - a[1];
                    dp0_y2 <= b[2] - a[2];

                    // Init calculating d01
                    dp1_x0 <= b[0] - a[0];
                    dp1_x1 <= b[1] - a[1];
                    dp1_x2 <= b[2] - a[2];
                    dp1_y0 <= c[0] - a[0];
                    dp1_y1 <= c[1] - a[1];
                    dp1_y2 <= c[2] - a[2];
                end else begin
                    state <= IDLE;
                    busy <= 0;
                end
                init_done <= 0;
            end
            INIT_D11: begin
                // Init calculating d11
                dp0_x0 <= v1[0];
                dp0_x1 <= v1[1];
                dp0_x2 <= v1[2];
                dp0_y0 <= v1[0];
                dp0_y1 <= v1[1];
                dp0_y2 <= v1[2];
                state <= AWAIT_INIT;
            end
            AWAIT_INIT: begin
                state <= AWAIT_INIT_2;
            end
            AWAIT_INIT_2: begin
                state <= D00_D01_DONE;
            end
            D00_D01_DONE: begin
                d00 <= dp0_out;
                d01 <= dp1_out;
                state <= D11_DONE;
            end
            D11_DONE: begin
                d11 <= dp0_out;
                // Compute divider for invDenom
                prod_a <= d00 * dp0_out;
                prod_b <= d01 * d01;
                state <= START_DIV;
            end
            START_DIV: begin
                div0_start <= 1;
                div0_dividend <= 32'h00010000;
                div0_divider <= prod_a[FP_HIGH:FP_LOW] - prod_b[FP_HIGH:FP_LOW];
                state <= AWAIT_DIVIDER;
            end
            AWAIT_DIVIDER: begin
                div0_start <= 0;
                if (div0_done) begin
                    if (div0_valid) begin
                        state <= INIT_DONE;
                        invDenom <= div0_out;
                        init_done <= 1;
                    end
                    else begin
                        // Division error
                        state <= IDLE;
                        valid <= 0;
                        done <= 1;
                        init_done <= 0;
                    end
                end else begin
                    state <= AWAIT_DIVIDER;
                end
            end
            INIT_DONE: begin
                state <= INIT_DONE;

                // Step 1
                v2 <= {p[2] - a[2], p[1] - a[1], p[0] - a[0]};

                // Step 2
                dp0_x0 <= v2[0];
                dp0_x1 <= v2[1];
                dp0_x2 <= v2[2];
                dp0_y0 <= v0[0];
                dp0_y1 <= v0[1];
                dp0_y2 <= v0[2];

                dp1_x0 <= v2[0];
                dp1_x1 <= v2[1];
                dp1_x2 <= v2[2];
                dp1_y0 <= v1[0];
                dp1_y1 <= v1[1];
                dp1_y2 <= v1[2];

                // Step 3 (3 cycles later, on 4th cycle after step 2, 6th overall)
                prod_a <= dp0_out * d11;
                prod_b <= dp1_out * d01;
                prod_c <= dp1_out * d00;
                prod_d <= dp0_out * d01;

                // Step 4
                v_prod <= $signed(prod_a[FP_HIGH:FP_LOW] - prod_b[FP_HIGH:FP_LOW]) * invDenom;
                w_prod <= $signed(prod_c[FP_HIGH:FP_LOW] - prod_d[FP_HIGH:FP_LOW]) * invDenom;

                // Step 5
                u <= $signed(32'h00010000) - v_prod[FP_HIGH:FP_LOW] - w_prod[FP_HIGH:FP_LOW];
                v <= v_prod[FP_HIGH:FP_LOW];
                w <= w_prod[FP_HIGH:FP_LOW];
                valid <= v_prod[FP_HIGH] != 1 && w_prod[FP_HIGH] != 1 && (v_prod[FP_HIGH] + w_prod[FP_HIGH] < $signed(32'h00010000));
            end
        endcase
    end
end

dotProduct #(.FIXED_POINT(1), .WIDTH(COORD_WIDTH)) dotProduct0 (
    .clk_in(clk_in),
    .x0(dp0_x0),
    .x1(dp0_x1),
    .x2(dp0_x2),
    .x3(32'h0),
    .y0(dp0_y0),
    .y1(dp0_y1),
    .y2(dp0_y2),
    .y3(32'h0),
    .out(dp0_out)
);

dotProduct #(.FIXED_POINT(1), .WIDTH(COORD_WIDTH)) dotProduct1 (
    .clk_in(clk_in),
    .x0(dp1_x0),
    .x1(dp1_x1),
    .x2(dp1_x2),
    .x3(32'h0),
    .y0(dp1_y0),
    .y1(dp1_y1),
    .y2(dp1_y2),
    .y3(32'h0),
    .out(dp1_out)
);

div #(.WIDTH(COORD_WIDTH), .FBITS(COORD_WIDTH/2)) divider0(
    .clk(clk_in),
    .rst(rst_in),
    .start(div0_start),
    .busy(div0_busy),
    .done(div0_done),
    .valid(div0_valid),
    .dbz(),
    .ovf(),
    .a(div0_dividend),
    .b(div0_divider),
    .val(div0_out)
);

endmodule
`default_nettype wire