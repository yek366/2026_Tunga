`ifndef NPU_PKG_SV
`define NPU_PKG_SV

`timescale 1ns/1ps

package npu_pkg;

    // ---- Model boyutları (şartname Tiny Conv) ----
    localparam int INPUT_SIZE  = 1960;
    localparam int IN_H        = 49;
    localparam int IN_W        = 40;
    localparam int NUM_FILTERS = 8;
    localparam int KER_H       = 10;
    localparam int KER_W       = 8;
    localparam int STRIDE_H    = 2;
    localparam int STRIDE_W    = 2;
    localparam int OUT_H       = 25;
    localparam int OUT_W       = 20;
    localparam int OUT_C       = NUM_FILTERS;          // 8
    localparam int FC_FLAT     = OUT_H * OUT_W * OUT_C; // 4000
    localparam int FC_OUTPUTS  = 4;

    // SAME padding (sabit, modelden): total=(O-1)*S+K-I, pad_before=total/2
    localparam int PAD_TOP  = 4;   // ((25-1)*2+10-49)/2 = 9/2 = 4
    localparam int PAD_LEFT = 3;   // ((20-1)*2+ 8-40)/2 = 6/2 = 3

    localparam int DW_WEIGHT_BYTES = NUM_FILTERS * KER_H * KER_W; // 640
    localparam int FC_WEIGHT_BYTES = FC_OUTPUTS * FC_FLAT;        // 16000

    // ---- AI_MEM ağırlık blob yerleşimi (npu_golden.py ile birebir) ----
    // Çok-baytlı alanlar little-endian, tüm int32 alanlar 4 bayt.
    localparam int OFF_HDR      = 0;     // b0=input_zp b1=dw_out_zp b2=act_min b3=act_max
    localparam int OFF_DW_MULT  = 4;     // 8×int32 -> 4..35
    localparam int OFF_DW_SHIFT = 36;    // 8×int32 -> 36..67  (işaretli)
    localparam int OFF_DW_BIAS  = 68;    // 8×int32 -> 68..99
    localparam int OFF_DW_W     = 100;   // 640×int8 -> 100..739
    localparam int OFF_FC_MULT  = 740;   // 4×int32 -> 740..755  (FC per-channel)
    localparam int OFF_FC_SHIFT = 756;   // 4×int32 -> 756..771
    localparam int OFF_FC_BIAS  = 772;   // 4×int32 -> 772..787
    localparam int OFF_FC_OUTZP = 788;   // 1×int32 -> 788..791  (FC çıkış zero-point)
    localparam int OFF_FC_W     = 792;   // 16000×int8 -> 792..16791
    localparam int BLOB_BYTES   = OFF_FC_W + FC_WEIGHT_BYTES; // 16792

    localparam logic signed [31:0] INT32_MAX = 32'sh7FFF_FFFF;
    localparam logic signed [31:0] INT32_MIN = 32'sh8000_0000;

    // gemmlowp SaturatingRoundingDoublingHighMul
    function automatic logic signed [31:0] srdhm(
        input logic signed [31:0] a,
        input logic signed [31:0] b
    );
        logic signed [63:0] ab, nudge, sum, q;
        begin
            if (a == INT32_MIN && b == INT32_MIN)
                return INT32_MAX;
            ab    = $signed(a) * $signed(b);          // 64-bit işaretli çarpım
            nudge = (ab >= 0) ? 64'sd1073741824        // 1<<30
                              : -64'sd1073741823;       // 1-(1<<30)
            sum   = ab + nudge;
            q     = sum / 64'sd2147483648;             // /2^31, sıfıra doğru kırpma
            if (q > 64'sd2147483647)        return INT32_MAX;
            else if (q < -64'sd2147483648)  return INT32_MIN;
            else                            return q[31:0];
        end
    endfunction

    // gemmlowp RoundingDivideByPOT
    function automatic logic signed [31:0] rdbp(
        input logic signed [31:0] x,
        input logic        [5:0]  exponent
    );
        logic signed [31:0] mask, remainder, threshold;
        begin
            if (exponent == 0) return x;
            mask      = (32'sd1 << exponent) - 32'sd1;
            remainder = x & mask;
            threshold = (mask >>> 1) + (x < 0 ? 32'sd1 : 32'sd0);
            return (x >>> exponent) + ((remainder > threshold) ? 32'sd1 : 32'sd0);
        end
    endfunction

    // TFLite MultiplyByQuantizedMultiplier
    function automatic logic signed [31:0] mbqm(
        input logic signed [31:0] x,
        input logic signed [31:0] mult,
        input logic signed [31:0] shift
    );
        logic signed [31:0] x_ls, high;
        logic        [5:0]  rshift;
        begin
            if (shift > 0) begin
                x_ls = x <<< shift[5:0];     // sola kaydır (nadir), int32 sarması
                return srdhm(x_ls, mult);
            end else begin
                high   = srdhm(x, mult);
                rshift = 6'(-shift);
                return rdbp(high, rshift);
            end
        end
    endfunction

    // DW requant + output_zp + fused ReLU clamp → int8
    function automatic logic signed [7:0] requant_relu(
        input logic signed [31:0] acc,
        input logic signed [31:0] mult,
        input logic signed [31:0] shift,
        input logic signed [31:0] out_zp,
        input logic signed [31:0] act_min,
        input logic signed [31:0] act_max
    );
        logic signed [31:0] v;
        begin
            v = mbqm(acc, mult, shift) + out_zp;
            if (v < act_min) v = act_min;
            if (v > act_max) v = act_max;
            return v[7:0];
        end
    endfunction

endpackage

`endif
