`timescale 1ns / 1ps
`default_nettype none
module rasterizer #(parameter WIREFRAME = 0, parameter COORD_WIDTH = 32, parameter DEPTH_BIT_WIDTH = 16,
                    parameter FB_WIDTH = 320, parameter FB_HEIGHT = 180) (
    input wire clk_in,
    input wire rst_in,
    input wire start,
    input wire signed [2:0][2:0][COORD_WIDTH-1:0] triangle_coords,
    input wire signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix,

    output logic [COORD_WIDTH-1:0] x, y,
    output logic [DEPTH_BIT_WIDTH-1:0] depth,
    output logic drawing,
    output logic [2:0] raster_state,
    output logic [1:0] proj_status,
    output logic busy,
    output logic done,
    output logic signed [31:0] test
);
localparam DEPTH_HIGH = (COORD_WIDTH/2) + (DEPTH_BIT_WIDTH/4) - 1;
localparam DEPTH_LOW = (COORD_WIDTH/2) - (DEPTH_BIT_WIDTH/4);

logic signed [2:0][3:0][COORD_WIDTH-1:0] projected_coords;
logic signed [3:0][3:0][COORD_WIDTH-1:0] model_matrix;
//logic signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix;
logic signed [3:0][3:0][COORD_WIDTH-1:0] projection_matrix;

logic start_rendering, start_projection;
logic rendering_busy, projection_busy;
logic rendering_done, projection_done;
logic rendering_valid, projection_valid;

logic [1:0] projection_status;

always_comb begin
    test = depth;
    //triangle_coords[0][0] = 32'hffff0000; // X
    //triangle_coords[0][1] = 32'h00000000; // Y
    //triangle_coords[0][2] = 32'hffff0000; // Z

    //triangle_coords[1][0] = 32'h00010000;
    //triangle_coords[1][1] = 32'h00000000;
    //triangle_coords[1][2] = 32'hffff0000;

    //triangle_coords[2][0] = 32'h00010000;
    //triangle_coords[2][1] = 32'h00000000;
    //triangle_coords[2][2] = 32'h00010000;

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

    // view_matrix[0][0] = 32'h00010000; // 1 in Q16.16
    // view_matrix[0][1] = 0;
    // view_matrix[0][2] = 0;
    // view_matrix[0][3] = x_in;
    // view_matrix[1][0] = 0;
    // view_matrix[1][1] = 32'h00010000;
    // view_matrix[1][2] = 0;
    // view_matrix[1][3] = y_in;
    // view_matrix[2][0] = 0;
    // view_matrix[2][1] = 0; 
    // view_matrix[2][2] = 32'h00010000;
    // view_matrix[2][3] = z_in; //-6
    // view_matrix[3][0] = 0; 
    // view_matrix[3][1] = 0;
    // view_matrix[3][2] = 0; 
    // view_matrix[3][3] = 32'h00010000;
    // [1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0, 0, 0, 0, 1];

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

logic signed [COORD_WIDTH-1:0] out_x, out_y;
logic signed [COORD_WIDTH-1:0] x0, y0, x1, y1, x2, y2;

enum {IDLE, INIT_TRI, PROJECTING, DRAWING, DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        state <= IDLE;
        busy <= 0;
        start_projection <= 0;
        start_rendering <= 0;
        done <= 0;
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
            end
            PROJECTING: begin
                raster_state <= 2;
                start_projection <= 0;
                if (projection_done) begin
                    if (projection_valid) begin
                        state <= DRAWING;
                        start_rendering <= 1;

                        // Retrieve results from projection
                        x0 <= $signed(projected_coords[0][0]) >>> 16;
                        y0 <= $signed(projected_coords[0][1]) >>> 16;
                        x1 <= $signed(projected_coords[1][0]) >>> 16;
                        y1 <= $signed(projected_coords[1][1]) >>> 16;
                        x2 <= $signed(projected_coords[2][0]) >>> 16;
                        y2 <= $signed(projected_coords[2][1]) >>> 16;

                        // Set min depth
                        if (projected_coords[1][2] >= projected_coords[0][2] && projected_coords[2][2] >= projected_coords[0][2]) begin
                            depth[DEPTH_BIT_WIDTH-1:DEPTH_BIT_WIDTH/2] <= {~projected_coords[0][2][DEPTH_HIGH], projected_coords[0][2][DEPTH_HIGH-1:DEPTH_LOW]};
                        end else if (projected_coords[0][2] >= projected_coords[1][2] && projected_coords[2][2] >= projected_coords[0][2]) begin
                            depth[DEPTH_BIT_WIDTH-1:DEPTH_BIT_WIDTH/2] <= {~projected_coords[1][2][DEPTH_HIGH], projected_coords[1][2][DEPTH_HIGH-1:DEPTH_LOW]};
                        end else begin
                            depth[DEPTH_BIT_WIDTH-1:DEPTH_BIT_WIDTH/2] <= {~projected_coords[2][2][DEPTH_HIGH], projected_coords[2][2][DEPTH_HIGH-1:DEPTH_LOW]};
                        end
                        // there are still bugs
                    end else begin
                        state <= DONE;
                    end
                end else begin
                    state <= PROJECTING;
                end
            end
            DRAWING: begin
                raster_state <= 3;
                start_rendering <= 0;
                if (rendering_done) begin
                    state <= DONE;
                    busy <= 0;
                end else begin
                    state <= DRAWING;
                end
            end
            DONE: begin
                raster_state <= 4;
                state <= IDLE;
                busy <= 0;
                done <= 1;
            end
        endcase
    end
end

always_ff @(posedge clk_in) begin
    x <= out_x;
    y <= out_y;
    if ((out_x < $signed(0)) || (out_x >= $signed(FB_WIDTH)) || (out_y < $signed(0)) || (out_y >= $signed(FB_HEIGHT))) begin
        drawing <= 0;
    end else begin
        drawing <= rendering_valid;
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
    .x(out_x),
    .y(out_y),
    .drawing(rendering_valid),
    .busy(rendering_busy),
    .done(rendering_done)
);
endmodule

`default_nettype wire
