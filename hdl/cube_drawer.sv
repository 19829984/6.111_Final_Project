`timescale 1ns / 1ps 
`default_nettype none
module cube_drawer #(parameter COORD_WIDTH=32, parameter WIREFRAME = 0, parameter DEPTH_BIT_WIDTH=16, parameter FB_WIDTH=320, parameter FB_HEIGHT=180, parameter FB_BIT_WIDTH=100) (
    input wire clk_in,
    input wire rst_in,
    input wire start,
    input wire signed [COORD_WIDTH-1:0] x_corner,
    input wire signed [COORD_WIDTH-1:0] y_corner,
    input wire signed [COORD_WIDTH-1:0] z_corner,
    input wire signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix,

    output logic [COORD_WIDTH-1:0] x, y,
    output logic [DEPTH_BIT_WIDTH-1:0] depth,
    output logic [FB_BIT_WIDTH-1:0] color,
    output logic drawing,
    output logic busy,
    output logic done
);
    logic signed [COORD_WIDTH-1:0] cube_width = 32'h0001_0000;

    logic [3:0] tri_index; // which triangle we're on
    logic drawer_start;
    logic drawer_busy;
    logic drawer_done;
    logic signed [COORD_WIDTH-1:0] x_cor;
    logic signed [COORD_WIDTH-1:0] y_cor;
    logic signed [COORD_WIDTH-1:0] z_cor;
    logic signed [2:0][2:0][COORD_WIDTH-1:0] triangle_coords;
    enum {IDLE, INIT_TRI, DRAW_TRI, DONE} state;

    rasterizer #(
        .WIREFRAME(WIREFRAME),
        .COORD_WIDTH(COORD_WIDTH),
        .DEPTH_BIT_WIDTH(DEPTH_BIT_WIDTH),
        .FB_WIDTH(FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) drawer (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .start(drawer_start),
        .triangle_coords(triangle_coords),
        .view_matrix(view_matrix),
        .x(x),
        .y(y),
        .depth(depth),
        .drawing(drawing),
        .busy(drawer_busy),
        .done(drawer_done),
        .raster_state(),
        .proj_status(),
        .test()
    );

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            tri_index <= 0;
            triangle_coords <= 0;
            busy <= 0;
            done <= 0;
            state <= IDLE;
            color <= 8'hFF;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        x_cor <= x_corner;
                        y_cor <= y_corner;
                        z_cor <= z_corner;
                        color <= 8'hFF;
                        state <= INIT_TRI;
                        busy <= 1;
                    end
                    tri_index <= 0;
                    done <= 0;
                end
                INIT_TRI: begin
                    case (tri_index) 
                        4'b0000: begin
                            triangle_coords[0][0] <= x_cor;
                            triangle_coords[0][1] <= y_cor;
                            triangle_coords[0][2] <= z_cor;

                            triangle_coords[1][0] <= x_cor;
                            triangle_coords[1][1] <= y_cor + cube_width;
                            triangle_coords[1][2] <= z_cor;

                            triangle_coords[2][0] <= x_cor + cube_width;
                            triangle_coords[2][1] <= y_cor;
                            triangle_coords[2][2] <= z_cor;
                        end
                        4'b0001: begin
                            triangle_coords[0][0] <= x_cor + cube_width;
                            triangle_coords[0][1] <= y_cor + cube_width;
                            triangle_coords[0][2] <= z_cor;

                            triangle_coords[1][0] <= x_cor + cube_width;
                            triangle_coords[1][1] <= y_cor;
                            triangle_coords[1][2] <= z_cor;

                            triangle_coords[2][0] <= x_cor;
                            triangle_coords[2][1] <= y_cor + cube_width;
                            triangle_coords[2][2] <= z_cor;
                        end
                        4'b0010: begin
                            triangle_coords[0][0] <= x_cor;
                            triangle_coords[0][1] <= y_cor;
                            triangle_coords[0][2] <= z_cor;

                            triangle_coords[1][0] <= x_cor + cube_width;
                            triangle_coords[1][1] <= y_cor;
                            triangle_coords[1][2] <= z_cor;

                            triangle_coords[2][0] <= x_cor;
                            triangle_coords[2][1] <= y_cor;
                            triangle_coords[2][2] <= z_cor + cube_width;
                        end
                        4'b0011: begin
                            triangle_coords[0][0] <= x_cor + cube_width;
                            triangle_coords[0][1] <= y_cor;
                            triangle_coords[0][2] <= z_cor + cube_width;

                            triangle_coords[1][0] <= x_cor;
                            triangle_coords[1][1] <= y_cor;
                            triangle_coords[1][2] <= z_cor + cube_width;

                            triangle_coords[2][0] <= x_cor + cube_width;
                            triangle_coords[2][1] <= y_cor;
                            triangle_coords[2][2] <= z_cor;
                        end
                        4'b0100: begin
                            triangle_coords[0][0] <= x_cor;
                            triangle_coords[0][1] <= y_cor;
                            triangle_coords[0][2] <= z_cor;

                            triangle_coords[1][0] <= x_cor;
                            triangle_coords[1][1] <= y_cor;
                            triangle_coords[1][2] <= z_cor + cube_width;

                            triangle_coords[2][0] <= x_cor;
                            triangle_coords[2][1] <= y_cor + cube_width;
                            triangle_coords[2][2] <= z_cor;
                        end
                        4'b0101: begin
                            triangle_coords[0][0] <= x_cor;
                            triangle_coords[0][1] <= y_cor + cube_width;
                            triangle_coords[0][2] <= z_cor + cube_width;

                            triangle_coords[1][0] <= x_cor;
                            triangle_coords[1][1] <= y_cor + cube_width;
                            triangle_coords[1][2] <= z_cor;

                            triangle_coords[2][0] <= x_cor;
                            triangle_coords[2][1] <= y_cor;
                            triangle_coords[2][2] <= z_cor + cube_width;
                        end
                        4'b0110: begin
                            triangle_coords[0][0] <= x_cor + cube_width;
                            triangle_coords[0][1] <= y_cor + cube_width;
                            triangle_coords[0][2] <= z_cor + cube_width;

                            triangle_coords[1][0] <= x_cor;
                            triangle_coords[1][1] <= y_cor + cube_width;
                            triangle_coords[1][2] <= z_cor + cube_width;

                            triangle_coords[2][0] <= x_cor + cube_width;
                            triangle_coords[2][1] <= y_cor;
                            triangle_coords[2][2] <= z_cor + cube_width;
                        end
                        4'b0111: begin
                            triangle_coords[0][0] <= x_cor;
                            triangle_coords[0][1] <= y_cor;
                            triangle_coords[0][2] <= z_cor + cube_width;

                            triangle_coords[1][0] <= x_cor + cube_width;
                            triangle_coords[1][1] <= y_cor;
                            triangle_coords[1][2] <= z_cor + cube_width;

                            triangle_coords[2][0] <= x_cor;
                            triangle_coords[2][1] <= y_cor + cube_width;
                            triangle_coords[2][2] <= z_cor + cube_width;
                        end
                        4'b1000: begin
                            triangle_coords[0][0] <= x_cor + cube_width;
                            triangle_coords[0][1] <= y_cor + cube_width;
                            triangle_coords[0][2] <= z_cor + cube_width;

                            triangle_coords[1][0] <= x_cor + cube_width;
                            triangle_coords[1][1] <= y_cor + cube_width;
                            triangle_coords[1][2] <= z_cor;

                            triangle_coords[2][0] <= x_cor;
                            triangle_coords[2][1] <= y_cor + cube_width;
                            triangle_coords[2][2] <= z_cor + cube_width;
                        end
                        4'b1001: begin
                            triangle_coords[0][0] <= x_cor;
                            triangle_coords[0][1] <= y_cor + cube_width;
                            triangle_coords[0][2] <= z_cor;

                            triangle_coords[1][0] <= x_cor;
                            triangle_coords[1][1] <= y_cor + cube_width;
                            triangle_coords[1][2] <= z_cor + cube_width;

                            triangle_coords[2][0] <= x_cor + cube_width;
                            triangle_coords[2][1] <= y_cor + cube_width;
                            triangle_coords[2][2] <= z_cor;
                        end
                        4'b1010: begin
                            triangle_coords[0][0] <= x_cor + cube_width;
                            triangle_coords[0][1] <= y_cor + cube_width;
                            triangle_coords[0][2] <= z_cor + cube_width;

                            triangle_coords[1][0] <= x_cor + cube_width;
                            triangle_coords[1][1] <= y_cor;
                            triangle_coords[1][2] <= z_cor + cube_width;

                            triangle_coords[2][0] <= x_cor + cube_width;
                            triangle_coords[2][1] <= y_cor + cube_width;
                            triangle_coords[2][2] <= z_cor;
                        end
                        4'b1011: begin
                            triangle_coords[0][0] <= x_cor + cube_width;
                            triangle_coords[0][1] <= y_cor;
                            triangle_coords[0][2] <= z_cor;

                            triangle_coords[1][0] <= x_cor + cube_width;
                            triangle_coords[1][1] <= y_cor + cube_width;
                            triangle_coords[1][2] <= z_cor;

                            triangle_coords[2][0] <= x_cor + cube_width;
                            triangle_coords[2][1] <= y_cor;
                            triangle_coords[2][2] <= z_cor + cube_width;
                        end
                    endcase
                    state <= DRAW_TRI;
                    drawer_start <= 1;
                    color[FB_BIT_WIDTH-1:FB_BIT_WIDTH-4] <= ~tri_index[3:0];  // for debug
                end
                DRAW_TRI: begin
                    if (drawer_busy) begin
                        drawer_start <= 0;
                    end
                    if (drawer_done) begin
                        if (tri_index < 4'b1011) begin
                            tri_index <= tri_index + 1;
                            state <= INIT_TRI;
                        end else begin
                            state <= DONE;
                            done <= 1;
                            busy <= 0;
                        end

                        // Let's draw one triangle for now
                        //state <= DONE;
                        //done <= 1;
                        //busy <= 0;
                    end
                end
                DONE: begin
                    state <= IDLE;
                    done <= 0;
                end
            endcase
        end
    end

endmodule
