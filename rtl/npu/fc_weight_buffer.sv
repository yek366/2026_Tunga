`timescale 1ns/1ps

module fc_weight_buffer
    import npu_pkg::*;
(
    input  logic clk,

    // Loader yazma portu
    input  logic                              wr_en,
    input  logic [$clog2(FC_WEIGHT_BYTES)-1:0] wr_addr,
    input  logic        [7:0]                  wr_data,

    // FC okuma portu
    input  logic [$clog2(FC_WEIGHT_BYTES)-1:0] rd_addr,
    output logic signed [7:0]                  rd_data
);

    logic signed [7:0] fc_w_mem [0:FC_WEIGHT_BYTES-1];

    // Senkron okuma (1 çevrim gecikme) → BRAM eşlenir
    always_ff @(posedge clk) begin
        if (wr_en) fc_w_mem[wr_addr] <= $signed(wr_data);
        rd_data <= fc_w_mem[rd_addr];
    end

endmodule
