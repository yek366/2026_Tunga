// ============================================================
// Module : local_buffer
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Desc   : NPU yerel SRAM tamponu — DepthwiseConv2D çıkışı (4000 × INT8),
//          FullyConnected girişi. Tek yazma (DW), tek okuma (FC) portu.
//          KAYITLI okuma (synchronous-read RAM) → FPGA/ASIC BRAM eşlenir.
//          rd_data, rd_addr'den 1 çevrim sonra geçerli (tüketici pipeline'lı).
// ============================================================

`timescale 1ns/1ps

module local_buffer #(
    parameter int DEPTH      = 4000,
    parameter int DATA_WIDTH = 8
) (
    input  logic clk,

    input  logic                         wr_en,
    input  logic [$clog2(DEPTH)-1:0]     wr_addr,
    input  logic signed [DATA_WIDTH-1:0] wr_data,

    input  logic [$clog2(DEPTH)-1:0]     rd_addr,
    output logic signed [DATA_WIDTH-1:0] rd_data
);

    logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Simple dual-port BRAM: senkron yazma + senkron okuma (1 çevrim gecikme)
    always_ff @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end

endmodule
