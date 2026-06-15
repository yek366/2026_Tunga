// ============================================================
// Module : fully_connected
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Desc   : FullyConnected (Dense) — INT8 MAC → per-channel requant → INT8 logit.
//          4 nöron × 4000 giriş. Giriş = DW çıkışı (flatten, INT8).
//            acc[n] = Σ w[n][i] * (in[i] - fc_input_zp) + bias[n]
//            logit[n] = requant(acc[n], mult[n], shift[n]) + fc_out_zp  (INT8)
//          Gerçek tiny_conv FC'si PER-CHANNEL quantize (4 ayrı ölçek);
//          argmax requant'lı int8 logit üzerinde (TFLite sınıfıyla aynı).
//
//          BORU HATTI: local_buffer + fc_weight_buffer KAYITLI okuma (BRAM);
//          adres MAC'ten 1 çevrim önde, çarpım gecikmeli biriktirilir.
// ============================================================

`timescale 1ns/1ps

module fully_connected
    import npu_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    input  logic start,
    output logic done,

    input  logic signed [31:0] fc_input_zp,
    input  logic signed [31:0] fc_bias  [0:FC_OUTPUTS-1],
    input  logic signed [31:0] fc_mult  [0:FC_OUTPUTS-1],
    input  logic signed [31:0] fc_shift [0:FC_OUTPUTS-1],
    input  logic signed [31:0] fc_out_zp,

    // Giriş okuma (local_buffer, KAYITLI: 1 çevrim gecikme)
    output logic [$clog2(FC_FLAT)-1:0]  in_rd_addr,
    input  logic signed [7:0]           in_data,

    // Ağırlık okuma (fc_weight_buffer, KAYITLI)
    output logic [$clog2(FC_WEIGHT_BYTES)-1:0] weight_rd_addr,
    input  logic signed [7:0]                  weight_data,

    // Çıkış logit'leri (per-channel requant sonrası INT8)
    output logic signed [7:0]  logits [0:FC_OUTPUTS-1],
    output logic               logits_valid
);

    typedef enum logic [1:0] {FC_IDLE, FC_RUN, FC_STORE, FC_DONE} fc_state_t;
    fc_state_t state;

    logic [$clog2(FC_OUTPUTS)-1:0]  n;
    logic [$clog2(FC_FLAT+1)-1:0]   icnt;   // 0..FC_FLAT (adres fazı önde)
    logic signed [31:0]             acc;

    logic addr_ph;
    assign addr_ph = (icnt < FC_FLAT[$clog2(FC_FLAT+1)-1:0]);

    assign in_rd_addr     = ($clog2(FC_FLAT))'(addr_ph ? icnt : '0);
    assign weight_rd_addr = ($clog2(FC_WEIGHT_BYTES))'(
                                int'(n) * FC_FLAT + (addr_ph ? int'(icnt) : 0));

    // MAC çarpımı (KAYITLI tampon çıkışları — in_data/weight_data hizalı)
    int term, prod;
    always_comb begin
        term = int'(in_data) - fc_input_zp;
        prod = int'(weight_data) * term;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= FC_IDLE;
            done         <= 1'b0;
            logits_valid <= 1'b0;
            n <= '0; icnt <= '0; acc <= '0;
            for (int k = 0; k < FC_OUTPUTS; k++) logits[k] <= '0;
        end else begin
            done         <= 1'b0;
            logits_valid <= 1'b0;
            case (state)
                FC_IDLE: begin
                    if (start) begin
                        n <= '0; icnt <= '0; acc <= '0;
                        state <= FC_RUN;
                    end
                end

                FC_RUN: begin
                    if (icnt != '0) acc <= acc + prod;   // bir önceki giriş çarpımı
                    if (icnt == FC_FLAT[$clog2(FC_FLAT+1)-1:0]) begin
                        state <= FC_STORE;               // 4000 birikim tamam
                    end else begin
                        icnt <= icnt + 1'b1;
                    end
                end

                FC_STORE: begin
                    // acc + bias (int32 sarma) → per-channel requant + fc_out_zp → INT8
                    logits[n] <= requant_relu(acc + fc_bias[n], fc_mult[n], fc_shift[n],
                                              fc_out_zp, -32'sd128, 32'sd127);
                    acc  <= '0;
                    icnt <= '0;
                    if (n == 2'(FC_OUTPUTS-1)) begin
                        state <= FC_DONE;
                    end else begin
                        n     <= n + 1'b1;
                        state <= FC_RUN;
                    end
                end

                FC_DONE: begin
                    done         <= 1'b1;
                    logits_valid <= 1'b1;
                    state        <= FC_IDLE;
                end
                default: state <= FC_IDLE;
            endcase
        end
    end

endmodule
