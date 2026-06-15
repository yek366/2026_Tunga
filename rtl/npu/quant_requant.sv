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
