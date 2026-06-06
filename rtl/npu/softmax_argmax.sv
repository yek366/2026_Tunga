// ============================================================
// Module : softmax_argmax
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : Karar birimi — 4 adet INT32 logit arasından Argmax hesaplar.
//          Tam Softmax donanımda pahalıdır; şartname yalnızca argmax
//          (en büyük değerin indeksi) ile karar vermesine izin verir.
//          Çıkış: 2-bit sınıf indeksi (0=silence, 1=unknown, 2=yes, 3=no)
// ============================================================

`timescale 1ns/1ps

module softmax_argmax #(
    parameter int NUM_CLASSES  = 4,
    parameter int LOGIT_WIDTH  = 32
) (
    input  logic clk,
    input  logic rst_n,

    // Kontrol
    input  logic start,
    output logic done,

    // Giriş — 4 × INT32 logit
    input  logic signed [LOGIT_WIDTH-1:0] logits [0:NUM_CLASSES-1],

    // Çıkış
    output logic [1:0] result    // 2-bit sınıf indeksi
);

    typedef enum logic [1:0] {AM_IDLE, AM_COMPARE, AM_DONE} am_state_t;
    am_state_t state;

    logic [$clog2(NUM_CLASSES)-1:0]  idx;
    logic signed [LOGIT_WIDTH-1:0]   max_val;
    logic [1:0]                      max_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= AM_IDLE;
            done    <= 1'b0;
            result  <= 2'h0;
            idx     <= '0;
            max_val <= {1'b1, {(LOGIT_WIDTH-1){1'b0}}}; // INT32 minimum
            max_idx <= 2'h0;
        end else begin
            done <= 1'b0;

            case (state)
                AM_IDLE: begin
                    if (start) begin
                        idx     <= '0;
                        max_val <= {1'b1, {(LOGIT_WIDTH-1){1'b0}}};
                        max_idx <= 2'h0;
                        state   <= AM_COMPARE;
                    end
                end

                AM_COMPARE: begin
                    if ($signed(logits[idx]) > max_val) begin
                        max_val <= logits[idx];
                        max_idx <= 2'(idx);
                    end

                    if (idx == NUM_CLASSES[$clog2(NUM_CLASSES)-1:0] - 1) begin
                        idx   <= '0;
                        state <= AM_DONE;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                AM_DONE: begin
                    result <= max_idx;
                    done   <= 1'b1;
                    state  <= AM_IDLE;
                end
                default: state <= AM_IDLE;
            endcase
        end
    end

endmodule
