// ============================================================
// Module : quant_requant
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Desc   : npu_pkg::requant_relu kombinasyonel sarmalayıcısı.
//          DW katmanı akümülatör → INT8 requant + zero-point + fused ReLU.
//          Birim test (requant_tb) ile golden'a karşı doğrulanır.
// ============================================================

`timescale 1ns/1ps

module quant_requant
    import npu_pkg::*;
(
    input  logic signed [31:0] acc,
    input  logic signed [31:0] mult,
    input  logic signed [31:0] shift,
    input  logic signed [31:0] out_zp,
    input  logic signed [31:0] act_min,
    input  logic signed [31:0] act_max,
    output logic signed [7:0]  q_out
);
    assign q_out = requant_relu(acc, mult, shift, out_zp, act_min, act_max);
endmodule
