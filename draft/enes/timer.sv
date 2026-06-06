// ============================================================
// Module : timer
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Enes Kırmızı
// Date   : 2026-05-XX
// Desc   : 32-bit sayaç Timer — AXI4-Lite slave, IRQ üretir.
//          Yazmaçlar:
//            0x00 TIM_PRE (RW) — Prescaler
//            0x04 TIM_ARE (RW) — Auto-reload değeri
//            0x08 TIM_CLR (WO) — Sayacı temizle (yazma ile)
//            0x0C TIM_ENA (RW) — Enable [0]: sayaç çalış/dur
//            0x10 TIM_MOD (RW) — Mod: 0=yukarı say, 1=aşağı say
//            0x14 TIM_CNT (RO) — Anlık sayaç değeri
//            0x18 TIM_EVN (RO) — Event (overflow/match) sayacı
//            0x1C TIM_EVC (WO) — Event sayacını sıfırla
// ============================================================

`timescale 1ns/1ps

module timer #(
    parameter int AXIL_ADDR_WIDTH = 8
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4-Lite Slave ----
    input  logic [AXIL_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  logic                       s_axil_awvalid,
    output logic                       s_axil_awready,
    input  logic [31:0]                s_axil_wdata,
    input  logic [3:0]                 s_axil_wstrb,
    input  logic                       s_axil_wvalid,
    output logic                       s_axil_wready,
    output logic [1:0]                 s_axil_bresp,
    output logic                       s_axil_bvalid,
    input  logic                       s_axil_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0] s_axil_araddr,
    input  logic                       s_axil_arvalid,
    output logic                       s_axil_arready,
    output logic [31:0]                s_axil_rdata,
    output logic [1:0]                 s_axil_rresp,
    output logic                       s_axil_rvalid,
    input  logic                       s_axil_rready,

    // ---- Kesme çıkışı ----
    output logic timer_irq
);

    // ---- Yazmaç adresleri ----
    localparam logic [7:0] TIM_PRE = 8'h00;
    localparam logic [7:0] TIM_ARE = 8'h04;
    localparam logic [7:0] TIM_CLR = 8'h08;
    localparam logic [7:0] TIM_ENA = 8'h0C;
    localparam logic [7:0] TIM_MOD = 8'h10;
    localparam logic [7:0] TIM_CNT = 8'h14;
    localparam logic [7:0] TIM_EVN = 8'h18;
    localparam logic [7:0] TIM_EVC = 8'h1C;

    // ---- Yazmaçlar ----
    logic [31:0] reg_pre;   // Prescaler
    logic [31:0] reg_are;   // Auto-reload
    logic        reg_ena;   // Enable
    logic        reg_mod;   // 0=up, 1=down
    logic [31:0] reg_cnt;   // Sayaç
    logic [31:0] reg_evn;   // Event sayacı

    // ---- Prescaler sayacı ----
    logic [31:0] pre_cnt;

    // ================================================================
    // TODO: Timer ve AXI4-Lite FSM implementasyonu
    //
    // Sayaç mantığı:
    //   Her (pre_cnt == reg_pre) çevrimde reg_cnt artar/azalır
    //   reg_mod=0 (yukarı): reg_cnt == reg_are → overflow, timer_irq=1, reg_cnt=0
    //   reg_mod=1 (aşağı): reg_cnt == 0        → underflow, timer_irq=1, reg_cnt=reg_are
    //   timer_irq tek çevrimlik puls olmalı
    //
    // TIM_CLR yazma: reg_cnt=0 ve pre_cnt=0
    // TIM_EVC yazma: reg_evn=0
    // ================================================================

    assign timer_irq = 1'b0; // stub

    assign s_axil_awready = 1'b0;
    assign s_axil_wready  = 1'b0;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_bvalid  = 1'b0;
    assign s_axil_arready = 1'b0;
    assign s_axil_rdata   = 32'h0;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_pre <= 32'h1;
            reg_are <= 32'hFFFF_FFFF;
            reg_ena <= 1'b0;
            reg_mod <= 1'b0;
            reg_cnt <= 32'h0;
            reg_evn <= 32'h0;
            pre_cnt <= 32'h0;
        end
    end
    // TODO: AXI yazma/okuma ve sayaç mantığı

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (|s_axil_awaddr) | (|s_axil_wdata) | (|s_axil_wstrb)
                  | s_axil_bready | (|s_axil_araddr) | s_axil_rready
                  | reg_pre[0] | reg_are[0] | reg_ena | reg_mod
                  | reg_cnt[0] | reg_evn[0] | pre_cnt[0];
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
