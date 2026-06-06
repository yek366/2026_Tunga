// ============================================================
// Module : obi_axi_bridge
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Sevda Oğraş
// Date   : 2026-05-XX
// Desc   : CV32E40P OBI veri yolunu AXI4'e dönüştürür.
//          İki bağımsız köprü örneği kullanılır:
//          1) Buyruk (instruction) OBI → AXI4-Lite (read-only)
//          2) Veri (data)         OBI → AXI4       (read/write)
// ============================================================

`timescale 1ns/1ps

// ---- OBI → AXI4 genel amaçlı köprü ----
// tunga_soc.sv içinde iki kez örneklenir (instr + data)
module obi_axi_bridge #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4
) (
    input  logic clk,
    input  logic rst_n,

    // ---- OBI Slave (CV32E40P tarafı) ----
    input  logic                  obi_req,
    output logic                  obi_gnt,
    input  logic [ADDR_WIDTH-1:0] obi_addr,
    input  logic                  obi_we,
    input  logic [3:0]            obi_be,
    input  logic [DATA_WIDTH-1:0] obi_wdata,
    output logic [DATA_WIDTH-1:0] obi_rdata,
    output logic                  obi_rvalid,
    output logic                  obi_err,

    // ---- AXI4 Master (Interconnect tarafı) ----
    // Yazma adresi kanalı
    output logic [ID_WIDTH-1:0]   m_axi_awid,
    output logic [ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [7:0]            m_axi_awlen,
    output logic [2:0]            m_axi_awsize,
    output logic [1:0]            m_axi_awburst,
    output logic                  m_axi_awvalid,
    input  logic                  m_axi_awready,
    // Yazma veri kanalı
    output logic [DATA_WIDTH-1:0] m_axi_wdata,
    output logic [3:0]            m_axi_wstrb,
    output logic                  m_axi_wlast,
    output logic                  m_axi_wvalid,
    input  logic                  m_axi_wready,
    // Yazma yanıt kanalı
    input  logic [ID_WIDTH-1:0]   m_axi_bid,
    input  logic [1:0]            m_axi_bresp,
    input  logic                  m_axi_bvalid,
    output logic                  m_axi_bready,
    // Okuma adresi kanalı
    output logic [ID_WIDTH-1:0]   m_axi_arid,
    output logic [ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [7:0]            m_axi_arlen,
    output logic [2:0]            m_axi_arsize,
    output logic [1:0]            m_axi_arburst,
    output logic                  m_axi_arvalid,
    input  logic                  m_axi_arready,
    // Okuma veri kanalı
    input  logic [ID_WIDTH-1:0]   m_axi_rid,
    input  logic [DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0]            m_axi_rresp,
    input  logic                  m_axi_rlast,
    input  logic                  m_axi_rvalid,
    output logic                  m_axi_rready
);

    // ---- FSM durum tanımı ----
    typedef enum logic [2:0] {
        IDLE,
        AR_SENT,   // Okuma adresi gönderildi
        R_WAIT,    // Okuma verisi bekleniyor
        AW_SENT,   // Yazma adresi gönderildi
        W_SENT,    // Yazma verisi gönderildi
        B_WAIT     // Yazma yanıtı bekleniyor
    } bridge_state_t;

    bridge_state_t state;

    // ---- Adres ve veri latch'leri ----
    logic [ADDR_WIDTH-1:0] addr_lat;
    logic [DATA_WIDTH-1:0] wdata_lat;
    logic [3:0]            be_lat;
    logic                  we_lat;

    // ================================================================
    // TODO: OBI → AXI4 köprü FSM'ini buraya implemente et.
    //
    // Temel kural:
    //   OBI okuma : obi_req=1 & obi_we=0 → AXI AR kanalı → AXI R kanalı → obi_rvalid=1
    //   OBI yazma : obi_req=1 & obi_we=1 → AXI AW + W kanalı → AXI B kanalı → obi_rvalid=1
    //
    // OBI gnt politikası:
    //   obi_gnt = 1 sadece IDLE durumunda yeni istek kabul edildiğinde
    //
    // AXI sabit değerler (tek-beat transfer):
    //   awlen=0, awsize=2 (4 byte), awburst=INCR
    //   arlen=0, arsize=2 (4 byte), arburst=INCR
    //
    // Hata yönetimi:
    //   AXI BRESP/RRESP != OKAY ise obi_err=1
    // ================================================================

    // Stub — sadece derleme için
    assign obi_gnt    = 1'b0;
    assign obi_rdata  = '0;
    assign obi_rvalid = 1'b0;
    assign obi_err    = 1'b0;

    assign m_axi_awid    = '0;
    assign m_axi_awaddr  = '0;
    assign m_axi_awlen   = 8'h0;
    assign m_axi_awsize  = 3'b010;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = 1'b0;
    assign m_axi_wdata   = '0;
    assign m_axi_wstrb   = '0;
    assign m_axi_wlast   = 1'b0;
    assign m_axi_wvalid  = 1'b0;
    assign m_axi_bready  = 1'b1;
    assign m_axi_arid    = '0;
    assign m_axi_araddr  = '0;
    assign m_axi_arlen   = 8'h0;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = 1'b0;
    assign m_axi_rready  = 1'b1;

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = m_axi_awready | m_axi_wready | (|m_axi_bid) | (|m_axi_bresp)
                  | m_axi_bvalid | m_axi_arready | (|m_axi_rid) | (|m_axi_rdata)
                  | (|m_axi_rresp) | m_axi_rlast | m_axi_rvalid
                  | addr_lat[0] | wdata_lat[0] | be_lat[0] | we_lat | state[0];
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
