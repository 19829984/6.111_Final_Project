`timescale 1ns / 1ps 
`default_nettype none
module world_drawer #(parameter COORD_WIDTH=32, parameter WIREFRAME = 0, parameter DEPTH_BIT_WIDTH=16, parameter FB_WIDTH=320, parameter FB_HEIGHT=180, parameter FB_BIT_WIDTH=100, parameter WORLD_SIZE=100, parameter WORLD_BITS=7) (
    input wire clk_in,
    input wire rst_in,
    input wire start,
    input wire signed [3*COORD_WIDTH/2:0] world_read,
    input wire signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix,

    output logic signed [COORD_WIDTH-1:0] x_cor,
    output logic signed [COORD_WIDTH-1:0] y_cor,
    output logic signed [COORD_WIDTH-1:0] z_cor,
    output logic signed [6:0] test,
    output logic [WORLD_BITS-1:0] world_read_addr,
    output logic [COORD_WIDTH-1:0] x, y,
    output logic [DEPTH_BIT_WIDTH-1:0] depth,
    output logic [FB_BIT_WIDTH-1:0] color,
    output logic drawing,
    output logic busy,
    output logic done
);
    logic [WORLD_BITS-1:0] current_cube;
    logic cube_start;
    logic cube_busy;
    logic cube_done;

    logic [1:0] wait_until_draw;
    enum {IDLE, INIT_READ, NEW_CUBE, DRAWING, DONE} state;

    logic signed [COORD_WIDTH-1:0] x_corner;
    logic signed [COORD_WIDTH-1:0] y_corner;
    logic signed [COORD_WIDTH-1:0] z_corner;
    logic valid_cube;
    assign valid_cube = world_read[3*COORD_WIDTH/2];

    //assign color = {1'b1, current_cube[3:0], 3'b1};
    cube_drawer #(.COORD_WIDTH(COORD_WIDTH), .DEPTH_BIT_WIDTH(DEPTH_BIT_WIDTH), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT), .FB_BIT_WIDTH(FB_BIT_WIDTH))  (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .start(cube_start),
        .x_corner(x_corner),
        .y_corner(y_corner),
        .z_corner(z_corner),
        .view_matrix(view_matrix),
        .x(x),
        .y(y),
        .depth(depth),
        .color(color),
        .drawing(drawing),
        .busy(cube_busy),
        .done(cube_done)
    );

    assign world_read_addr = current_cube;
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            test <= 0;
        end else begin
            if (state == DONE) begin
                test[6] <= 1;
            end
            if (state == DRAWING && current_cube == 6) begin
                test[5] <= 1;
            end
            if (state == INIT_READ && current_cube == 6) begin
                test[4] <= 1;
            end
            if (wait_until_draw == 2'b11 && current_cube == 6) begin
                test[3] <= 1;
            end
            if (cube_busy && current_cube == 6) begin
                test[2] <= 1;
            end
            if (cube_done && current_cube == 6) begin
                test[1] <= 1;
            end
            if (cube_start && current_cube == 6) begin
                test[0] <= 1;
            end
        end

        if (rst_in) begin
            current_cube <= 0;
            wait_until_draw <= 0;
            state <= IDLE;
        end else begin
            case (state)
               IDLE: begin
                    if (start) begin
                        wait_until_draw <= 0;
                        current_cube <= 0;
                        state <= INIT_READ;
                    end
                    done <= 0;
               end
               INIT_READ: begin
                    if (wait_until_draw == 2'b11 && valid_cube) begin
                        wait_until_draw <= 0;
                        x_corner[COORD_WIDTH-1:COORD_WIDTH/2] <= world_read[3*COORD_WIDTH/2-1:COORD_WIDTH];
                        y_corner[COORD_WIDTH-1:COORD_WIDTH/2] <= world_read[COORD_WIDTH-1:COORD_WIDTH/2];
                        z_corner[COORD_WIDTH-1:COORD_WIDTH/2] <= world_read[COORD_WIDTH/2-1:0];
                        cube_start <= 1;
                        state <= DRAWING;

                    end else if (wait_until_draw == 2'b11 && ~valid_cube) begin
                        wait_until_draw <= 0;
                        if (current_cube < WORLD_SIZE - 1) begin
                            current_cube <= current_cube + 1;
                        end else begin
                            state <= DONE;
                            done <= 1;
                            busy <= 0;
                        end
                    end else begin
                        wait_until_draw <= wait_until_draw + 1;
                    end
               end
               DRAWING: begin
                    if (cube_busy) begin
                        cube_start <= 0;
                    end
                    if (cube_done && ~cube_start) begin
                        if (current_cube < WORLD_SIZE - 1) begin
                            current_cube <= current_cube + 1;
                            state <= INIT_READ;
                        end else begin
                            state <= DONE;
                            done <= 1;
                            busy <= 0;
                        end
                    end
               end
               DONE: begin
                    done <= 0;
                    state <= IDLE;
               end
            endcase
        end

        x_cor <= x_corner;
        y_cor <= y_corner;
        z_cor <= z_corner;
    end
endmodule
