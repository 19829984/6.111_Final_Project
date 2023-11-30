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

    output logic signed [2:0][2:0][COORD_WIDTH-1:0] projected_verts,
    output logic valid,
    output logic busy,
    output logic [1:0] status,
    output logic done
);
localparam FB_HEIGHT_HALF = FB_HEIGHT / 2;
localparam FB_WIDTH_HALF = FB_WIDTH / 2;
localparam FAR_MINUS_NEAR_HALF = (32'h00640000 - 32'h0000199a) / 2; // 100 - 0.1 in Q16.16
localparam FAR_PLUS_NEAR_HALF = (32'h00640000 + 32'h0000199a) / 2; // 100 + 0.1 in Q16.16

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

logic signed [COORD_WIDTH-1:0] abs_x, abs_y, abs_z, w;

logic div0_start, div0_busy, div0_done, div0_valid;
logic signed [COORD_WIDTH-1:0] div0_dividend, div0_divider, div0_out;

logic div1_start, div1_busy, div1_done, div1_valid;
logic signed [COORD_WIDTH-1:0] div1_dividend, div1_divider, div1_out;

logic div2_start, div2_busy, div2_done, div2_valid;
logic signed [COORD_WIDTH-1:0] div2_dividend, div2_divider, div2_out;

logic dividers_busy, dividers_valid;
assign dividers_busy = ~(div0_done && div1_done && div2_done);
assign dividers_valid = div0_valid && div1_valid && div2_valid;

logic signed [2:0][2:0][COORD_WIDTH-1:0] out_tri;
logic signed [2:0][COORD_WIDTH-1:0] out_vert;
assign projected_verts = out_tri;

enum {IDLE, INIT, MODEL_MATRIX, VIEW_MATRIX, PROJ_MATRIX, CLIP, NDC, VIEWPORT, DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        busy <= 0;
        done <= 0;
        state <= IDLE;
        vert_index <= 0;
        valid <= 0;
        out_tri <= 0;
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
                    out_tri[vert_index - 1] <= out_vert;
                end
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
                if ((abs_x > w) || (abs_y > w) || (abs_z > w)) begin
                    // Discard triangles that are outside of the view frustum
                    // TODO: Create new triangles from frustum clipping
                    state <= DONE;
                    valid <= 0;
                    done <= 1;
                    status <= 2'b01;
                end else begin
                    state <= NDC;

                    // Initialize the dividers
                    div0_dividend <= vector_out[0];
                    div0_divider <= vector_out[3];
                    div0_start <= 1;

                    div1_dividend <= vector_out[1];
                    div1_divider <= vector_out[3];
                    div1_start <= 1;

                    div2_dividend <= vector_out[2];
                    div2_divider <= vector_out[3];
                    div2_start <= 1;
                end
            end
            NDC: begin
                if (dividers_busy) begin
                    state <= NDC;
                    div0_start <= 0;
                    div1_start <= 0;
                    div2_start <= 0;
                end else begin
                    if (dividers_valid) begin
                        state <= VIEWPORT;
                        vector_latest <= {32'b0, div2_out, div1_out, div0_out};
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
            VIEWPORT: begin
                out_vert[0] <= $signed(FB_WIDTH_HALF) * (vector_latest[0] + 32'h00010000);
                out_vert[1] <= $signed(FB_HEIGHT_HALF) * (32'h00010000 - vector_latest[1]);
                out_vert[2] <= $signed(FAR_MINUS_NEAR_HALF) * vector_latest[2] + ($signed(FAR_PLUS_NEAR_HALF)  << 16);
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

div #(.WIDTH(COORD_WIDTH), .FBITS(COORD_WIDTH/2)) divider1(
    .clk(clk_in),
    .rst(rst_in),
    .start(div1_start),
    .busy(div1_busy),
    .done(div1_done),
    .valid(div1_valid),
    .dbz(),
    .ovf(),
    .a(div1_dividend),
    .b(div1_divider),
    .val(div1_out)
);

div #(.WIDTH(COORD_WIDTH), .FBITS(COORD_WIDTH/2)) divider2(
    .clk(clk_in),
    .rst(rst_in),
    .start(div2_start),
    .busy(div2_busy),
    .done(div2_done),
    .valid(div2_valid),
    .dbz(),
    .ovf(),
    .a(div2_dividend),
    .b(div2_divider),
    .val(div2_out)
);

endmodule

`default_nettype wire