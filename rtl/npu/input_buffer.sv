// ============================================================
// Module : input_buffer
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Desc   : NPU giriş + DepthwiseConv ağırlık on-chip tamponu.
//          - input_mem : 1960 × INT8 (49×40×1 giriş spektrogramı, flat)
//          - dw_w_mem  : 640  × INT8 (8 filtre × 10×8 DW ağırlığı, [c][kh][kw])
//          İki yazma portu (loader/FSM'den), kombinasyonel okuma portları
//          (DepthwiseConv kayan-pencere erişimi gecikmesiz).
//
//          NOT (çip akışı): Kombinasyonel okuma = fonksiyonel-önce seçim
//          (sıralı MAC zamanlamasını basit tutar). ASIC/BRAM eşlemesinde
//          kayıtlı-okuma + 1 boru hattı aşaması eklenecek (optimizasyon).
// ============================================================

`timescale 1ns/1ps

module input_buffer
    import npu_pkg::*;
(
    input  logic clk,

    // ---- Yazma portu A: giriş verisi (flat 0..INPUT_SIZE-1) ----
    input  logic                          in_wr_en,
    input  logic [$clog2(INPUT_SIZE)-1:0] in_wr_addr,
    input  logic        [7:0]             in_wr_data,

    // ---- Yazma portu B: DW ağırlıkları (0..DW_WEIGHT_BYTES-1) ----
    input  logic                              dw_w_wr_en,
    input  logic [$clog2(DW_WEIGHT_BYTES)-1:0] dw_w_wr_addr,
    input  logic        [7:0]                  dw_w_wr_data,

    // ---- Okuma portu: giriş pikseli (DepthwiseConv'a) ----
    input  logic [$clog2(INPUT_SIZE)-1:0] in_rd_addr,
    output logic signed [7:0]             in_rd_data,

    // ---- Okuma portu: DW ağırlığı (DepthwiseConv'a) ----
    input  logic [$clog2(DW_WEIGHT_BYTES)-1:0] dw_w_rd_addr,
    output logic signed [7:0]                  dw_w_rd_data
);

    logic signed [7:0] input_mem [0:INPUT_SIZE-1];
    logic signed [7:0] dw_w_mem  [0:DW_WEIGHT_BYTES-1];

    // Senkron yazma + senkron okuma (1 çevrim gecikme) → BRAM eşlenir
    always_ff @(posedge clk) begin
        if (in_wr_en)   input_mem[in_wr_addr]  <= $signed(in_wr_data);
        if (dw_w_wr_en) dw_w_mem[dw_w_wr_addr]  <= $signed(dw_w_wr_data);
        in_rd_data   <= input_mem[in_rd_addr];
        dw_w_rd_data <= dw_w_mem[dw_w_rd_addr];
    end

endmodule
