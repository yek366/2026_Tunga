// ============================================================
// Module : i2c_master
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Enes Kırmızı
// Date   : 2026-05-XX
// Desc   : I2C Master — AXI4-Lite slave. SCL sabit 400 kHz (Fast Mode).
//          7-bit adresleme, 1-4 byte transfer.
//          Referans: github.com/mbaykenar/apis_anatolia ders27
//          Yazmaçlar:
//            0x00 I2C_NBY (RW) — Transfer uzunluğu: 1-4 byte [1:0]
//            0x04 I2C_ADR (RW) — 7-bit slave adresi [6:0]
//            0x08 I2C_RDR (RO) — Alınan veri (okununca hazır)
//            0x0C I2C_TDR (RW) — Gönderilecek veri (yazma ile TX başlar)
//            0x10 I2C_CFG (RW) — [0]=TX_EN, [1]=RX_EN, [7:4]=STATUS
//              STATUS: 0=IDLE, 1=BUSY, 2=ACK_ERR, 3=DONE
// ============================================================

`timescale 1ns/1ps

module i2c_master #(
    parameter int AXIL_ADDR_WIDTH = 8,
    parameter int SYS_CLK_MHZ    = 100,   // Sistem saati MHz
    parameter int I2C_CLK_KHZ    = 400    // I2C SCL frekansı kHz (Fast Mode)
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

    // ---- I2C fiziksel pinler (open-drain) ----
    inout wire i2c_scl,
    inout wire i2c_sda,

    // ---- Kesme ----
    output logic i2c_irq   // Transfer tamamlandı veya hata
);

    // SCL bölücü: sys_clk / (4 * I2C_CLK) çevrim başına quarter-period
    localparam int SCL_DIV = SYS_CLK_MHZ * 1000 / (4 * I2C_CLK_KHZ);

    localparam logic [7:0] I2C_NBY = 8'h00;
    localparam logic [7:0] I2C_ADR = 8'h04;
    localparam logic [7:0] I2C_RDR = 8'h08;
    localparam logic [7:0] I2C_TDR = 8'h0C;
    localparam logic [7:0] I2C_CFG = 8'h10;

    logic [1:0]  reg_nby;
    logic [6:0]  reg_adr;
    logic [31:0] reg_tdr;
    logic [31:0] reg_rdr;
    logic        tx_en;
    logic        rx_en;
    logic [3:0]  status;

    // Open-drain sürücü
    logic scl_out, sda_out;
    logic scl_in,  sda_in;

    assign i2c_scl = scl_out ? 1'bz : 1'b0;
    assign i2c_sda = sda_out ? 1'bz : 1'b0;
    assign scl_in  = i2c_scl;
    assign sda_in  = i2c_sda;

    // ================================================================
    // TODO: I2C Master FSM
    //
    // Durum sırası:
    //   IDLE → START → ADDR_SEND (7-bit + R/W bit) → ACK_WAIT →
    //   DATA_SEND/RECV (reg_nby byte) → ACK_WAIT → STOP → DONE
    //
    // SCL üretimi: SCL_DIV çevrimde quarter-period
    //   HIGH → FALL → LOW → RISE → HIGH ...
    //
    // Start condition: SDA HIGH→LOW, SCL HIGH
    // Stop condition:  SDA LOW→HIGH, SCL HIGH
    //
    // ACK: 9. bit sonrası SDA=1'bz, slave SDA'yı 0'a çekerse ACK var
    //
    // Hata: ACK gelmezse i2c_irq=1, status=ACK_ERR
    // ================================================================

    assign scl_out = 1'b1; // Idle high (open-drain)
    assign sda_out = 1'b1;
    assign i2c_irq = 1'b0;

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
            reg_nby <= 2'h1;
            reg_adr <= 7'h0;
            reg_tdr <= 32'h0;
            reg_rdr <= 32'h0;
            tx_en   <= 1'b0;
            rx_en   <= 1'b0;
            status  <= 4'h0;
        end
    end

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (|s_axil_awaddr) | (|s_axil_wdata) | (|s_axil_wstrb)
                  | s_axil_bready | (|s_axil_araddr) | s_axil_rready
                  | reg_nby[0] | reg_adr[0] | reg_tdr[0] | reg_rdr[0]
                  | tx_en | rx_en | (|status) | scl_in | sda_in;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
