// ============================================================
// Module : uart0
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Enes Kırmızı
// Date   : 2026-05-XX
// Desc   : UART0 — Genel amaçlı UART, AXI4-Lite slave.
//          Baud rate = sys_clk / UART_CPB
//          Min 1 Mbps, en az 2 baud rate desteği.
//          Yazmaçlar:
//            0x00 UART_CPB (RW) — Clocks Per Bit (baud rate bölücü)
//            0x04 UART_STP (RW) — Stop bit sayısı: 0=1bit, 1=2bit
//            0x08 UART_RDR (RO) — Alınan byte (okununca FIFO çıkar)
//            0x0C UART_TDR (RW) — Gönderilecek byte (yazma ile TX başlar)
//            0x10 UART_CFG (RO) — Durum: [0]=TX_BUSY, [1]=RX_VALID, [2]=RX_ERR
// ============================================================

`timescale 1ns/1ps

module uart0 #(
    parameter int AXIL_ADDR_WIDTH = 8,
    parameter int FIFO_DEPTH      = 8
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

    // ---- UART fiziksel pinler ----
    output logic uart_tx,
    input  logic uart_rx,

    // ---- Kesme ----
    output logic uart0_irq   // RX byte hazır veya TX tamamlandı
);

    // ---- Yazmaç adresleri ----
    localparam logic [7:0] UART_CPB = 8'h00;
    localparam logic [7:0] UART_STP = 8'h04;
    localparam logic [7:0] UART_RDR = 8'h08;
    localparam logic [7:0] UART_TDR = 8'h0C;
    localparam logic [7:0] UART_CFG = 8'h10;

    // ---- Yazmaçlar ----
    logic [31:0] reg_cpb;       // Clocks Per Bit (varsayılan: 100 @ 100MHz = 1Mbps)
    logic        reg_stp;       // Stop bit sayısı
    logic [7:0]  tx_data;
    logic        tx_start;
    logic        tx_busy;
    logic [7:0]  rx_data;
    logic        rx_valid;
    logic        rx_err;

    // ================================================================
    // TODO: UART TX/RX implementasyonu + AXI4-Lite FSM
    //
    // TX state machine:
    //   IDLE → START_BIT (uart_tx=0, cpb çevrim) →
    //   DATA[0..7] (her bit cpb çevrim) → STOP_BIT(ler) → IDLE
    //
    // RX state machine:
    //   RX hattı 0'a düştüğünde start bit algıla →
    //   cpb/2 bekle (orta nokta hizalama) →
    //   Her cpb çevrimde bir bit örnekle →
    //   8 bit topla → stop bit kontrol → rx_valid=1
    //
    // FIFO: FIFO_DEPTH derinliğinde RX FIFO (basit shift register yeterli)
    //
    // Kesme: rx_valid puls → uart0_irq puls
    // ================================================================

    assign uart_tx   = 1'b1; // Idle high
    assign uart0_irq = 1'b0; // stub

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
            reg_cpb  <= 32'd100; // 100MHz / 100 = 1Mbps
            reg_stp  <= 1'b0;
            tx_busy  <= 1'b0;
            rx_valid <= 1'b0;
            rx_err   <= 1'b0;
        end
    end
    // TODO: TX/RX mantığı ve AXI yazma/okuma

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (|s_axil_awaddr) | (|s_axil_wdata) | (|s_axil_wstrb)
                  | s_axil_bready | (|s_axil_araddr) | s_axil_rready
                  | uart_rx | reg_cpb[0] | reg_stp | tx_data[0] | tx_start
                  | tx_busy | rx_data[0] | rx_valid | rx_err;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
