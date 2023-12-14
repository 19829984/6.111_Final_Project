`timescale 1ns / 1ps
`default_nettype none
module view_matrix_calculator #(parameter COORD_WIDTH=16) (
    input wire clk_in,
    input wire rst_in,
    input wire start,
    input wire signed [COORD_WIDTH-1:0] x_in,
    input wire signed [COORD_WIDTH-1:0] y_in,
    input wire signed [COORD_WIDTH-1:0] z_in,
    input wire signed [COORD_WIDTH-1:0] rot_angle,
    input wire signed [COORD_WIDTH-1:0] side_angle,

    output logic done,
    output logic signed [3:0][3:0][COORD_WIDTH-1:0] view_matrix,
    output logic signed [2:0][COORD_WIDTH-1:0] forward_vec
);
  enum {IDLE, TRIG, SET_MATRIX, ROT_SIDE, ROTSIDE_TRANS, DONE} state;

  logic signed [3:0][3:0][COORD_WIDTH-1:0] rot_matrix;
  logic signed [3:0][3:0][COORD_WIDTH-1:0] second_matrix;
  logic signed [3:0][3:0][COORD_WIDTH-1:0] mult_matrix_out;

  logic mult_start;
  logic mult_busy;
  logic mult_done;

  //logic signed [3:0][3:0][COORD_WIDTH-1:0] vmatrix_out;
  assign view_matrix = mult_matrix_out;
  //assign view_matrix = second_matrix;

  logic signed [COORD_WIDTH-1:0] cos_rot;
  logic signed [COORD_WIDTH-1:0] sin_rot;
  logic signed [7:0] cos_rot_small;
  logic signed [7:0] sin_rot_small;
  logic signed [COORD_WIDTH-1:0] cos_side;
  logic signed [COORD_WIDTH-1:0] sin_side;
  logic signed [7:0] cos_side_small;
  logic signed [7:0] sin_side_small;

  logic first_trig;

  trig_lookup trig_lut_rot (
      .clk_in(clk_in),
      .angle(rot_angle[COORD_WIDTH-1:COORD_WIDTH-8]),
      .cos(cos_rot_small),
      .sin(sin_rot_small)
  ); trig_lookup trig_lut_side (
      .clk_in(clk_in),
      .angle(side_angle[COORD_WIDTH-1:COORD_WIDTH-8]),
      .cos(cos_side_small),
      .sin(sin_side_small)
  );

  matrixMultiply4x4 #(.WIDTH(COORD_WIDTH)) matrix_multiplier (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start(mult_start),
    .m1(rot_matrix),
    .m2(second_matrix),
    .m_out(mult_matrix_out),
    .busy(mult_busy),
    .done(mult_done)
  );

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
        state <= IDLE;
        done <= 0;
        first_trig <= 0;
        mult_start <= 0;
        forward_vec <= 0;

        rot_matrix <= 0;
        second_matrix <= 0;

        cos_rot <= 0;
        sin_rot <= 0;
    end else begin
        case (state)
            IDLE: begin
               if (start) begin
                  rot_matrix <= 0;
                  second_matrix <= 0;

                  state <= TRIG;
               end
               done <= 0;
               first_trig <= 0;
               mult_start <= 0;
            end
            TRIG: begin
                first_trig <= 1;

                if (first_trig) begin
                    sin_rot[COORD_WIDTH-1:COORD_WIDTH-8] <= sin_rot_small;
                    cos_rot[COORD_WIDTH-1:COORD_WIDTH-8] <= cos_rot_small;
                    sin_side[COORD_WIDTH-1:COORD_WIDTH-8] <= sin_side_small;
                    cos_side[COORD_WIDTH-1:COORD_WIDTH-8] <= cos_side_small;

                    //forward_vec[0][COORD_WIDTH-1:COORD_WIDTH/2-6] <= sin_side_small >>> (COORD_WIDTH/2-6); // sin = x
                    //forward_vec[2][COORD_WIDTH-1:COORD_WIDTH/2-6] <= cos_side_small >>> (COORD_WIDTH/2-6); // cos = z
                    //forward_vec[2][COORD_WIDTH/2:COORD_WIDTH/2-7] <= sin_side_small;
                    //forward_vec[0][COORD_WIDTH/2:COORD_WIDTH/2-7] <= cos_side_small;
                    //forward_vec[2][COORD_WIDTH-1:COORD_WIDTH/2+1] <= sin_side_small[7]; // sign
                    //forward_vec[0][COORD_WIDTH-1:COORD_WIDTH/2+1] <= cos_side_small[7]; // sign
                    forward_vec[2][COORD_WIDTH-1:COORD_WIDTH-8] <= cos_side_small; 
                    forward_vec[0][COORD_WIDTH-1:COORD_WIDTH-8] <= sin_side_small;

                    state <= SET_MATRIX;
                end
            end
            SET_MATRIX: begin
                rot_matrix[0][0] <= 32'h0001_0000;
                rot_matrix[3][3] <= 32'h0001_0000;
                rot_matrix[1][1] <= cos_rot >>> 15;
                rot_matrix[1][2] <= sin_rot >>> 15;
                rot_matrix[2][1] <= -1 * (sin_rot >>> 15);
                rot_matrix[2][2] <= cos_rot >>> 15;

                second_matrix[1][1] <= 32'h0001_0000;
                second_matrix[3][3] <= 32'h0001_0000;
                second_matrix[0][0] <= cos_side >>> 15;
                second_matrix[0][2] <= sin_side >>> 15;
                second_matrix[2][0] <= -1 * (sin_side >>> 15);
                second_matrix[2][2] <= cos_side >>> 15;

                forward_vec[0] <= $signed(forward_vec[0]) >>> (COORD_WIDTH/2-1);
                forward_vec[2] <= $signed(forward_vec[2]) >>> (COORD_WIDTH/2-1); // correct fixed point

                state <= ROT_SIDE;
                mult_start <= 1;
            end
            ROT_SIDE: begin
                if (mult_busy) begin
                    mult_start <= 0;
                end
                if (mult_done && ~mult_start) begin
                    rot_matrix[0][0] <= mult_matrix_out[0][0]; 
                    rot_matrix[0][1] <= mult_matrix_out[0][1];
                    rot_matrix[0][2] <= mult_matrix_out[0][2];
                    rot_matrix[0][3] <= mult_matrix_out[0][3];
                    rot_matrix[1][0] <= mult_matrix_out[1][0];
                    rot_matrix[1][1] <= mult_matrix_out[1][1];
                    rot_matrix[1][2] <= mult_matrix_out[1][2];
                    rot_matrix[1][3] <= mult_matrix_out[1][3];
                    rot_matrix[2][0] <= mult_matrix_out[2][0];
                    rot_matrix[2][1] <= mult_matrix_out[2][1]; 
                    rot_matrix[2][2] <= mult_matrix_out[2][2];
                    rot_matrix[2][3] <= mult_matrix_out[2][3];
                    rot_matrix[3][0] <= mult_matrix_out[3][0];
                    rot_matrix[3][1] <= mult_matrix_out[3][1];
                    rot_matrix[3][2] <= mult_matrix_out[3][2]; 
                    rot_matrix[3][3] <= mult_matrix_out[3][3];

                    second_matrix[0][0] <= 32'h0001_0000; 
                    second_matrix[0][1] <= 0;
                    second_matrix[0][2] <= 0;
                    second_matrix[0][3] <= x_in;
                    second_matrix[1][0] <= 0;
                    second_matrix[1][1] <= 32'h0001_0000;
                    second_matrix[1][2] <= 0;
                    second_matrix[1][3] <= y_in;
                    second_matrix[2][0] <= 0;
                    second_matrix[2][1] <= 0; 
                    second_matrix[2][2] <= 32'h0001_0000;
                    second_matrix[2][3] <= z_in;
                    second_matrix[3][0] <= 0; 
                    second_matrix[3][1] <= 0;
                    second_matrix[3][2] <= 0; 
                    second_matrix[3][3] <= 32'h0001_0000;

                    state <= ROTSIDE_TRANS;
                    mult_start <= 1;
                end
            end
            ROTSIDE_TRANS: begin
                if (mult_busy) begin
                    mult_start <= 0;
                end
                if (mult_done && ~mult_start) begin
                    state <= DONE;
                end
            end
            DONE: begin
                state <= IDLE;
                done <= 1;
            end
        endcase
    end
  end

endmodule

`default_nettype wire
