// ============================================================
// Module : uart1_stream
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Enes Kırmızı
// Date   : 2026-05-XX
// Desc   : UART1 Stream — gelen veriyi doğrudan YZ belleğine yazar.
//          CPU yükü sıfır: CPU sadece konfigüre eder, veri akışı otomatik.
//          İki AXI arayüzü:
//            - AXI4-Lite slave : CPU konfigürasyonu (baud, hedef adres)
//            - AXI4 master     : Alınan veriyi AI_MEM'e yazar
//          Yazmaçlar:
//            0x00 UART_CPB    (RW) — Clocks Per Bit
//            0x04 UART_DADDR  (RW) — Hedef bellek adresi (AI_MEM başlangıcı)
//            0x08 UART_DLEN   (RW) — Beklenen veri uzunluğu (byte)
//            0x0C UART_CFG    (RO) — [0]=BUSY, [1]=DONE, [2]=RX_ERR
// ============================================================

`timescale 1ns/1ps

module uart1_stream #(
    parameter int AXIL_ADDR_WIDTH = 8,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 32,
    parameter int AXI_ID_WIDTH    = 4
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4-Lite Slave (CPU konfigürasyon) ----
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

    // ---- AXI4 Master (AI_MEM yazma) ----
    output logic [AXI_ID_WIDTH-1:0]    m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]                 m_axi_awlen,
    output logic [2:0]                 m_axi_awsize,
    output logic [1:0]                 m_axi_awburst,
    output logic                       m_axi_awvalid,
    input  logic                       m_axi_awready,
    output logic [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [3:0]                 m_axi_wstrb,
    output logic                       m_axi_wlast,
    output logic                       m_axi_wvalid,
    input  logic                       m_axi_wready,
    input  logic [AXI_ID_WIDTH-1:0]    m_axi_bid,
    input  logic [1:0]                 m_axi_bresp,
    input  logic                       m_axi_bvalid,
    output logic                       m_axi_bready,

    // ---- UART fiziksel pin ----
    input  logic uart1_rx,

    // ---- Kesme ----
    output logic uart1_irq   // Transfer tamamlandı
);

    localparam logic [7:0] UART_CPB   = 8'h00;
    localparam logic [7:0] UART_DADDR = 8'h04;
    localparam logic [7:0] UART_DLEN  = 8'h08;
    localparam logic [7:0] UART_CFG   = 8'h0C;

    logic [31:0] reg_cpb;
    logic [31:0] reg_daddr;
    logic [31:0] reg_dlen;
    logic        busy;
    logic        done;

    // ================================================================
    // TODO: UART1 stream implementasyonu
    //
    // RX FSM: UART byte alır (uart1_rx hattı)
    // Write buffer: 4 byte biriktir → 32-bit AXI word oluştur
    // AXI write FSM: AW kanalı → W kanalı → B yanıtı
    //   Her word için: m_axi_awaddr = reg_daddr + byte_count
    //   reg_dlen byte gelince done=1, uart1_irq=1
    //
    // ÖNEMLİ: Bu modül CPU müdahalesi olmadan çalışır.
    //   CPU sadece reg_cpb, reg_daddr, reg_dlen'i yazar ve bekler.
    // ================================================================

    assign uart1_irq = 1'b0;

    assign s_axil_awready = 1'b0;
    assign s_axil_wready  = 1'b0;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_bvalid  = 1'b0;
    assign s_axil_arready = 1'b0;
    assign s_axil_rdata   = 32'h0;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = 1'b0;

    assign m_axi_awid    = '0;
    assign m_axi_awaddr  = '0;
    assign m_axi_awlen   = 8'h0;
    assign m_axi_awsize  = 3'b000;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = 1'b0;
    assign m_axi_wdata   = '0;
    assign m_axi_wstrb   = 4'hF;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = 1'b0;
    assign m_axi_bready  = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_cpb   <= 32'd100;
            reg_daddr <= 32'h0001_0000; // AI_MEM başlangıcı
            reg_dlen  <= 32'h0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end
    end

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (|s_axil_awaddr) | (|s_axil_wdata) | (|s_axil_wstrb)
                  | s_axil_bready | (|s_axil_araddr) | s_axil_rready
                  | m_axi_awready | m_axi_wready | (|m_axi_bid)
                  | (|m_axi_bresp) | m_axi_bvalid | uart1_rx
                  | reg_cpb[0] | reg_daddr[0] | reg_dlen[0] | busy | done;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
