`timescale 1ns/1ps

module npu_subsystem
    import npu_pkg::*;
#(
    parameter int          AXI_ADDR_WIDTH = 32,
    parameter int          AXI_DATA_WIDTH = 32,
    parameter int          AXI_ID_WIDTH   = 4,
    parameter int          CSR_ADDR_WIDTH = 8,
    parameter logic [31:0] AIMEM_BASE     = 32'h0001_0000, // AI_MEM taban adresi
    parameter int          AIMEM_SIZE     = 30720,         // 30 KB
    parameter string       AIMEM_INIT     = ""             // önyükleme dosyası
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4-Lite Slave (CSR) — sistem tarafı (CPU/interconnect) ----
    input  logic [CSR_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  logic                      s_axil_awvalid,
    output logic                      s_axil_awready,
    input  logic [31:0]               s_axil_wdata,
    input  logic [3:0]                s_axil_wstrb,
    input  logic                      s_axil_wvalid,
    output logic                      s_axil_wready,
    output logic [1:0]                s_axil_bresp,
    output logic                      s_axil_bvalid,
    input  logic                      s_axil_bready,
    input  logic [CSR_ADDR_WIDTH-1:0] s_axil_araddr,
    input  logic                      s_axil_arvalid,
    output logic                      s_axil_arready,
    output logic [31:0]               s_axil_rdata,
    output logic [1:0]                s_axil_rresp,
    output logic                      s_axil_rvalid,
    input  logic                      s_axil_rready,

    // ---- IRQ → CPU ----
    output logic                      npu_irq
);

    // ---- NPU AXI4 master ↔ AI_MEM AXI4 slave (alt-sistem iç hattı) ----
    logic [AXI_ID_WIDTH-1:0]   axi_awid;
    logic [AXI_ADDR_WIDTH-1:0] axi_awaddr;
    logic [7:0]                axi_awlen;
    logic [2:0]                axi_awsize;
    logic [1:0]                axi_awburst;
    logic                      axi_awvalid, axi_awready;
    logic [AXI_DATA_WIDTH-1:0] axi_wdata;
    logic [3:0]                axi_wstrb;
    logic                      axi_wlast, axi_wvalid, axi_wready;
    logic [AXI_ID_WIDTH-1:0]   axi_bid;
    logic [1:0]                axi_bresp;
    logic                      axi_bvalid, axi_bready;
    logic [AXI_ID_WIDTH-1:0]   axi_arid;
    logic [AXI_ADDR_WIDTH-1:0] axi_araddr;
    logic [7:0]                axi_arlen;
    logic [2:0]                axi_arsize;
    logic [1:0]                axi_arburst;
    logic                      axi_arvalid, axi_arready;
    logic [AXI_ID_WIDTH-1:0]   axi_rid;
    logic [AXI_DATA_WIDTH-1:0] axi_rdata;
    logic [1:0]                axi_rresp;
    logic                      axi_rlast, axi_rvalid, axi_rready;

    // NPU çekirdeği (CSR slave dışarı, AXI4 master içeri)
    npu_top #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH), .CSR_ADDR_WIDTH(CSR_ADDR_WIDTH)
    ) u_npu (
        .clk(clk), .rst_n(rst_n),
        // CSR slave → dışarı
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        // AXI4 master → AI_MEM
        .m_axi_awid(axi_awid), .m_axi_awaddr(axi_awaddr), .m_axi_awlen(axi_awlen), .m_axi_awsize(axi_awsize),
        .m_axi_awburst(axi_awburst), .m_axi_awvalid(axi_awvalid), .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata), .m_axi_wstrb(axi_wstrb), .m_axi_wlast(axi_wlast), .m_axi_wvalid(axi_wvalid), .m_axi_wready(axi_wready),
        .m_axi_bid(axi_bid), .m_axi_bresp(axi_bresp), .m_axi_bvalid(axi_bvalid), .m_axi_bready(axi_bready),
        .m_axi_arid(axi_arid), .m_axi_araddr(axi_araddr), .m_axi_arlen(axi_arlen), .m_axi_arsize(axi_arsize),
        .m_axi_arburst(axi_arburst), .m_axi_arvalid(axi_arvalid), .m_axi_arready(axi_arready),
        .m_axi_rid(axi_rid), .m_axi_rdata(axi_rdata), .m_axi_rresp(axi_rresp), .m_axi_rlast(axi_rlast),
        .m_axi_rvalid(axi_rvalid), .m_axi_rready(axi_rready),
        .npu_irq(npu_irq)
    );

    // AI_MEM (AXI4 salt-okunur slave)
    ai_mem #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH), .ID_WIDTH(AXI_ID_WIDTH),
        .BASE_ADDR(AIMEM_BASE), .SIZE_BYTES(AIMEM_SIZE), .INIT_FILE(AIMEM_INIT)
    ) u_aimem (
        .clk(clk), .rst_n(rst_n),
        .s_axi_arid(axi_arid), .s_axi_araddr(axi_araddr), .s_axi_arlen(axi_arlen),
        .s_axi_arsize(axi_arsize), .s_axi_arburst(axi_arburst),
        .s_axi_arvalid(axi_arvalid), .s_axi_arready(axi_arready),
        .s_axi_rid(axi_rid), .s_axi_rdata(axi_rdata), .s_axi_rresp(axi_rresp),
        .s_axi_rlast(axi_rlast), .s_axi_rvalid(axi_rvalid), .s_axi_rready(axi_rready),
        .s_axi_awid(axi_awid), .s_axi_awaddr(axi_awaddr), .s_axi_awlen(axi_awlen),
        .s_axi_awsize(axi_awsize), .s_axi_awburst(axi_awburst),
        .s_axi_awvalid(axi_awvalid), .s_axi_awready(axi_awready),
        .s_axi_wdata(axi_wdata), .s_axi_wstrb(axi_wstrb), .s_axi_wlast(axi_wlast),
        .s_axi_wvalid(axi_wvalid), .s_axi_wready(axi_wready),
        .s_axi_bid(axi_bid), .s_axi_bresp(axi_bresp), .s_axi_bvalid(axi_bvalid), .s_axi_bready(axi_bready)
    );

endmodule
