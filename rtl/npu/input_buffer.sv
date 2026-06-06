// ============================================================
// Module : input_buffer
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : Giriş verisi ve ağırlık geçici tamponu.
//          DepthwiseConv2D için 10×8 kayan pencereye aynı anda erişim
//          sağlamak üzere satır tamponu (line buffer) düzeni kullanılır.
//          Bellek erişimini azaltır, hesaplama hızını artırır.
// ============================================================

`timescale 1ns/1ps

module input_buffer #(
    parameter int INPUT_SIZE  = 1960,
    parameter int NUM_FILTERS = 8,
    parameter int KERNEL_H    = 10,
    parameter int KERNEL_W    = 8,
    parameter int IN_W        = 40   // Giriş genişliği (frekans bölmesi sayısı)
) (
    input  logic clk,

    /* verilator lint_off UNUSEDSIGNAL */
    input  logic rst_n,   // Gelecekteki reset mantığı için arayüzde tutulur
    /* verilator lint_on UNUSEDSIGNAL */

    // Yazma arayüzü (FSM'den — bellekten okunan veri)
    input  logic        wr_en,
    input  logic [7:0]  wr_data,           // INT8 giriş/ağırlık baytı
    input  logic [12:0] wr_addr,           // Düz adres (0..WEIGHT_SIZE+INPUT_SIZE-1)

    // Ağırlık okuma arayüzü (DepthwiseConv'a)
    input  logic [9:0]  weight_rd_addr,    // 0..KERNEL_H*KERNEL_W*NUM_FILTERS-1
    output logic signed [7:0] weight_data,

    // Satır tamponu okuma arayüzü — KERNEL_H satıra paralel erişim
    input  logic [5:0]  col_idx,           // Okunacak sütun indeksi (0..IN_W-1)
    output logic signed [7:0] line_buf_data [0:KERNEL_H-1]
);

    // ---- Bellek boyut sabitleri ----
    localparam int WEIGHT_SIZE   = NUM_FILTERS * KERNEL_H * KERNEL_W; // 640
    localparam int WEIGHT_BITS   = $clog2(WEIGHT_SIZE);   // 10
    localparam int INPUT_BITS    = $clog2(INPUT_SIZE);    // 11

    // ---- Giriş SRAM tamponu (1960 × 8 bit) ----
    logic signed [7:0] input_mem [0:INPUT_SIZE-1];

    // ---- Ağırlık SRAM tamponu (640 × 8 bit) ----
    logic signed [7:0] weight_mem [0:WEIGHT_SIZE-1];

    // ---- Yazma portu ----
    // wr_addr < WEIGHT_SIZE → weight_mem
    // wr_addr >= WEIGHT_SIZE → input_mem (ofset düşülür)
    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (wr_addr < WEIGHT_SIZE[12:0]) begin
                weight_mem[wr_addr[WEIGHT_BITS-1:0]] <= $signed(wr_data);
            end else begin
                automatic logic [INPUT_BITS-1:0] in_idx;
                in_idx = INPUT_BITS'(wr_addr) - INPUT_BITS'(WEIGHT_SIZE);
                input_mem[in_idx] <= $signed(wr_data);
            end
        end
    end

    // ---- Ağırlık okuma ----
    assign weight_data = weight_mem[weight_rd_addr];

    // ---- Satır tamponu ----
    // DepthwiseConv2D'nin kayan penceresi için KERNEL_H ardışık satıra
    // aynı anda erişim gerekir. Her satır bağımsız bir adres hesabıyla okunur.
    // row_offset: konvolüsyon penceresinin başlangıç satırı (DW conv FSM'inden türetilir)
    // Şimdilik row_offset=0 varsayımıyla satır tamponu erişimi gösterilmektedir;
    // gerçek implementasyonda DW conv FSM'i row_offset'i sağlayacak.
    genvar row;
    generate
        for (row = 0; row < KERNEL_H; row++) begin : gen_line_buf
            always_comb begin
                automatic logic [INPUT_BITS-1:0] flat_addr;
                flat_addr = INPUT_BITS'(row * IN_W) + INPUT_BITS'(col_idx);
                line_buf_data[row] = (flat_addr < INPUT_BITS'(INPUT_SIZE)) ?
                                     input_mem[flat_addr] : 8'sh0;
            end
        end
    endgenerate

endmodule
