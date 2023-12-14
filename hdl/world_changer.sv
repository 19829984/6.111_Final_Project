`timescale 1ns / 1ps
`default_nettype none
module world_changer #(parameter COORD_WIDTH=32, parameter WORLD_BITS=7, parameter WORLD_SIZE=128) (
    input wire clk_in,
    input wire rst_in,
    input wire start,
    input wire [15:0] sw,
    input wire [3:0] btn,
    input wire signed [2:0][COORD_WIDTH-1:0] forward_vec,
    input wire [3*COORD_WIDTH/2:0] world_read,
    output logic signed [COORD_WIDTH-1:0] x_input,
    output logic signed [COORD_WIDTH-1:0] y_input,
    output logic signed [COORD_WIDTH-1:0] z_input,
    output logic signed [COORD_WIDTH-1:0] rot_angle,
    output logic signed [COORD_WIDTH-1:0] side_angle,
    output logic [WORLD_BITS-1:0] world_read_addr,
    output logic [WORLD_BITS-1:0] world_write_addr,
    output logic signed [3*COORD_WIDTH/2:0] world_write,
    output logic busy,
    output logic done
);
    logic [1:0] read_counter;
    enum {IDLE, INIT, LOOP, DONE} state;

    always_ff @(posedge clk_in) begin
        case (state)
            IDLE: begin
                if (start) begin
                    if (sw[3]) begin
                      y_input <= y_input + 32'h0000019a;
                    end
                    if (sw[4]) begin
                      y_input <= y_input - 32'h0000019a;
                    end
                    if (sw[5]) begin
                        x_input <= x_input - ($signed(forward_vec[0]) >>> 6);
                        z_input <= z_input + ($signed(forward_vec[2]) >>> 6);
                    end 
                    if (sw[6]) begin
                        x_input <= x_input + ($signed(forward_vec[0]) >>> 6);
                        z_input <= z_input - ($signed(forward_vec[2]) >>> 6);
                    end
                    if (sw[9]) begin
                      side_angle <= side_angle + 32'h0080_0000;
                    end
                    if (sw[10]) begin
                      side_angle <= side_angle - 32'h0080_0000;
                    end
                    if (sw[11]) begin
                      if (rot_angle < 32'h7F7F_FFFF) begin
                          rot_angle <= rot_angle + 32'h0080_0000;
                      end
                    end
                    if (sw[12]) begin
                      if (rot_angle > 32'sh8080_0000) begin
                          rot_angle <= rot_angle - 32'h0080_0000;
                      end
                    end
                    busy <= 1;
                    state <= INIT;
                end
            end
            INIT: begin
                world_read_addr <= 0;
                state <= LOOP;
                read_counter <= 0;
            end
            LOOP: begin
                if (read_counter < 2'b11) begin
                    read_counter <= read_counter + 1;
                end else begin
                    // delete all cubes with z=1,3
                    // doesn't work yet
                    if (sw[1] && world_read[3*COORD_WIDTH/2]) begin
                        if (world_read[1] == 1) begin
                            world_write_addr <= world_read_addr;
                            world_write <= {1'b0, world_read[3*COORD_WIDTH/2-1:0]}; 
                        end
                    end

                    // add them back
                    // doesn't work yet
                    if (sw[7] && ~world_read[3*COORD_WIDTH/2]) begin
                        if (world_read[1] == 1) begin
                            world_write_addr <= world_read_addr;
                            world_write <= {1'b1, world_read[3*COORD_WIDTH/2-1:0]}; 
                        end
                    end

                    if (world_read_addr < WORLD_SIZE - 1) begin
                        world_read_addr <= world_read_addr + 1;
                        read_counter <= 0;
                    end else begin
                        done <= 1;
                        state <= DONE;
                    end
                end
            end
            DONE: begin
                done <= 0;
                busy <= 0;
                state <= IDLE;
            end
        endcase

        if (rst_in) begin
          x_input <= 32'h00000000;
          y_input <= 32'h00010000;
          z_input <= 32'hFFFA0000;

          done <= 0;
          busy <= 0;
          state <= IDLE;
        end else if (btn[1]) begin
          x_input <= 32'h00000005;
          y_input <= 32'h00000005;
          z_input <= 32'h00000005;
        end else if (btn[2]) begin
          x_input = 32'hFFFF0628;
          y_input = 32'hFFFFF156;
          z_input = 32'hFFFEC464;
          rot_angle <= 0;
          side_angle <= 0;
        end
    end
endmodule
`default_nettype wire
