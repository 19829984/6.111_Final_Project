`timescale 1ns / 1ps
`default_nettype none
module rasterizer #(parameter WIREFRAME = 0, parameter COORD_WIDTH = 32, parameter DEPTH_BIT_WIDTH = 16,
                    parameter FB_WIDTH = 320, parameter FB_HEIGHT = 180) (
    input wire clk_in,
    input wire rst_in,
    input wire start,
    input wire signed [COORD_WIDTH-1:0] x_in,
    input wire signed [COORD_WIDTH-1:0] y_in,
    input wire signed [COORD_WIDTH-1:0] z_in,

    output logic [COORD_WIDTH-1:0] x, y,
    output logic signed [COORD_WIDTH-1:0] out_u, out_v, out_w,
    output logic [DEPTH_BIT_WIDTH-1:0] depth,
    output logic drawing,
    output logic [2:0] raster_state,
    output logic [1:0] proj_status,
    output logic busy,
    output logic done,
    output logic signed [31:0] test
);
localparam BARY_HIGH = (COORD_WIDTH*2) - (COORD_WIDTH/2) - 1;
localparam BARY_LOW = (COORD_WIDTH)/2; 
localparam DEPTH_HIGH = (COORD_WIDTH/2) + (DEPTH_BIT_WIDTH/2) - 1;
localparam DEPTH_LOW = (COORD_WIDTH/2) - (DEPTH_BIT_WIDTH/2);
localparam DEPTH64_HIGH = (COORD_WIDTH) + (DEPTH_BIT_WIDTH/2) - 1;
localparam DEPTH64_LOW = (COORD_WIDTH) - (DEPTH_BIT_WIDTH/2);

logic signed [2:0][2:0][COORD_WIDTH-1:0] triangle_coords;
logic signed [2:0][3:0][COORD_WIDTH-1:0] projected_coords;
logic signed [3:0][3:0][COORD_WIDTH-1:0] model_matrix;
logic signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix;
logic signed [3:0][3:0][COORD_WIDTH-1:0] projection_matrix;

logic signed [3:0][COORD_WIDTH-1:0] screen_vert_1, screen_vert_2, screen_vert_3;

logic signed [2:0][COORD_WIDTH-1:0] bary_p, bary_a, bary_b, bary_c;
logic bary_init, bary_valid_in, bary_reset, bary_valid_out, bary_init_done, bary_init_failed;
logic use_barycentric;
logic [2*COORD_WIDTH-1:0] bary_u, bary_v, bary_w;
logic signed [COORD_WIDTH-1:0] out_u_pipe, out_v_pipe, out_w_pipe;
logic signed [COORD_WIDTH-1:0] out_u_pipe1, out_v_pipe1, out_w_pipe1;

logic start_rendering, start_projection;
logic rendering_busy, projection_busy;
logic rendering_done, projection_done;
logic rendering_valid, projection_valid;

logic signed [2*COORD_WIDTH-1:0] interpolated_depth, interpolated_depth_u, interpolated_depth_v, interpolated_depth_w;
logic [DEPTH_BIT_WIDTH-1:0] max_depth;

logic signed [COORD_WIDTH-1:0] tri_x, tri_y;
logic signed [COORD_WIDTH-1:0] out_x, out_y;
logic signed [COORD_WIDTH-1:0] out_x_pipe, out_y_pipe;
logic signed [COORD_WIDTH-1:0] x0, y0, x1, y1, x2, y2;

logic [1:0] projection_status;

always_comb begin
    test = depth;
    triangle_coords[0][0] = 32'hffff0000; // X
    triangle_coords[0][1] = 32'h00000000; // Y
    triangle_coords[0][2] = 32'hffff0000; // Z

    triangle_coords[1][0] = 32'h00010000;
    triangle_coords[1][1] = 32'h00000000;
    triangle_coords[1][2] = 32'hffff0000;

    triangle_coords[2][0] = 32'h00010000;
    triangle_coords[2][1] = 32'h00000000;
    triangle_coords[2][2] = 32'h00010000;

    projection_matrix[0][0] = 32'h00015ba6;
    projection_matrix[0][1] = 32'b0;
    projection_matrix[0][2] = 32'b0;
    projection_matrix[0][3] = 32'b0;
    projection_matrix[1][0] = 32'b0;
    projection_matrix[1][1] = 32'h00026a0a;
    projection_matrix[1][2] = 32'b0;
    projection_matrix[1][3] = 32'b0;
    projection_matrix[2][0] = 32'b0;
    projection_matrix[2][1] = 32'b0;
    projection_matrix[2][2] = 32'hfffeff7d;
    projection_matrix[2][3] = 32'hffffccc0;
    projection_matrix[3][0] = 32'b0;
    projection_matrix[3][1] = 32'b0;
    projection_matrix[3][2] = 32'hffff0000; // -1, same as opengl's
    projection_matrix[3][3] = 32'b0;

    view_matrix[0][0] = 32'h00010000; // 1 in Q16.16
    view_matrix[0][1] = 0;
    view_matrix[0][2] = 0;
    view_matrix[0][3] = x_in;
    view_matrix[1][0] = 0;
    view_matrix[1][1] = 32'h00010000;
    view_matrix[1][2] = 0;
    view_matrix[1][3] = y_in;
    view_matrix[2][0] = 0;
    view_matrix[2][1] = 0; 
    view_matrix[2][2] = 32'h00010000;
    view_matrix[2][3] = z_in; //-6
    view_matrix[3][0] = 0; 
    view_matrix[3][1] = 0;
    view_matrix[3][2] = 0; 
    view_matrix[3][3] = 32'h00010000;

    model_matrix[0][0] = 32'h00010000; // 1 in Q16.16
    model_matrix[0][1] = 0;
    model_matrix[0][2] = 0;
    model_matrix[0][3] = 0;
    model_matrix[1][0] = 0;
    model_matrix[1][1] = 32'h00010000;
    model_matrix[1][2] = 0;
    model_matrix[1][3] = 0;
    model_matrix[2][0] = 0;
    model_matrix[2][1] = 0; 
    model_matrix[2][2] = 32'h00010000;
    model_matrix[2][3] = 0;
    model_matrix[3][0] = 0; 
    model_matrix[3][1] = 0;
    model_matrix[3][2] = 0; 
    model_matrix[3][3] = 32'h00010000;
end

enum {IDLE, INIT_TRI, PROJECTING, BARY_INIT, NO_BARY_DRAWING, BARY_DRAWING, DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        state <= IDLE;
        busy <= 0;
        start_projection <= 0;
        start_rendering <= 0;
        done <= 0;
        bary_init <= 0;
        use_barycentric <= 0;
        bary_valid_in <= 0;
        interpolated_depth_u <= 0;
        interpolated_depth_v <= 0;
        interpolated_depth_w <= 0;
        max_depth <= 0;
        out_x_pipe <= 0;
        out_y_pipe <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (start) begin
                    state <= INIT_TRI;
                    busy <= 1;
                end
                done <= 0;
                raster_state <= 0;
            end
            INIT_TRI: begin
                start_projection <= 1;
                state <= PROJECTING;
                raster_state <= 1;
                bary_reset <= 1;
            end
            PROJECTING: begin
                raster_state <= 2;
                start_projection <= 0;
                bary_reset <= 0;
                if (projection_done) begin
                    if (projection_valid) begin
                        state <= BARY_INIT;

                        // Initialize barycentric calculator in screenspace, set z to 1, truncate decimals;
                        bary_a[0] <= $signed(projected_coords[0][0]) >>> COORD_WIDTH/2;
                        bary_a[1] <= $signed(projected_coords[0][1]) >>> COORD_WIDTH/2;
                        bary_a[2] <= (COORD_WIDTH'('b1));
                        bary_b[0] <= $signed(projected_coords[1][0]) >>> COORD_WIDTH/2;
                        bary_b[1] <= $signed(projected_coords[1][1]) >>> COORD_WIDTH/2;
                        bary_b[2] <= (COORD_WIDTH'('b1));
                        bary_c[0] <= $signed(projected_coords[2][0]) >>> COORD_WIDTH/2;
                        bary_c[1] <= $signed(projected_coords[2][1]) >>> COORD_WIDTH/2;
                        bary_c[2] <= (COORD_WIDTH'('b1));
                        bary_init <= 1;

                        // Retrieve results from projection
                        x0 <= $signed(projected_coords[0][0]) >>> COORD_WIDTH/2;
                        y0 <= $signed(projected_coords[0][1]) >>> COORD_WIDTH/2;
                        x1 <= $signed(projected_coords[1][0]) >>> COORD_WIDTH/2;
                        y1 <= $signed(projected_coords[1][1]) >>> COORD_WIDTH/2;
                        x2 <= $signed(projected_coords[2][0]) >>> COORD_WIDTH/2;
                        y2 <= $signed(projected_coords[2][1]) >>> COORD_WIDTH/2;

                        screen_vert_1 <= projected_coords[0];
                        screen_vert_2 <= projected_coords[1];
                        screen_vert_3 <= projected_coords[2];

                        // Set max depth
                        if (projected_coords[0][2] >= projected_coords[1][2] && projected_coords[0][2] >= projected_coords[2][2]) begin
                            max_depth <= {~projected_coords[0][2][DEPTH_HIGH], projected_coords[0][2][DEPTH_HIGH-1:DEPTH_LOW]};
                        end else if (projected_coords[1][2] >= projected_coords[0][2] && projected_coords[1][2] >= projected_coords[2][2]) begin
                            max_depth <= {~projected_coords[1][2][DEPTH_HIGH], projected_coords[1][2][DEPTH_HIGH-1:DEPTH_LOW]};
                        end else begin
                            max_depth <= {~projected_coords[2][2][DEPTH_HIGH], projected_coords[2][2][DEPTH_HIGH-1:DEPTH_LOW]};
                        end
                    end else begin
                        state <= DONE;
                    end
                end else begin
                    state <= PROJECTING;
                end
            end
            BARY_INIT: begin
                raster_state <= 3;
                bary_init <= 0;
                if (bary_init_done) begin
                    state <= BARY_DRAWING;
                    start_rendering <= 1;
                    use_barycentric <= 1;
                end else if (bary_init_failed) begin
                    state <= NO_BARY_DRAWING;
                    start_rendering <= 1;
                    use_barycentric <= 0;
                end else begin
                    state <= BARY_INIT;
                end

                // Clamp depth to 0
                screen_vert_1[2] <= $signed(screen_vert_1[2]) < 0 ? 0 : screen_vert_1[2];
                screen_vert_2[2] <= $signed(screen_vert_2[2]) < 0 ? 0 : screen_vert_2[2];
                screen_vert_3[2] <= $signed(screen_vert_3[2]) < 0 ? 0 : screen_vert_3[2];
            end
            BARY_DRAWING: begin
                raster_state <= 4;
                start_rendering <= 0;

                if (rendering_valid) begin
                    bary_p[0] <= $signed(tri_x);
                    bary_p[1] <= $signed(tri_y);
                    bary_p[2] <= (COORD_WIDTH'('b1));
                    bary_valid_in <= 1;
                end else begin
                    bary_valid_in <= 0;
                end

                if (bary_valid_out) begin
                    out_u_pipe1 <= $signed(bary_u[BARY_HIGH:BARY_LOW]);
                    out_v_pipe1 <= $signed(bary_v[BARY_HIGH:BARY_LOW]);
                    out_w_pipe1 <= $signed(bary_w[BARY_HIGH:BARY_LOW]);
                    interpolated_depth_u <= $signed(screen_vert_1[2])*$signed(bary_u[BARY_HIGH:BARY_LOW]);
                    interpolated_depth_v <= $signed(screen_vert_2[2])*$signed(bary_v[BARY_HIGH:BARY_LOW]);
                    interpolated_depth_w <= $signed(screen_vert_3[2])*$signed(bary_w[BARY_HIGH:BARY_LOW]);
                    out_x_pipe <= tri_x_pipe[0];
                    out_y_pipe <= tri_y_pipe[0];
                end

                if (rendering_done_pipe[0]) begin
                    state <= DONE;
                    busy <= 0;
                end else begin
                    state <= BARY_DRAWING;
                end
            end
            NO_BARY_DRAWING: begin
                raster_state <= 5;
                start_rendering <= 0;
                if (rendering_done_pipe[0]) begin
                    state <= DONE;
                    busy <= 0;
                end else begin
                    state <= NO_BARY_DRAWING;
                    out_x_pipe <= tri_x_pipe[0];
                    out_y_pipe <= tri_y_pipe[0];
                end
            end
            DONE: begin
                raster_state <= 6;
                state <= IDLE;
                busy <= 0;
                done <= 1;
            end
        endcase
    end
end

localparam BARYCENTRIC_DELAY = 14; // 14 from barycentric
logic signed [BARYCENTRIC_DELAY-1:0][COORD_WIDTH-1:0] tri_x_pipe, tri_y_pipe;
logic [BARYCENTRIC_DELAY-1:0] rendering_done_pipe;
logic [BARYCENTRIC_DELAY-1+2:0] rendering_valid_pipe; // +2 to account for depth calculation and final pipe
always_ff @(posedge clk_in) begin
    tri_x_pipe <= {tri_x, tri_x_pipe[BARYCENTRIC_DELAY-1:1]};
    tri_y_pipe <= {tri_y, tri_y_pipe[BARYCENTRIC_DELAY-1:1]};
    rendering_done_pipe <= {rendering_done, rendering_done_pipe[BARYCENTRIC_DELAY-1:1]};
    rendering_valid_pipe <= {rendering_valid, rendering_valid_pipe[BARYCENTRIC_DELAY-1+2:1]};
end

always_ff @(posedge clk_in) begin
    out_x <= out_x_pipe;
    out_y <= out_y_pipe;
    out_u_pipe <= out_u_pipe1;
    out_v_pipe <= out_v_pipe1;
    out_w_pipe <= out_w_pipe1;
    interpolated_depth <= interpolated_depth_u + interpolated_depth_v + interpolated_depth_w;

    x <= out_x;
    y <= out_y;
    out_u <= out_u_pipe;
    out_v <= out_v_pipe;
    out_w <= out_w_pipe;
    depth <= use_barycentric ? {~interpolated_depth[DEPTH64_HIGH], interpolated_depth[DEPTH64_HIGH-1:DEPTH64_LOW]} : max_depth;
    if ((out_x < $signed(0)) || (out_x >= $signed(FB_WIDTH)) || (out_y < $signed(0)) || (out_y >= $signed(FB_HEIGHT))) begin
        drawing <= 0;
    end else begin
        drawing <= rendering_valid_pipe[0];
    end
    proj_status <= projection_status;
end

project_triangle #(.COORD_WIDTH(COORD_WIDTH), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT)) project (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start(start_projection),
    .triangle_verts(triangle_coords),
    .model_matrix(model_matrix),
    .view_matrix(view_matrix),
    .projection_matrix(projection_matrix),
    .projected_verts(projected_coords),
    .busy(projection_busy),
    .valid(projection_valid),
    .status(projection_status),
    .done(projection_done)
);

bresenhamTriangleFill #(.COORD_WIDTH(COORD_WIDTH)) draw_triangle (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start_draw(start_rendering),
    .oe(1'b1),
    .x0(x0),
    .y0(y0),
    .x1(x1),
    .y1(y1),
    .x2(x2),
    .y2(y2),
    .x(tri_x),
    .y(tri_y),
    .drawing(rendering_valid),
    .busy(rendering_busy),
    .done(rendering_done)
);

computeBarycentric #(.COORD_WIDTH(2*COORD_WIDTH)) barycentric (
    .clk_in(clk_in),
    .rst_in(bary_reset),
    .p(bary_p),
    .a(bary_a),
    .b(bary_b),
    .c(bary_c),
    .valid_in(bary_valid_in),
    .init(bary_init),
    .u(bary_u),
    .v(bary_v),
    .w(bary_w),
    .valid_out(bary_valid_out),
    .init_done(bary_init_done),
    .init_failed(bary_init_failed)
);
endmodule

`default_nettype wire
