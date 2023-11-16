module tm_choice (
  input wire [7:0] data_in,
  output logic [8:0] qm_out
  );
logic [8:0] temp_qm;
 assign qm_out = temp_qm;
 always_comb begin
    logic[3:0] num_ones; 
    // Count number of ones in data_in
    num_ones = 0;
    for (int i = 0; i < 8; i=i+1) begin
        num_ones = num_ones + data_in[i];
    end
    if (num_ones > 4 || (num_ones == 4 && !(data_in & 8'h01))) begin
        for (int i = 0; i < 9; i=i+1) begin
            if (i == 0) 
                temp_qm[i] = data_in[i];
            else if (i == 8)
                temp_qm[i] = 0;
            else
                temp_qm[i] = temp_qm[i-1] ~^ data_in[i];
        end
    end else begin
        for (int i = 0; i < 9; i=i+1) begin
            if (i == 0) 
                temp_qm[i] = data_in[i];
            else if (i == 8)
                temp_qm[i] = 1;
            else
                temp_qm[i] = temp_qm[i-1] ^ data_in[i];
        end
    end
 end
endmodule