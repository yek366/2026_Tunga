// ============================================================
// Module : qspi_master
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Enes Kırmızı
// Date   : 2026-05-XX
// Desc   : QSPI Master — Harici NOR Flash MT25QL256ABA8E12 ile haberleşir.
//          Desteklenen modlar: x1, x2, x4 (Quad SPI)
//          SPI Mode 0: CPOL=0, CPHA=0
//          4-byte adresleme, 256-byte sayfa yazma/okuma.
//          Yazmaçlar:
//            0x00 QSPI_CCR (RW) — Komut+Konfigürasyon: [7:0]=komut, [9:8]=mod(x1/x2/x4)
//            0x04 QSPI_ADR (RW) — Flash adresi (32-bit, 4-byte)
//            0x08 QSPI_DR  (RW) — Veri yazmacı (TX/RX FIFO erişimi)
//            0x0C QSPI_STA (RO) — Durum: [0]=BUSY, [1]=TX_EMPTY, [2]=RX_VALID
//            0x10 QSPI_FCR (RW) — FIFO kontrol: [0]=TX_CLR, [1]=RX_CLR
// ============================================================

`timescale 1ns/1ps

module qspi_master #(
    parameter int AXIL_ADDR_WIDTH = 8,
    parameter int FIFO_DEPTH      = 64   // 64 × 32-bit TX ve RX FIFO
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

    // ---- QSPI fiziksel pinler ----
    output logic       qspi_sck,
    output logic       qspi_csn,    // Chip Select (active-low)
    inout  wire  [3:0] qspi_io      // IO[0]=MOSI/SO, IO[1]=MISO/SI, IO[2]=WP#, IO[3]=HOLD#
);

    localparam logic [7:0] QSPI_CCR_ADDR = 8'h00;
    localparam logic [7:0] QSPI_ADR_ADDR = 8'h04;
    localparam logic [7:0] QSPI_DR_ADDR  = 8'h08;
    localparam logic [7:0] QSPI_STA_ADDR = 8'h0C;
    localparam logic [7:0] QSPI_FCR_ADDR = 8'h10;

    // Desteklenen Flash komutları (MT25QL256ABA8E12)
    localparam logic [7:0] CMD_READ    = 8'h03;
    localparam logic [7:0] CMD_DOR     = 8'h3B; // Dual Output Read
    localparam logic [7:0] CMD_QOR     = 8'h6B; // Quad Output Read
    localparam logic [7:0] CMD_PP      = 8'h02; // Page Program
    localparam logic [7:0] CMD_QPP     = 8'h32; // Quad Page Program
    localparam logic [7:0] CMD_SE      = 8'hD8; // Sector Erase
    localparam logic [7:0] CMD_WREN    = 8'h06; // Write Enable
    localparam logic [7:0] CMD_RDSR1   = 8'h05; // Read Status Register 1

    logic [31:0] reg_ccr;
    logic [31:0] reg_adr;
    logic        busy;

    // Tri-state yönetimi
    logic [3:0] qspi_io_out;
    logic [3:0] qspi_io_oe;  // Output enable
    logic [3:0] qspi_io_in;

    assign qspi_io    = (|qspi_io_oe) ? qspi_io_out : 4'bzzzz;
    assign qspi_io_in = qspi_io;

    // ================================================================
    // TODO: QSPI state machine
    //
    // Faz sırası (her komut için):
    //   1. CS assert (qspi_csn=0)
    //   2. Komut gönder (8-bit, x1 mod)
    //   3. Adres gönder (32-bit, x1 veya x4)
    //   4. Dummy çevrimler (komuta bağlı)
    //   5. Veri oku/yaz (x1, x2, veya x4)
    //   6. CS deassert (qspi_csn=1)
    //
    // SCK: sys_clk / 2 (50 MHz @ 100 MHz sistem saati)
    // x4 mod: 4 hat paralel → 4 kat hızlı transfer
    //
    // FIFO: 64×32-bit TX ve RX FIFO
    //   TX: CPU yazar → QSPI gönderir
    //   RX: QSPI alır → CPU okur
    // ================================================================

    assign qspi_sck    = 1'b0;
    assign qspi_csn    = 1'b1; // Deasserted (idle)
    assign qspi_io_out = 4'hF;
    assign qspi_io_oe  = 4'h0;

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
            reg_ccr <= 32'h0;
            reg_adr <= 32'h0;
            busy    <= 1'b0;
        end
    end

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (|s_axil_awaddr) | (|s_axil_wdata) | (|s_axil_wstrb)
                  | s_axil_bready | (|s_axil_araddr) | s_axil_rready
                  | reg_ccr[0] | reg_adr[0] | busy | (|qspi_io_in);
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
