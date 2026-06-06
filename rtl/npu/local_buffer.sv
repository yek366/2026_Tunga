// ============================================================
// Module : local_buffer
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : NPU yerel SRAM tamponu.
//          DepthwiseConv2D çıkışını (4000 × INT8) ve FC katmanı
//          için ara sonuçları saklar. Tek yazma, tek okuma portlu.
// ============================================================

`timescale 1ns/1ps

module local_buffer #(
    parameter int DEPTH      = 4000,  // 25*20*8 = 4000 eleman
    parameter int DATA_WIDTH = 8
) (
    input  logic clk,

    // Yazma portu
    input  logic                        wr_en,
    input  logic [$clog2(DEPTH)-1:0]    wr_addr,
    input  logic signed [DATA_WIDTH-1:0] wr_data,

    // Okuma portu (tek çevrim gecikme)
    input  logic [$clog2(DEPTH)-1:0]    rd_addr,
    output logic signed [DATA_WIDTH-1:0] rd_data
);

    logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end

endmodule
