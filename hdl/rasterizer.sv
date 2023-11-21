`timescale 1ns / 1ps
`default_nettype none
module rasterizer #(parameter WIREFRAME = 0, parameter COORD_WIDTH = 32) (
    input wire clk_in,
    input wire rst_in,
    input wire start,

    output logic [COORD_WIDTH-1:0] x, y,
    output logic drawing,
    output logic busy,
    output logic done
);

logic signed [2:0][2:0][COORD_WIDTH-1:0] triangle_coords;
logic signed [2:0][2:0][COORD_WIDTH-1:0] projected_coords;
logic signed [3:0][3:0][COORD_WIDTH-1:0] model_matrix;
logic signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix;
logic signed [3:0][3:0][COORD_WIDTH-1:0] projection_matrix;

logic start_rendering, start_projection;
logic rendering_busy, projection_busy;
logic rendering_done, projection_done;
logic rendering_valid, projection_valid;

always_comb begin
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
    projection_matrix[3][2] = 32'hffff0000; // -1
    projection_matrix[3][3] = 32'b0;

    view_matrix[0][0] = 32'h00010000; // 1 in Q16.16
    view_matrix[0][1] = 0;
    view_matrix[0][2] = 0;
    view_matrix[0][3] = 0;
    view_matrix[1][0] = 0;
    view_matrix[1][1] = 32'h00010000;
    view_matrix[1][2] = 0;
    view_matrix[1][3] = 32'h00010000;
    view_matrix[2][0] = 0;
    view_matrix[2][1] = 0; 
    view_matrix[2][2] = 32'h00010000;
    view_matrix[2][3] = 32'hfffa0000; //-6
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

localparam SF = $pow(2.0, -16.0);
logic [COORD_WIDTH-1:0] out_x, out_y;
logic [COORD_WIDTH-1:0] x0, y0, x1, y1, x2, y2;

enum {IDLE, INIT_TRI, PROJECTING, DRAWING, DONE} state;

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        state <= IDLE;
        busy <= 0;
        start_projection <= 0;
        start_rendering <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (start) begin
                    state <= INIT_TRI; //TODO: ???? Why dont this start
                    busy <= 1;
                end
            end
            INIT_TRI: begin
                start_projection <= 1;
                state <= PROJECTING;
            end
            PROJECTING: begin
                if (projection_done) begin
                    if (projection_valid) begin
                        state <= DRAWING;
                        start_rendering <= 1;

                        // Retrieve results from projection
                        x0 <= projected_coords[0][0] >> 16;
                        y0 <= projected_coords[0][1] >> 16;
                        x1 <= projected_coords[1][0] >> 16;
                        y1 <= projected_coords[1][1] >> 16;
                        x2 <= projected_coords[2][0] >> 16;
                        y2 <= projected_coords[2][1] >> 16;
                    end else begin
                        state <= DONE;
                    end
                end else begin
                    start_projection <= 0;
                    state <= PROJECTING;
                end
            end
            DRAWING: begin
                if (rendering_done) begin
                    state <= DONE;
                    busy <= 0;
                    // done <= 1;
                end else begin
                    start_rendering <= 0;
                    state <= DRAWING;
                end
            end
            DONE: begin
                state <= IDLE;
                busy <= 0;
                // done <= 1;
            end
        endcase
    end
end

always_ff @(posedge clk_in) begin
    x <= out_x;
    y <= out_y;
    drawing <= rendering_valid;
    done <= rendering_done;
end

project_triangle #(.COORD_WIDTH(COORD_WIDTH)) project (
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
