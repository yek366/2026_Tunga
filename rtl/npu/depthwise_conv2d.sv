// ============================================================
// Module : depthwise_conv2d
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : DepthwiseConv2D + ReLU hesaplama motoru.
//          Giriş: 49×40×1 INT8
//          Kernel: 8 filtre × 10×8, stride 2
//          Çıkış: 25×20×8 INT8 (ReLU sonrası, negatifler sıfırlanmış)
//          Her filtre için 80 adet INT8×INT8→INT32 MAC işlemi yapılır.
//          8 filtre sıralı çalışır (kaynak kısıtı için);
//          paralel mimariye geçiş için NUM_PARALLEL parametresi eklenebilir.
// ============================================================

`timescale 1ns/1ps

module depthwise_conv2d #(
    parameter int NUM_FILTERS  = 8,
    parameter int KERNEL_H     = 10,
    parameter int KERNEL_W     = 8,
    parameter int STRIDE_W     = 2,   // Yatay stride (sütun yönü)
    // OUT_H ve OUT_W değerleri şartnameden alınmıştır (padding dahil)
    // Gerçek padding miktarı implementasyon sırasında netleştirilecek
    parameter int OUT_H        = 25,
    parameter int OUT_W        = 20,
    parameter int ACCUM_WIDTH  = 32
) (
    input  logic clk,
    input  logic rst_n,

    // Kontrol
    input  logic start,
    output logic done,

    // Giriş verisi — input_buffer'dan satır tamponu arayüzü
    output logic [5:0]             col_rd_idx,
    input  logic signed [7:0]      line_buf [0:KERNEL_H-1],

    // Ağırlık okuma
    output logic [9:0]             weight_rd_addr,
    input  logic signed [7:0]      weight_data,

    // Çıkış veri yazma arayüzü (local_buffer'a)
    output logic                   out_wr_en,
    output logic [11:0]            out_wr_addr,   // 25*20*8 = 4000 < 2^12 = 4096
    output logic signed [7:0]      out_wr_data    // INT8 (ReLU sonrası)
);

    // ---- Durum makinesi ----
    typedef enum logic [2:0] {
        DW_IDLE,
        DW_COMPUTE,
        DW_RELU,
        DW_WRITE,
        DW_DONE
    } dw_state_t;

    dw_state_t state;

    // ---- Sayaçlar ----
    logic [$clog2(OUT_H)-1:0]        out_row;
    logic [$clog2(OUT_W)-1:0]        out_col;
    logic [$clog2(NUM_FILTERS)-1:0]  filter_idx;
    logic [$clog2(KERNEL_H)-1:0]     krow;
    logic [$clog2(KERNEL_W)-1:0]     kcol;

    // ---- Akümülatör ----
    logic signed [ACCUM_WIDTH-1:0]   accumulator;

    // ---- Ağırlık adresi hesaplama ----
    // Ağırlık düzeni: [filtre][krow][kcol]
    assign weight_rd_addr = (10'(filter_idx) * 10'(KERNEL_H * KERNEL_W)) +
                            (10'(krow) * 10'(KERNEL_W)) +
                            10'(kcol);

    // ---- Giriş adresi: kayan pencere ----
    // Giriş satırı = out_row*STRIDE_H + krow
    // Giriş sütunu = out_col*STRIDE_W + kcol
    assign col_rd_idx = 6'(out_col * STRIDE_W + kcol);

    // ---- FSM ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= DW_IDLE;
            done         <= 1'b0;
            out_wr_en    <= 1'b0;
            accumulator  <= '0;
            out_row      <= '0;
            out_col      <= '0;
            filter_idx   <= '0;
            krow         <= '0;
            kcol         <= '0;
        end else begin
            done      <= 1'b0;
            out_wr_en <= 1'b0;

            case (state)
                DW_IDLE: begin
                    if (start) begin
                        out_row    <= '0;
                        out_col    <= '0;
                        filter_idx <= '0;
                        krow       <= '0;
                        kcol       <= '0;
                        accumulator<= '0;
                        state      <= DW_COMPUTE;
                    end
                end

                DW_COMPUTE: begin
                    // MAC: accumulator += weight * input_pixel
                    // input_pixel: line_buf[krow] sütun = col_rd_idx (kombinasyonel)
                    accumulator <= accumulator +
                        ($signed(weight_data) * $signed(line_buf[krow]));

                    // Kernel sayaçlarını ilerlet
                    if (kcol == KERNEL_W[($clog2(KERNEL_W))-1:0] - 1) begin
                        kcol <= '0;
                        if (krow == KERNEL_H[($clog2(KERNEL_H))-1:0] - 1) begin
                            krow  <= '0;
                            state <= DW_RELU;
                        end else begin
                            krow <= krow + 1'b1;
                        end
                    end else begin
                        kcol <= kcol + 1'b1;
                    end
                end

                DW_RELU: begin
                    // ReLU: negatif → 0, pozitif saturate to INT8 max
                    state <= DW_WRITE;
                end

                DW_WRITE: begin
                    out_wr_en   <= 1'b1;
                    // Düz çıkış adresi: (out_row * OUT_W * NUM_FILTERS) +
                    //                   (out_col * NUM_FILTERS) + filter_idx
                    out_wr_addr <= 12'(out_row) * 12'(OUT_W * NUM_FILTERS) +
                                   12'(out_col) * 12'(NUM_FILTERS) +
                                   12'(filter_idx);
                    // INT8 saturasyon sonrası ReLU çıkışı
                    if (accumulator <= 32'sh0)
                        out_wr_data <= 8'sh0;
                    else if (accumulator > 32'sh7F)
                        out_wr_data <= 8'sh7F;
                    else
                        out_wr_data <= accumulator[7:0];

                    accumulator <= '0;

                    // Sonraki piksel için sayaçları ilerlet
                    if (filter_idx == NUM_FILTERS[($clog2(NUM_FILTERS))-1:0] - 1) begin
                        filter_idx <= '0;
                        if (out_col == OUT_W[($clog2(OUT_W))-1:0] - 1) begin
                            out_col <= '0;
                            if (out_row == OUT_H[($clog2(OUT_H))-1:0] - 1) begin
                                out_row <= '0;
                                state   <= DW_DONE;
                            end else begin
                                out_row <= out_row + 1'b1;
                                state   <= DW_COMPUTE;
                            end
                        end else begin
                            out_col <= out_col + 1'b1;
                            state   <= DW_COMPUTE;
                        end
                    end else begin
                        filter_idx <= filter_idx + 1'b1;
                        state      <= DW_COMPUTE;
                    end
                end

                DW_DONE: begin
                    done  <= 1'b1;
                    state <= DW_IDLE;
                end
                default: state <= DW_IDLE;
            endcase
        end
    end

endmodule
