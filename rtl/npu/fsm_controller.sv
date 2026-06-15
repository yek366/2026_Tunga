// ============================================================
// Module : fsm_controller
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Desc   : NPU ana kontrol FSM'i + ağırlık/giriş yükleyici (loader).
//          1) Ağırlık blob'unu AI_MEM'den (weight_base) okur, AI_MEM
//             yerleşimine göre dağıtır:
//               header (zp/act) → quant register'ları
//               dw_mult/shift/bias[8] (int32, little-endian) → register'lar
//               dw_weight[640]   → input_buffer (DW ağırlık portu)
//               fc_bias[4]       → register'lar
//               fc_weight[16000] → fc_weight_buffer
//          2) Giriş[1960]'ı AI_MEM'den (input_base) okur → input_buffer.
//          3) DepthwiseConv → FullyConnected → Argmax sıralar.
//          4) Sonucu mandallar, DONE'da CPU'ya IRQ üretir.
//          Quant parametreleri DW/FC modüllerine register dizisi olarak çıkar.
// ============================================================

`timescale 1ns/1ps

module fsm_controller
    import npu_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    // CSR'dan
    input  logic        start,
    input  logic [31:0] input_base_addr,
    input  logic [31:0] weight_base_addr,

    // AXI okuma motoru (axi_controller'a)
    output logic        rd_start,
    output logic [31:0] rd_addr,
    output logic [15:0] rd_len,
    input  logic [7:0]  rd_byte,
    input  logic        rd_valid,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic        rd_busy,    // gözlem/debug
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        rd_done,

    // input_buffer yazma portları
    output logic                              in_wr_en,
    output logic [$clog2(INPUT_SIZE)-1:0]     in_wr_addr,
    output logic [7:0]                        in_wr_data,
    output logic                              dw_w_wr_en,
    output logic [$clog2(DW_WEIGHT_BYTES)-1:0] dw_w_wr_addr,
    output logic [7:0]                        dw_w_wr_data,

    // fc_weight_buffer yazma portu
    output logic                              fc_w_wr_en,
    output logic [$clog2(FC_WEIGHT_BYTES)-1:0] fc_w_wr_addr,
    output logic [7:0]                        fc_w_wr_data,

    // Quant parametreleri (DW/FC'ye)
    output logic signed [31:0] input_zp,
    output logic signed [31:0] dw_out_zp,
    output logic signed [31:0] dw_act_min,
    output logic signed [31:0] dw_act_max,
    output logic signed [31:0] dw_mult  [0:NUM_FILTERS-1],
    output logic signed [31:0] dw_shift [0:NUM_FILTERS-1],
    output logic signed [31:0] dw_bias  [0:NUM_FILTERS-1],
    output logic signed [31:0] fc_bias  [0:FC_OUTPUTS-1],
    output logic signed [31:0] fc_mult  [0:FC_OUTPUTS-1],
    output logic signed [31:0] fc_shift [0:FC_OUTPUTS-1],
    output logic signed [31:0] fc_out_zp,

    // Katman kontrolü
    output logic dw_start,
    input  logic dw_done,
    output logic fc_start,
    input  logic fc_done,
    output logic argmax_start,
    input  logic argmax_done,

    // Durum
    output logic       busy,
    output logic       done,
    input  logic [1:0] result,
    output logic       irq
);

    typedef enum logic [3:0] {
        S_IDLE,
        S_LDW_REQ, S_LDW_DATA,
        S_LDI_REQ, S_LDI_DATA,
        S_RUN_DW, S_RUN_FC, S_RUN_ARGMAX,
        S_DONE
    } state_t;
    state_t state;

    logic [16:0] load_cnt;   // 0..BLOB_BYTES-1 (ağırlık) veya 0..INPUT_SIZE-1 (giriş)

    // 17-bit tiplenmiş blob ofsetleri (lint-temiz karşılaştırma için)
    localparam logic [16:0] C_HDR      = 17'(OFF_HDR);
    localparam logic [16:0] C_DW_MULT  = 17'(OFF_DW_MULT);
    localparam logic [16:0] C_DW_SHIFT = 17'(OFF_DW_SHIFT);
    localparam logic [16:0] C_DW_BIAS  = 17'(OFF_DW_BIAS);
    localparam logic [16:0] C_DW_W     = 17'(OFF_DW_W);
    localparam logic [16:0] C_FC_MULT  = 17'(OFF_FC_MULT);
    localparam logic [16:0] C_FC_SHIFT = 17'(OFF_FC_SHIFT);
    localparam logic [16:0] C_FC_BIAS  = 17'(OFF_FC_BIAS);
    localparam logic [16:0] C_FC_OUTZP = 17'(OFF_FC_OUTZP);
    localparam logic [16:0] C_FC_W     = 17'(OFF_FC_W);

    // ---- Bayt sign-extend yardımcı ----
    function automatic logic signed [31:0] sx8(input logic [7:0] b);
        return {{24{b[7]}}, b};
    endfunction

    // ============================================================
    // Yükleme dağıtımı — buffer yazmaları KOMBİNASYONEL (rd_valid + load_cnt)
    // ============================================================
    logic in_w_phase;   // ağırlık yükleme fazı
    logic in_i_phase;   // giriş yükleme fazı
    assign in_w_phase = (state == S_LDW_DATA);
    assign in_i_phase = (state == S_LDI_DATA);

    // DW ağırlık bölgesi: [OFF_DW_W, OFF_FC_MULT) — arada FC quant alanları var
    logic dw_w_region, fc_w_region;
    assign dw_w_region = in_w_phase && (load_cnt >= C_DW_W) && (load_cnt < C_FC_MULT);
    assign fc_w_region = in_w_phase && (load_cnt >= C_FC_W);

    assign dw_w_wr_en   = rd_valid && dw_w_region;
    assign dw_w_wr_addr = ($clog2(DW_WEIGHT_BYTES))'(load_cnt - C_DW_W);
    assign dw_w_wr_data = rd_byte;

    assign fc_w_wr_en   = rd_valid && fc_w_region;
    assign fc_w_wr_addr = ($clog2(FC_WEIGHT_BYTES))'(load_cnt - C_FC_W);
    assign fc_w_wr_data = rd_byte;

    assign in_wr_en   = rd_valid && in_i_phase;
    assign in_wr_addr = ($clog2(INPUT_SIZE))'(load_cnt);
    assign in_wr_data = rd_byte;

    // ---- int32 bölge dizin/lane (little-endian) ----
    logic [4:0] mult_li, shift_li, bias_li;            // DW: 32 bayt → 5-bit
    logic [3:0] fcmult_li, fcshift_li, fcbias_li;      // FC: 16 bayt → 4-bit
    logic [1:0] fcoutzp_li;                            // FC out_zp: 4 bayt → 2-bit
    assign mult_li    = 5'(load_cnt - C_DW_MULT);
    assign shift_li   = 5'(load_cnt - C_DW_SHIFT);
    assign bias_li    = 5'(load_cnt - C_DW_BIAS);
    assign fcmult_li  = 4'(load_cnt - C_FC_MULT);
    assign fcshift_li = 4'(load_cnt - C_FC_SHIFT);
    assign fcbias_li  = 4'(load_cnt - C_FC_BIAS);
    assign fcoutzp_li = 2'(load_cnt - C_FC_OUTZP);

    // ============================================================
    // Ana FSM
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            irq          <= 1'b0;
            rd_start     <= 1'b0;
            rd_addr      <= 32'h0;
            rd_len       <= 16'h0;
            load_cnt     <= 17'h0;
            dw_start     <= 1'b0;
            fc_start     <= 1'b0;
            argmax_start <= 1'b0;
            input_zp     <= '0;
            dw_out_zp    <= '0;
            dw_act_min   <= '0;
            dw_act_max   <= '0;
            for (int k = 0; k < NUM_FILTERS; k++) begin
                dw_mult[k]  <= '0;
                dw_shift[k] <= '0;
                dw_bias[k]  <= '0;
            end
            fc_out_zp <= '0;
            for (int k = 0; k < FC_OUTPUTS; k++) begin
                fc_bias[k]  <= '0;
                fc_mult[k]  <= '0;
                fc_shift[k] <= '0;
            end
        end else begin
            // Varsayılan puls temizleme (done STICKY — burada temizlenmez)
            rd_start     <= 1'b0;
            dw_start     <= 1'b0;
            fc_start     <= 1'b0;
            argmax_start <= 1'b0;
            irq          <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        done     <= 1'b0;   // yeni çıkarım: önceki DONE'u temizle
                        rd_start <= 1'b1;
                        rd_addr  <= weight_base_addr;
                        rd_len   <= 16'(BLOB_BYTES - 1);
                        load_cnt <= 17'h0;
                        state    <= S_LDW_DATA;
                    end
                end

                // Ağırlık blob'u akışı + dağıtımı
                S_LDW_DATA: begin
                    if (rd_valid) begin
                        // Header (0..3): tek bayt işaretli alanlar
                        if (load_cnt == C_HDR + 17'd0) input_zp   <= sx8(rd_byte);
                        if (load_cnt == C_HDR + 17'd1) dw_out_zp  <= sx8(rd_byte);
                        if (load_cnt == C_HDR + 17'd2) dw_act_min <= sx8(rd_byte);
                        if (load_cnt == C_HDR + 17'd3) dw_act_max <= sx8(rd_byte);
                        // dw_mult[8] little-endian
                        if (load_cnt >= C_DW_MULT && load_cnt < C_DW_SHIFT)
                            case (mult_li[1:0])
                                2'd0: dw_mult[mult_li[4:2]][7:0]   <= rd_byte;
                                2'd1: dw_mult[mult_li[4:2]][15:8]  <= rd_byte;
                                2'd2: dw_mult[mult_li[4:2]][23:16] <= rd_byte;
                                2'd3: dw_mult[mult_li[4:2]][31:24] <= rd_byte;
                            endcase
                        // dw_shift[8]
                        if (load_cnt >= C_DW_SHIFT && load_cnt < C_DW_BIAS)
                            case (shift_li[1:0])
                                2'd0: dw_shift[shift_li[4:2]][7:0]   <= rd_byte;
                                2'd1: dw_shift[shift_li[4:2]][15:8]  <= rd_byte;
                                2'd2: dw_shift[shift_li[4:2]][23:16] <= rd_byte;
                                2'd3: dw_shift[shift_li[4:2]][31:24] <= rd_byte;
                            endcase
                        // dw_bias[8]
                        if (load_cnt >= C_DW_BIAS && load_cnt < C_DW_W)
                            case (bias_li[1:0])
                                2'd0: dw_bias[bias_li[4:2]][7:0]   <= rd_byte;
                                2'd1: dw_bias[bias_li[4:2]][15:8]  <= rd_byte;
                                2'd2: dw_bias[bias_li[4:2]][23:16] <= rd_byte;
                                2'd3: dw_bias[bias_li[4:2]][31:24] <= rd_byte;
                            endcase
                        // fc_mult[4] (per-channel)
                        if (load_cnt >= C_FC_MULT && load_cnt < C_FC_SHIFT)
                            case (fcmult_li[1:0])
                                2'd0: fc_mult[fcmult_li[3:2]][7:0]   <= rd_byte;
                                2'd1: fc_mult[fcmult_li[3:2]][15:8]  <= rd_byte;
                                2'd2: fc_mult[fcmult_li[3:2]][23:16] <= rd_byte;
                                2'd3: fc_mult[fcmult_li[3:2]][31:24] <= rd_byte;
                            endcase
                        // fc_shift[4]
                        if (load_cnt >= C_FC_SHIFT && load_cnt < C_FC_BIAS)
                            case (fcshift_li[1:0])
                                2'd0: fc_shift[fcshift_li[3:2]][7:0]   <= rd_byte;
                                2'd1: fc_shift[fcshift_li[3:2]][15:8]  <= rd_byte;
                                2'd2: fc_shift[fcshift_li[3:2]][23:16] <= rd_byte;
                                2'd3: fc_shift[fcshift_li[3:2]][31:24] <= rd_byte;
                            endcase
                        // fc_bias[4]
                        if (load_cnt >= C_FC_BIAS && load_cnt < C_FC_OUTZP)
                            case (fcbias_li[1:0])
                                2'd0: fc_bias[fcbias_li[3:2]][7:0]   <= rd_byte;
                                2'd1: fc_bias[fcbias_li[3:2]][15:8]  <= rd_byte;
                                2'd2: fc_bias[fcbias_li[3:2]][23:16] <= rd_byte;
                                2'd3: fc_bias[fcbias_li[3:2]][31:24] <= rd_byte;
                            endcase
                        // fc_out_zp (1×int32)
                        if (load_cnt >= C_FC_OUTZP && load_cnt < C_FC_W)
                            case (fcoutzp_li)
                                2'd0: fc_out_zp[7:0]   <= rd_byte;
                                2'd1: fc_out_zp[15:8]  <= rd_byte;
                                2'd2: fc_out_zp[23:16] <= rd_byte;
                                2'd3: fc_out_zp[31:24] <= rd_byte;
                            endcase
                        // (dw_weight / fc_weight buffer yazmaları kombinasyonel)
                        load_cnt <= load_cnt + 17'h1;
                    end
                    if (rd_done) begin
                        // Giriş yükleme fazına geç
                        rd_start <= 1'b1;
                        rd_addr  <= input_base_addr;
                        rd_len   <= 16'(INPUT_SIZE - 1);
                        load_cnt <= 17'h0;
                        state    <= S_LDI_DATA;
                    end
                end

                // Giriş akışı
                S_LDI_DATA: begin
                    if (rd_valid) load_cnt <= load_cnt + 17'h1;
                    if (rd_done) begin
                        dw_start <= 1'b1;
                        state    <= S_RUN_DW;
                    end
                end

                S_RUN_DW: begin
                    if (dw_done) begin
                        fc_start <= 1'b1;
                        state    <= S_RUN_FC;
                    end
                end

                S_RUN_FC: begin
                    if (fc_done) begin
                        argmax_start <= 1'b1;
                        state        <= S_RUN_ARGMAX;
                    end
                end

                S_RUN_ARGMAX: begin
                    if (argmax_done) state <= S_DONE;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    irq   <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Kullanılmayan enum değerleri + result (CSR argmax.result'i doğrudan okur)
    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (state == S_LDW_REQ) | (state == S_LDI_REQ) | (|result);
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
