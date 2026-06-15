`timescale 1ns/1ps

module npu_top
    import npu_pkg::*;
#(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int AXI_ID_WIDTH   = 4,
    parameter int CSR_ADDR_WIDTH = 8
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4-Lite Slave (CSR) ----
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

    // ---- AXI4 Master (AI_MEM) ----
    output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [3:0]                m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,
    output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,

    // ---- IRQ ----
    output logic                      npu_irq
);

    // ---- CSR ↔ FSM ----
    logic        csr_start;
    logic [31:0] csr_input_addr, csr_weight_addr;
    logic        fsm_done, fsm_busy;
    logic [1:0]  argmax_result;

    // ---- AXI okuma motoru ↔ FSM ----
    logic        rd_start, rd_valid, rd_busy, rd_done;
    logic [31:0] rd_addr;
    logic [15:0] rd_len;
    logic [7:0]  rd_byte;

    // ---- input_buffer yazma ----
    logic                              in_wr_en;
    logic [$clog2(INPUT_SIZE)-1:0]     in_wr_addr;
    logic [7:0]                        in_wr_data;
    logic                              dw_w_wr_en;
    logic [$clog2(DW_WEIGHT_BYTES)-1:0] dw_w_wr_addr;
    logic [7:0]                        dw_w_wr_data;
    // ---- fc_weight_buffer yazma ----
    logic                              fc_w_wr_en;
    logic [$clog2(FC_WEIGHT_BYTES)-1:0] fc_w_wr_addr;
    logic [7:0]                        fc_w_wr_data;

    // ---- Quant parametreleri ----
    logic signed [31:0] input_zp, dw_out_zp, dw_act_min, dw_act_max;
    logic signed [31:0] dw_mult  [0:NUM_FILTERS-1];
    logic signed [31:0] dw_shift [0:NUM_FILTERS-1];
    logic signed [31:0] dw_bias  [0:NUM_FILTERS-1];
    logic signed [31:0] fc_bias  [0:FC_OUTPUTS-1];
    logic signed [31:0] fc_mult  [0:FC_OUTPUTS-1];
    logic signed [31:0] fc_shift [0:FC_OUTPUTS-1];
    logic signed [31:0] fc_out_zp;

    // ---- Katman handshake ----
    logic dw_start, dw_done, fc_start, fc_done, argmax_start, argmax_done;

    // ---- DW ↔ input_buffer / local_buffer ----
    logic [$clog2(INPUT_SIZE)-1:0]      dw_in_rd_addr;
    logic signed [7:0]                  dw_in_rd_data;
    logic [$clog2(DW_WEIGHT_BYTES)-1:0] dw_w_rd_addr;
    logic signed [7:0]                  dw_w_rd_data;
    logic                               lbuf_wr_en;
    logic [$clog2(FC_FLAT)-1:0]         lbuf_wr_addr;
    logic signed [7:0]                  lbuf_wr_data;

    // ---- FC ↔ local_buffer / fc_weight_buffer ----
    logic [$clog2(FC_FLAT)-1:0]         fc_in_rd_addr;
    logic signed [7:0]                  fc_in_rd_data;
    logic [$clog2(FC_WEIGHT_BYTES)-1:0] fc_w_rd_addr;
    logic signed [7:0]                  fc_w_rd_data;
    logic signed [7:0]                  fc_logits [0:FC_OUTPUTS-1];  // per-channel requant sonrası INT8
    logic                               fc_logits_valid;

    // AXI denetleyici (CSR slave + okuma motoru)
    axi_controller #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH), .CSR_ADDR_WIDTH(CSR_ADDR_WIDTH)
    ) u_axi (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid), .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .csr_start(csr_start), .csr_input_addr(csr_input_addr), .csr_weight_addr(csr_weight_addr),
        .fsm_done(fsm_done), .fsm_busy(fsm_busy), .fsm_result(argmax_result),
        .rd_start(rd_start), .rd_addr(rd_addr), .rd_len(rd_len),
        .rd_byte(rd_byte), .rd_valid(rd_valid), .rd_busy(rd_busy), .rd_done(rd_done)
    );

    // Kontrol FSM + loader
    fsm_controller u_fsm (
        .clk(clk), .rst_n(rst_n),
        .start(csr_start), .input_base_addr(csr_input_addr), .weight_base_addr(csr_weight_addr),
        .rd_start(rd_start), .rd_addr(rd_addr), .rd_len(rd_len),
        .rd_byte(rd_byte), .rd_valid(rd_valid), .rd_busy(rd_busy), .rd_done(rd_done),
        .in_wr_en(in_wr_en), .in_wr_addr(in_wr_addr), .in_wr_data(in_wr_data),
        .dw_w_wr_en(dw_w_wr_en), .dw_w_wr_addr(dw_w_wr_addr), .dw_w_wr_data(dw_w_wr_data),
        .fc_w_wr_en(fc_w_wr_en), .fc_w_wr_addr(fc_w_wr_addr), .fc_w_wr_data(fc_w_wr_data),
        .input_zp(input_zp), .dw_out_zp(dw_out_zp), .dw_act_min(dw_act_min), .dw_act_max(dw_act_max),
        .dw_mult(dw_mult), .dw_shift(dw_shift), .dw_bias(dw_bias),
        .fc_bias(fc_bias), .fc_mult(fc_mult), .fc_shift(fc_shift), .fc_out_zp(fc_out_zp),
        .dw_start(dw_start), .dw_done(dw_done),
        .fc_start(fc_start), .fc_done(fc_done),
        .argmax_start(argmax_start), .argmax_done(argmax_done),
        .busy(fsm_busy), .done(fsm_done), .result(argmax_result), .irq(npu_irq)
    );

    // On-chip tamponlar
    input_buffer u_ibuf (
        .clk(clk),
        .in_wr_en(in_wr_en), .in_wr_addr(in_wr_addr), .in_wr_data(in_wr_data),
        .dw_w_wr_en(dw_w_wr_en), .dw_w_wr_addr(dw_w_wr_addr), .dw_w_wr_data(dw_w_wr_data),
        .in_rd_addr(dw_in_rd_addr), .in_rd_data(dw_in_rd_data),
        .dw_w_rd_addr(dw_w_rd_addr), .dw_w_rd_data(dw_w_rd_data)
    );

    fc_weight_buffer u_fcwbuf (
        .clk(clk),
        .wr_en(fc_w_wr_en), .wr_addr(fc_w_wr_addr), .wr_data(fc_w_wr_data),
        .rd_addr(fc_w_rd_addr), .rd_data(fc_w_rd_data)
    );

    local_buffer #(.DEPTH(FC_FLAT), .DATA_WIDTH(8)) u_lbuf (
        .clk(clk),
        .wr_en(lbuf_wr_en), .wr_addr(lbuf_wr_addr), .wr_data(lbuf_wr_data),
        .rd_addr(fc_in_rd_addr), .rd_data(fc_in_rd_data)
    );

    // Hesaplama katmanları
    depthwise_conv2d u_dw (
        .clk(clk), .rst_n(rst_n), .start(dw_start), .done(dw_done),
        .input_zp(input_zp), .out_zp(dw_out_zp), .act_min(dw_act_min), .act_max(dw_act_max),
        .dw_mult(dw_mult), .dw_shift(dw_shift), .dw_bias(dw_bias),
        .in_rd_addr(dw_in_rd_addr), .in_rd_data(dw_in_rd_data),
        .dw_w_rd_addr(dw_w_rd_addr), .dw_w_rd_data(dw_w_rd_data),
        .out_wr_en(lbuf_wr_en), .out_wr_addr(lbuf_wr_addr), .out_wr_data(lbuf_wr_data)
    );

    fully_connected u_fc (
        .clk(clk), .rst_n(rst_n), .start(fc_start), .done(fc_done),
        .fc_input_zp(dw_out_zp), .fc_bias(fc_bias),
        .fc_mult(fc_mult), .fc_shift(fc_shift), .fc_out_zp(fc_out_zp),
        .in_rd_addr(fc_in_rd_addr), .in_data(fc_in_rd_data),
        .weight_rd_addr(fc_w_rd_addr), .weight_data(fc_w_rd_data),
        .logits(fc_logits), .logits_valid(fc_logits_valid)
    );

    softmax_argmax #(.NUM_CLASSES(FC_OUTPUTS), .LOGIT_WIDTH(8)) u_argmax (
        .clk(clk), .rst_n(rst_n), .start(argmax_start), .done(argmax_done),
        .logits(fc_logits), .result(argmax_result)
    );

    // logits_valid kullanılmıyor (argmax start ile senkron)
    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = fc_logits_valid;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
