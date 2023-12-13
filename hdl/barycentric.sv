`timescale 1ns / 1ps
`default_nettype none

// Based on this stage exchange: https://gamedev.stackexchange.com/questions/23743/whats-the-most-efficient-way-to-find-barycentric-coordinates
// Use init and fill in a, b, and c first to initialize the module with precomputed values
// Then set p to start computing, results available on the 13th cycle after p is set
// May have precision errors near the vertices and edges, resulting in uvw values that are outside
// of the 0-1 range. This will result in extrapolation of vertex attributes, which should have 
// negligble error to its real value
module computeBarycentric #(parameter COORD_WIDTH = 32) (
    input wire clk_in,
    input wire rst_in,
    input wire signed [2:0][COORD_WIDTH/2-1:0] p, a, b, c, //Point p and triangle vertices a, b, c, integers
    input wire valid_in,
    input wire init, // Initialize module with precalculated values

    output logic [COORD_WIDTH-1:0] u, v, w,
    output logic valid_out,
    output logic init_done,
    output logic init_failed,
    output logic done
);
localparam DIV_HIGH = (COORD_WIDTH/2 + COORD_WIDTH) - COORD_WIDTH/4 - 1;
localparam DIV_LOW = COORD_WIDTH/4;
localparam DELAY = 7+5;
logic [DELAY-1:0] valid_in_pipe;
logic signed [COORD_WIDTH-1:0] out_u, out_v, out_w;

logic signed [COORD_WIDTH/2-1:0] dp0_x0, dp0_x1, dp0_x2, dp0_y0, dp0_y1, dp0_y2, dp0_out;
logic signed [COORD_WIDTH/2-1:0] dp1_x0, dp1_x1, dp1_x2, dp1_y0, dp1_y1, dp1_y2, dp1_out;
logic signed [COORD_WIDTH/2-1:0] d00, d01, d11, d20, d21;
logic signed [COORD_WIDTH-1:0] d00_11, d01_01;
logic signed [2:0][COORD_WIDTH/2-1:0] v0, v1, v2;
logic signed [(COORD_WIDTH/2 + COORD_WIDTH)-1:0] d00_div, d01_div, d11_div; // Multiplying Q32.0 with Q0.32, giving Q64.32

logic div0_start, div0_busy, div0_done, div0_valid;
logic signed [COORD_WIDTH-1:0] div0_dividend, div0_divider, div0_out; //Q32.32, div0_out will always be <1 so only use last 

logic signed [(COORD_WIDTH/2 + COORD_WIDTH)-1:0] prod_a, prod_b, prod_c, prod_d; //Q48.48
logic signed [(COORD_WIDTH/2 + COORD_WIDTH)-1:0] prod_test;

enum {IDLE, INIT_D11, AWAIT_INIT, AWAIT_INIT_2, D00_D01_DONE, D11_DONE, START_DIV, AWAIT_DIVIDER, INIT_DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        init_failed <= 0;
        done <= 0;
        init_done <= 0;
        valid_out <= 0;
        u <= 0;
        v <= 0;
        w <= 0;
        state <= IDLE;
        d00 <= 0;
        d01 <= 0;
        d11 <= 0;
        d20 <= 0;
        d21 <= 0;
        dp0_x0 <= 0;
        dp0_x1 <= 0;
        dp0_x2 <= 0;
        dp0_y0 <= 0;
        dp0_y1 <= 0;
        dp0_y2 <= 0;
        dp1_x0 <= 0;
        dp1_x1 <= 0;
        dp1_x2 <= 0;
        dp1_y0 <= 0;
        dp1_y1 <= 0;
        dp1_y2 <= 0;
        v0 <= 0;
        v1 <= 0;
        v2 <= 0;
        out_u <= 0;
        out_v <= 0;
        out_w <= 0;
        d00_div <= 0;
        d01_div <= 0;
        d11_div <= 0;
        valid_in_pipe <= 0;
        valid_out <= 0;

    end
    else begin
        case (state)
            IDLE: begin
                if (init) begin
                    state <= INIT_D11;
                    v0 <= {$signed(b[2]) - $signed(a[2]), $signed(b[1]) - $signed(a[1]), $signed(b[0]) - $signed(a[0])};
                    v1 <= {$signed(c[2]) - $signed(a[2]), $signed(c[1]) - $signed(a[1]), $signed(c[0]) - $signed(a[0])};

                    // Init calculating d00
                    dp0_x0 <= $signed(b[0]) - $signed(a[0]);
                    dp0_x1 <= $signed(b[1]) - $signed(a[1]);
                    dp0_x2 <= $signed(b[2]) - $signed(a[2]);
                    dp0_y0 <= $signed(b[0]) - $signed(a[0]);
                    dp0_y1 <= $signed(b[1]) - $signed(a[1]);
                    dp0_y2 <= $signed(b[2]) - $signed(a[2]);

                    // Init calculating d01
                    dp1_x0 <= $signed(b[0]) - $signed(a[0]);
                    dp1_x1 <= $signed(b[1]) - $signed(a[1]);
                    dp1_x2 <= $signed(b[2]) - $signed(a[2]);
                    dp1_y0 <= $signed(c[0]) - $signed(a[0]);
                    dp1_y1 <= $signed(c[1]) - $signed(a[1]);
                    dp1_y2 <= $signed(c[2]) - $signed(a[2]);
                end else begin
                    state <= IDLE;
                end
                init_done <= 0;
                init_failed <= 0;
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
                d00_11 <= d00*dp0_out;
                d01_01 <= d01*d01;
                state <= START_DIV;
            end
            START_DIV: begin
                div0_start <= 1;
                div0_dividend <= (COORD_WIDTH'('b1) <<< COORD_WIDTH/2);
                div0_divider <= (d00_11 - d01_01) <<< COORD_WIDTH/2;
                state <= AWAIT_DIVIDER;
            end
            AWAIT_DIVIDER: begin
                div0_start <= 0;
                if (div0_done) begin
                    if (div0_valid) begin
                        state <= INIT_DONE;
                        d00_div <= d00 * div0_out;
                        d01_div <= d01 * div0_out;
                        d11_div <= d11 * div0_out;
                        
                        // Prefill some values for the dot products ahead of time
                        dp0_y0 <= v0[0];
                        dp0_y1 <= v0[1];
                        dp0_y2 <= v0[2];
                        dp1_y0 <= v1[0];
                        dp1_y1 <= v1[1];
                        dp1_y2 <= v1[2];
                        init_done <= 1;
                    end
                    else begin
                        // Division error
                        state <= IDLE;
                        valid_out <= 0;
                        done <= 1;
                        init_done <= 0;
                        init_failed <= 1;
                    end
                end else begin
                    state <= AWAIT_DIVIDER;
                end
            end
            INIT_DONE: begin
                state <= INIT_DONE;
                valid_in_pipe <= {valid_in, valid_in_pipe[DELAY-1:1]};

                // Step 1
                v2 <= {$signed(p[2]) - $signed(a[2]), $signed(p[1]) - $signed(a[1]), $signed(p[0]) - $signed(a[0])};

                // Step 2
                dp0_x0 <= v2[0];
                dp0_x1 <= v2[1];
                dp0_x2 <= v2[2];

                dp1_x0 <= v2[0];
                dp1_x1 <= v2[1];
                dp1_x2 <= v2[2];

                // Step 3 (3 cycles later, on 4th cycle after step 2, 6th overall)
                d20 <= dp0_out;
                d21 <= dp1_out;

                // Step 4 (6th cycle after dp20 and dp21 are set)
                out_v <= (prod_a - prod_b); //Q64.32 to 32.32
                out_w <= (prod_c - prod_d);
                out_u <= (((prod_a - prod_b)) + ((prod_c - prod_d)));

                // Step 5
                // valid_out <= valid_in_pipe[0] && out_v[COORD_WIDTH-1] != 1 && out_w[COORD_WIDTH-1] != 1 && out_u[COORD_WIDTH-1] != 1;
                valid_out <= valid_in_pipe[0];
                u <= (COORD_WIDTH'('b1) <<< COORD_WIDTH/2) - out_u;
                v <= out_v;
                w <= out_w;
            end
        endcase
    end
end

mult1Q3232Q6464 mult1Q3232Q6464_0 (
    .CLK(clk_in),
    .A(d20), //Q32.0
    .B($signed(d11_div[63:0])), //Q64.32 to Q32.32
    .P(prod_a) //Q64.32
);

mult1Q3232Q6464 mult1Q3232Q6464_1 (
    .CLK(clk_in),
    .A(d21),
    .B($signed(d01_div[63:0])),
    .P(prod_b)
);

mult1Q3232Q6464 mult1Q3232Q6464_2 (
    .CLK(clk_in),
    .A(d21),
    .B($signed(d00_div[63:0])),
    .P(prod_c)
);

mult1Q3232Q6464 mult1Q3232Q6464_3 (
    .CLK(clk_in),
    .A(d20),
    .B($signed(d01_div[63:0])),
    .P(prod_d)
);

dotProduct_3 #(.FIXED_POINT(0), .WIDTH(COORD_WIDTH/2)) dotProduct0 (
    .clk_in(clk_in),
    .x0(dp0_x0),
    .x1(dp0_x1),
    .x2(dp0_x2),
    .y0(dp0_y0),
    .y1(dp0_y1),
    .y2(dp0_y2),
    .out(dp0_out)
);

dotProduct_3 #(.FIXED_POINT(0), .WIDTH(COORD_WIDTH/2)) dotProduct1 (
    .clk_in(clk_in),
    .x0(dp1_x0),
    .x1(dp1_x1),
    .x2(dp1_x2),
    .y0(dp1_y0),
    .y1(dp1_y1),
    .y2(dp1_y2),
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
    .b($signed(div0_divider)),
    .val(div0_out)
);

endmodule
`default_nettype wire