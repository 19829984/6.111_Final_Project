`timescale 1ns / 1ps
`default_nettype none
module project_triangle #(parameter COORD_WIDTH = 32, parameter FB_HEIGHT = 180, parameter FB_WIDTH = 320) (
    input wire clk_in,
    input wire rst_in,
    input wire start,

    input wire signed [2:0][2:0][COORD_WIDTH-1:0] triangle_verts,
    input wire signed [3:0][3:0][COORD_WIDTH-1:0] model_matrix,
    input wire signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix,
    input wire signed [3:0][3:0][COORD_WIDTH-1:0] projection_matrix,

    output logic signed [2:0][3:0][COORD_WIDTH-1:0] projected_verts,
    output logic valid,
    output logic busy,
    output logic [1:0] status,
    output logic done
);
localparam ONE = 1 <<< COORD_WIDTH/2;
localparam FP_HIGH = COORD_WIDTH*2 - COORD_WIDTH/2 - 1;
localparam FP_LOW = COORD_WIDTH/2;
localparam FB_HEIGHT_HALF = FB_HEIGHT / 2;
localparam FB_WIDTH_HALF = FB_WIDTH / 2;
localparam FAR_MINUS_NEAR_HALF = (32'h00640000 - 32'h0000199a) / 2; // 100 - 0.1 in Q16.16
localparam FAR_PLUS_NEAR_HALF = (32'h00640000 + 32'h0000199a) / 2; // 100 + 0.1 in Q16.16
localparam FAR_MINUS_NEAR = (32'h00640000 - 32'h0000199a); // 100 - 0.1 in Q16.16
localparam FAR_PLUS_NEAR = (32'h00640000 + 32'h0000199a); // 100 + 0.1 in Q16.16

// Register input vertices and matrices
logic signed [2:0][2:0][COORD_WIDTH-1:0] triangle_verts_reg;
logic signed [3:0][3:0][COORD_WIDTH-1:0] model_matrix_reg;
logic signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix_reg;
logic signed [3:0][3:0][COORD_WIDTH-1:0] projection_matrix_reg;

logic signed [3:0][3:0][COORD_WIDTH-1:0] matrix_in;
logic signed [3:0][COORD_WIDTH-1:0] vector_latest;
logic signed [3:0][COORD_WIDTH-1:0] vector_out;
logic vector_matrix_start;
logic vector_matrix_busy, vector_matrix_done;
logic [1:0] vert_index;
logic signed [2:0][COORD_WIDTH-1:0] current_vert;

logic signed [COORD_WIDTH-1:0] clip_x, clip_y, clip_z, abs_x, abs_y, abs_z, w, inv_w;

logic div0_start, div0_busy, div0_done, div0_valid;
logic signed [COORD_WIDTH-1:0] div0_dividend, div0_divider, div0_out;

logic signed [COORD_WIDTH-1:0] viewport_x_int, viewport_y_int;

logic signed [2*COORD_WIDTH-1:0] prod_x, prod_y, prod_z, viewport_x, viewport_y, viewport_z, viewport_z_int; //Q32.32
logic signed [2:0][3:0][COORD_WIDTH-1:0] out_tri;
logic [1:0] num_vert_out_of_bound;
assign projected_verts = out_tri;

enum {IDLE, INIT, MODEL_MATRIX, VIEW_MATRIX, PROJ_MATRIX, CLIP, NDC, VIEWPORT1, VIEWPORT2, DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        busy <= 0;
        done <= 0;
        state <= IDLE;
        vert_index <= 0;
        valid <= 0;
        out_tri <= 0;
        num_vert_out_of_bound <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (start) begin
                    state <= INIT;
                    busy <= 1;
                    if (vert_index == 0) begin
                        current_vert <= triangle_verts[vert_index];
                    end else begin
                        current_vert <= triangle_verts_reg[vert_index];
                    end
                    // Register inputs
                    if (vert_index == 0) begin
                        triangle_verts_reg <= triangle_verts;
                        model_matrix_reg <= model_matrix;
                        view_matrix_reg <= view_matrix;
                        projection_matrix_reg <= projection_matrix;
                    end
                end
                valid <= 0;
                done <= 0;
            end
            INIT: begin
                if (vert_index == 2'b11) begin
                    state <= DONE;
                    valid <= 1;
                    done <= 1;
                    status <= 0;
                end
                else begin
                    state <= MODEL_MATRIX;
                    vector_latest <= {32'h00010000, current_vert[2], current_vert[1], current_vert[0]};
                    matrix_in <= model_matrix_reg;
                    vector_matrix_start <= 1;
                end
                if (vert_index > 0) begin
                    out_tri[vert_index - 1] <= {inv_w, viewport_z[FP_HIGH:FP_LOW], viewport_y[FP_HIGH:FP_LOW], viewport_x[FP_HIGH:FP_LOW]};
                end
                num_vert_out_of_bound <= 0;
            end
            MODEL_MATRIX: begin
                if (!vector_matrix_done) begin
                    state <= MODEL_MATRIX;
                    vector_matrix_start <= 0;
                end else begin
                    state <= VIEW_MATRIX;
                    vector_latest <= vector_out;
                    matrix_in <= view_matrix_reg;
                    vector_matrix_start <= 1;
                end
            end
            VIEW_MATRIX: begin
                if (!vector_matrix_done) begin
                    state <= VIEW_MATRIX;
                    vector_matrix_start <= 0;
                end else begin
                    state <= PROJ_MATRIX;
                    vector_latest <= vector_out;
                    matrix_in <= projection_matrix_reg;
                    vector_matrix_start <= 1;
                end
            end
            PROJ_MATRIX: begin
                if (!vector_matrix_done) begin
                    state <= PROJ_MATRIX;
                    vector_matrix_start <= 0;
                end else begin
                    state <= CLIP;
                    vector_latest <= vector_out;
                    vector_matrix_start <= 0;

                    // Absolute value of vector_out
                    abs_x <= vector_out[0][31] == 1 ? ~vector_out[0] + 1: vector_out[0];
                    abs_y <= vector_out[1][31] == 1 ? ~vector_out[1] + 1: vector_out[1];
                    abs_z <= vector_out[2][31] == 1 ? ~vector_out[2] + 1: vector_out[2];
                    w <= vector_out[3];
                end
            end
            CLIP: begin
                if (abs_z > w) begin
                    // Discard triangles that are outside of the view frustum
                    state <= DONE;
                    valid <= 0;
                    done <= 1;
                    status <= 2'b01;
                end else if (abs_y > (w <<< 2) || abs_x > (w <<< 2)) begin
                    // Discard triangles that are outside of the view frustum
                    // TODO: Do xy culling with increased w.
                    if (num_vert_out_of_bound == 2) begin // All verts out of frustum
                        state <= DONE;
                        valid <= 0;
                        done <= 1;
                        status <= 2'b01;
                    end else begin
                        num_vert_out_of_bound = num_vert_out_of_bound + 1;
                    end
                end else begin
                state <= NDC;

                    // Initialize the divider
                    // Calculate 1/w
                    div0_dividend <= (COORD_WIDTH'('b1) <<< COORD_WIDTH/2);
                    div0_divider <= $signed(w);
                    div0_start <= 1;

                    clip_x <= $signed(vector_latest[0]);
                    clip_y <= $signed(vector_latest[1]);
                    clip_z <= $signed(vector_latest[2]);
                end
            end
            NDC: begin
                if (!div0_done) begin
                    state <= NDC;
                    div0_start <= 0;
                end else begin
                    if (div0_valid) begin
                        state <= VIEWPORT1;
                        prod_x <= clip_x * div0_out;
                        prod_y <= clip_y * div0_out;
                        prod_z <= clip_z * div0_out;
                        inv_w <= div0_out;
                        vert_index <= vert_index + 1;
                    end else begin
                        // Division error, discard triangle
                        state <= DONE;
                        valid <= 0;
                        done <= 1;
                        status <= 2'b10;
                    end
                end
            end
            VIEWPORT1: begin
                viewport_x_int <= $signed(prod_x >> COORD_WIDTH/2) + $signed(ONE);
                viewport_y_int <= $signed(ONE) - $signed(prod_y >> COORD_WIDTH/2);
                viewport_z_int <= ($signed(FAR_MINUS_NEAR)) * $signed(prod_z >> COORD_WIDTH/2);
                state <= VIEWPORT2;
            end
            VIEWPORT2: begin
                viewport_x <= ($signed(FB_WIDTH_HALF) <<< COORD_WIDTH/2) * viewport_x_int;
                viewport_y <= ($signed(FB_HEIGHT_HALF) <<< COORD_WIDTH/2) * viewport_y_int;
                viewport_z <= viewport_z_int + 64'h00000000199a0000;
                current_vert <= triangle_verts_reg[vert_index];
                state <= INIT;
            end
            DONE: begin
                state <= IDLE;
                done <= 1;
                busy <= 0;
                vert_index <= 0;
            end
        endcase
    end
end

matrixVectorMultiply #(.FIXED_POINT(1), .WIDTH(COORD_WIDTH)) matrix_vector_multiply (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start(vector_matrix_start),
    .m1(matrix_in),
    .v1(vector_latest),
    .v_out(vector_out),
    .busy(vector_matrix_busy),
    .done(vector_matrix_done)
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
