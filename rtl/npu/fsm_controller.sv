// ============================================================
// Module : fsm_controller
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : NPU ana kontrol FSM'i.
//          IDLE → LOAD_WEIGHTS → LOAD_INPUT → DEPTHWISE_CONV → RELU →
//          FLATTEN → FULLY_CONNECTED → ARGMAX → WRITE_RESULT → DONE → IDLE
//          DONE'dan IDLE'a geçerken IRQ üretilir.
// ============================================================

`timescale 1ns/1ps

module fsm_controller #(
    parameter int INPUT_SIZE   = 1960,
    parameter int NUM_FILTERS  = 8,
    parameter int KERNEL_H     = 10,
    parameter int KERNEL_W     = 8
) (
    input  logic clk,
    input  logic rst_n,

    // Kontrol sinyalleri (CSR'dan)
    input  logic        start,
    input  logic [31:0] input_base_addr,
    input  logic [31:0] weight_base_addr,

    // Bellek okuma arayüzü (axi_controller'a)
    output logic        mem_rd_req,
    output logic [31:0] mem_rd_addr,
    output logic [15:0] mem_rd_len,
    input  logic        mem_rd_valid,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [7:0]  mem_rd_data,   // TODO: input_buffer write port bağlandığında kullanılacak
    input  logic        mem_rd_last,   // TODO: burst tamamlama için kullanılacak
    /* verilator lint_on UNUSEDSIGNAL */

    // Bellek yazma arayüzü
    output logic        mem_wr_req,
    output logic [31:0] mem_wr_addr,
    output logic [31:0] mem_wr_data,
    input  logic        mem_wr_done,

    // Hesaplama birimi kontrol sinyalleri
    output logic        dw_start,
    input  logic        dw_done,
    output logic        fc_start,
    input  logic        fc_done,
    output logic        argmax_start,
    input  logic        argmax_done,

    // Durum çıkışları (CSR'a)
    output logic        busy,
    output logic        done,
    input  logic [1:0]  result,   // softmax_argmax'ten gelen sınıf indeksi

    // Kesme çıkışı
    output logic        irq
);

    // ---- FSM durum tanımı ----
    typedef enum logic [3:0] {
        IDLE,
        LOAD_WEIGHTS,
        LOAD_INPUT,
        DEPTHWISE_CONV,
        RELU,           // DepthwiseConv ile birlikte uygulanır (pipeline)
        FLATTEN,
        FULLY_CONNECTED,
        ARGMAX,
        WRITE_RESULT,
        DONE
    } npu_state_t;

    npu_state_t current_state, next_state;

    // ---- Yük sayacı ----
    // Kaç byte okunduğunu takip eder
    localparam int WEIGHT_BYTES = NUM_FILTERS * KERNEL_H * KERNEL_W; // 8*10*8 = 640 byte
    localparam int INPUT_BYTES  = INPUT_SIZE;                          // 1960 byte

    logic [15:0] load_cnt;
    logic        load_done;

    // ---- Durum kaydı ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end

    // ---- Sonraki durum mantığı ----
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE:            if (start)      next_state = LOAD_WEIGHTS;
            LOAD_WEIGHTS:    if (load_done)  next_state = LOAD_INPUT;
            LOAD_INPUT:      if (load_done)  next_state = DEPTHWISE_CONV;
            DEPTHWISE_CONV:  if (dw_done)    next_state = FLATTEN;
            RELU:            ;               // DepthwiseConv içinde uygulanır
            FLATTEN:                         next_state = FULLY_CONNECTED;
            FULLY_CONNECTED: if (fc_done)    next_state = ARGMAX;
            ARGMAX:          if (argmax_done) next_state = WRITE_RESULT;
            WRITE_RESULT:    if (mem_wr_done) next_state = DONE;
            DONE:                            next_state = IDLE;
            default:                         next_state = IDLE;
        endcase
    end

    // ---- Çıkış mantığı ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            done         <= 1'b0;
            irq          <= 1'b0;
            dw_start     <= 1'b0;
            fc_start     <= 1'b0;
            argmax_start <= 1'b0;
            mem_rd_req   <= 1'b0;
            mem_rd_addr  <= 32'h0;
            mem_rd_len   <= 16'h0;
            mem_wr_req   <= 1'b0;
            mem_wr_addr  <= 32'h0;
            mem_wr_data  <= 32'h0;
            load_cnt     <= 16'h0;
        end else begin
            // Tek çevrim puls sinyalleri temizle
            dw_start     <= 1'b0;
            fc_start     <= 1'b0;
            argmax_start <= 1'b0;
            irq          <= 1'b0;

            case (current_state)
                IDLE: begin
                    busy <= 1'b0;
                    done <= 1'b0;
                end

                LOAD_WEIGHTS: begin
                    busy        <= 1'b1;
                    mem_rd_req  <= 1'b1;
                    mem_rd_addr <= weight_base_addr + {16'h0, load_cnt};
                    mem_rd_len  <= WEIGHT_BYTES[15:0] - 16'h1;
                    if (mem_rd_valid) load_cnt <= load_cnt + 16'h1;
                    if (load_done) begin
                        mem_rd_req <= 1'b0;
                        load_cnt   <= 16'h0;
                    end
                end

                LOAD_INPUT: begin
                    mem_rd_req  <= 1'b1;
                    mem_rd_addr <= input_base_addr + {16'h0, load_cnt};
                    mem_rd_len  <= INPUT_BYTES[15:0] - 16'h1;
                    if (mem_rd_valid) load_cnt <= load_cnt + 16'h1;
                    if (load_done) begin
                        mem_rd_req <= 1'b0;
                        load_cnt   <= 16'h0;
                    end
                end

                DEPTHWISE_CONV: begin
                    if (current_state != next_state) dw_start <= 1'b1;
                end

                FLATTEN: begin
                    // Sadece adres aritmetiği — ek donanım gerektirmez
                end

                FULLY_CONNECTED: begin
                    if (current_state != next_state) fc_start <= 1'b1;
                end

                ARGMAX: begin
                    if (current_state != next_state) argmax_start <= 1'b1;
                end

                WRITE_RESULT: begin
                    mem_wr_req  <= 1'b1;
                    // Sonucu NPU_RESULT CSR yazmaç alanına yaz
                    // (axi_controller bu adresi doğrudan CSR'a yönlendirir)
                    mem_wr_addr <= 32'h0000_0010; // NPU_RESULT CSR ofseti
                    mem_wr_data <= {30'h0, result};
                    if (mem_wr_done) mem_wr_req <= 1'b0;
                end

                DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    irq  <= 1'b1; // CPU'ya kesme gönder
                end
                default: ; // Geçersiz durum — IDLE'a dönmek için next_state mantığındaki default yeterli
            endcase
        end
    end

    // ---- Yükleme tamamlanma sinyali ----
    assign load_done = (current_state == LOAD_WEIGHTS) ?
                       (load_cnt == WEIGHT_BYTES[15:0]) :
                       (load_cnt == INPUT_BYTES[15:0]);

endmodule
