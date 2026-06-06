// ============================================================
// Module : gpio
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Enes Kırmızı
// Date   : 2026-05-XX
// Desc   : 32-pin GPIO çevre birimi — AXI4-Lite slave.
//          16 pin sabit giriş, 16 pin sabit çıkış.
//          Yazmaçlar:
//            0x00 GPIO_IDR (RO) — giriş pini değerleri [15:0]
//            0x04 GPIO_ODR (RW) — çıkış pini değerleri [15:0]
// ============================================================

`timescale 1ns/1ps

module gpio #(
    parameter int AXIL_ADDR_WIDTH = 8,
    parameter int NUM_IN          = 16,
    parameter int NUM_OUT         = 16
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

    // ---- GPIO fiziksel pinler ----
    input  logic [NUM_IN-1:0]  gpio_in,   // Harici giriş pinleri
    output logic [NUM_OUT-1:0] gpio_out   // Harici çıkış pinleri
);

    // ---- Yazmaç adresleri ----
    localparam logic [AXIL_ADDR_WIDTH-1:0] GPIO_IDR = 8'h00; // Input Data Register (RO)
    localparam logic [AXIL_ADDR_WIDTH-1:0] GPIO_ODR = 8'h04; // Output Data Register (RW)

    // ---- Yazmaçlar ----
    logic [NUM_OUT-1:0] reg_odr;

    assign gpio_out = reg_odr;

    // ================================================================
    // TODO: AXI4-Lite slave yazma/okuma FSM'i
    //
    // Yazma:
    //   GPIO_ODR adresine yazma → reg_odr güncelle
    //   GPIO_IDR adresine yazma → yoksay (RO)
    //
    // Okuma:
    //   GPIO_IDR → {16'h0, gpio_in}   (doğrudan fiziksel pin)
    //   GPIO_ODR → {16'h0, reg_odr}
    //
    // AXI4-Lite kuralları:
    //   AWREADY ve WREADY aynı anda 1 olabilir (single-clock response)
    //   BRESP = 2'b00 (OKAY)
    //   RRESP = 2'b00 (OKAY)
    // ================================================================

    // Stub
    assign s_axil_awready = 1'b0;
    assign s_axil_wready  = 1'b0;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_bvalid  = 1'b0;
    assign s_axil_arready = 1'b0;
    assign s_axil_rdata   = 32'h0;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = 1'b0;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) reg_odr <= '0;
    // TODO: yazma mantığı

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (|s_axil_awaddr) | (|s_axil_wdata) | (|s_axil_wstrb)
                  | s_axil_bready | (|s_axil_araddr) | s_axil_rready;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
