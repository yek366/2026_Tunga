// ============================================================
// Module : npu_top
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : NPU üst modülü — TFLite Micro Speech Tiny Conv INT8 çıkarım motoru.
//          AXI4-Lite CSR arayüzü ve AXI4 bellek master arayüzü dışarı açılır.
// ============================================================

`timescale 1ns/1ps

module npu_top #(
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 32,
    parameter int AXI_ID_WIDTH    = 4,
    parameter int CSR_ADDR_WIDTH  = 8,
    // Model sabitleri
    parameter int INPUT_SIZE      = 1960,  // 1960 INT8 giriş elemanı
    parameter int NUM_FILTERS     = 8,
    parameter int KERNEL_H        = 10,
    parameter int KERNEL_W        = 8,
    parameter int FC_OUTPUTS      = 4,
    parameter int FC_INPUTS       = 4000
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4-Lite Slave (CSR) ---- CPU → NPU konfigürasyon
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

    // ---- AXI4 Master (bellek erişimi) ---- NPU → YZ Belleği
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

    // ---- Kesme çıkışı ---- NPU → CPU IRQ
    output logic                      npu_irq
);

    // ---- İç sinyaller ----

    // CSR'dan FSM'e kontrol sinyalleri
    logic        csr_start;
    logic [31:0] csr_input_addr;
    logic [31:0] csr_weight_addr;

    // FSM'den CSR'a durum sinyalleri
    logic        fsm_done;
    logic        fsm_busy;
    logic [1:0]  fsm_result;

    // FSM ↔ bellek kontrolcüsü (AXI master arbiter)
    logic        mem_rd_req;
    logic [31:0] mem_rd_addr;
    logic [15:0] mem_rd_len;
    logic        mem_rd_valid;
    logic [7:0]  mem_rd_data;
    logic        mem_rd_last;
    logic        mem_wr_req;
    logic [31:0] mem_wr_addr;
    logic [31:0] mem_wr_data;
    logic        mem_wr_done;

    // FSM ↔ depthwise conv
    logic        dw_start;
    logic        dw_done;

    // FSM ↔ fully connected
    logic        fc_start;
    logic        fc_done;

    // FSM ↔ argmax
    logic        argmax_start;
    logic        argmax_done;

    // (Hesaplama ara sonuçları local_buffer üzerinden aktarılır — ayrı sinyal gerekmez)

    // ---- Alt modül instantiationları ----

    axi_controller #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH)
    ) u_axi_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        // CSR AXI4-Lite slave
        .s_axil_awaddr    (s_axil_awaddr),
        .s_axil_awvalid   (s_axil_awvalid),
        .s_axil_awready   (s_axil_awready),
        .s_axil_wdata     (s_axil_wdata),
        .s_axil_wstrb     (s_axil_wstrb),
        .s_axil_wvalid    (s_axil_wvalid),
        .s_axil_wready    (s_axil_wready),
        .s_axil_bresp     (s_axil_bresp),
        .s_axil_bvalid    (s_axil_bvalid),
        .s_axil_bready    (s_axil_bready),
        .s_axil_araddr    (s_axil_araddr),
        .s_axil_arvalid   (s_axil_arvalid),
        .s_axil_arready   (s_axil_arready),
        .s_axil_rdata     (s_axil_rdata),
        .s_axil_rresp     (s_axil_rresp),
        .s_axil_rvalid    (s_axil_rvalid),
        .s_axil_rready    (s_axil_rready),
        // AXI4 master
        .m_axi_awid       (m_axi_awid),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),
        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),
        .m_axi_bid        (m_axi_bid),
        .m_axi_bresp      (m_axi_bresp),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready),
        .m_axi_arid       (m_axi_arid),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_rid        (m_axi_rid),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready),
        // FSM arayüzü
        .csr_start        (csr_start),
        .csr_input_addr   (csr_input_addr),
        .csr_weight_addr  (csr_weight_addr),
        .fsm_done         (fsm_done),
        .fsm_busy         (fsm_busy),
        .fsm_result       (fsm_result),
        .mem_rd_req       (mem_rd_req),
        .mem_rd_addr      (mem_rd_addr),
        .mem_rd_len       (mem_rd_len),
        .mem_rd_valid     (mem_rd_valid),
        .mem_rd_data      (mem_rd_data),
        .mem_rd_last      (mem_rd_last),
        .mem_wr_req       (mem_wr_req),
        .mem_wr_addr      (mem_wr_addr),
        .mem_wr_data      (mem_wr_data),
        .mem_wr_done      (mem_wr_done)
    );

    fsm_controller #(
        .INPUT_SIZE    (INPUT_SIZE),
        .NUM_FILTERS   (NUM_FILTERS),
        .KERNEL_H      (KERNEL_H),
        .KERNEL_W      (KERNEL_W)
    ) u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (csr_start),
        .input_base_addr (csr_input_addr),
        .weight_base_addr(csr_weight_addr),
        .mem_rd_req      (mem_rd_req),
        .mem_rd_addr     (mem_rd_addr),
        .mem_rd_len      (mem_rd_len),
        .mem_rd_valid    (mem_rd_valid),
        .mem_rd_data     (mem_rd_data),
        .mem_rd_last     (mem_rd_last),
        .mem_wr_req      (mem_wr_req),
        .mem_wr_addr     (mem_wr_addr),
        .mem_wr_data     (mem_wr_data),
        .mem_wr_done     (mem_wr_done),
        .dw_start        (dw_start),
        .dw_done         (dw_done),
        .fc_start        (fc_start),
        .fc_done         (fc_done),
        .argmax_start    (argmax_start),
        .argmax_done     (argmax_done),
        .busy            (fsm_busy),
        .done            (fsm_done),
        .result          (fsm_result),
        .irq             (npu_irq)
    );

    // ---- İç bağlantı sinyalleri (input_buffer ↔ depthwise_conv2d) ----
    logic [9:0]               ibuf_weight_rd_addr;
    logic signed [7:0]        ibuf_weight_data;
    logic [5:0]               ibuf_col_idx;
    logic signed [7:0]        ibuf_line_buf [0:KERNEL_H-1];

    // ---- İç bağlantı sinyalleri (depthwise_conv2d ↔ local_buffer) ----
    logic                     lbuf_wr_en;
    logic [11:0]              lbuf_wr_addr; // 25*20*8=4000 < 2^12
    logic signed [7:0]        lbuf_wr_data;
    logic [$clog2(FC_INPUTS)-1:0]  lbuf_rd_addr;
    logic signed [7:0]        lbuf_rd_data;

    // ---- İç bağlantı sinyalleri (fully_connected çıkışları) ----
    logic signed [31:0]       fc_logits [0:FC_OUTPUTS-1];
    logic                     fc_logits_valid;

    // ---- FC ağırlık/bias stub sinyalleri (implementasyonda doldurulacak) ----
    logic [$clog2(FC_OUTPUTS*FC_INPUTS)-1:0] fc_weight_rd_addr;
    logic signed [7:0]                       fc_weight_data;
    logic [$clog2(FC_OUTPUTS)-1:0]           fc_bias_rd_addr;
    logic signed [31:0]                      fc_bias_data;

    // TODO: FC ağırlık belleği YZ belleğinden AXI üzerinden yüklenecek
    // Şimdilik sıfır döndüren stub
    assign fc_weight_data = 8'sh0;
    assign fc_bias_data   = 32'sh0;

    /* verilator lint_off PINMISSING */
    input_buffer #(
        .INPUT_SIZE  (INPUT_SIZE),
        .NUM_FILTERS (NUM_FILTERS),
        .KERNEL_H    (KERNEL_H),
        .KERNEL_W    (KERNEL_W)
    ) u_input_buf (
        .clk            (clk),
        .rst_n          (rst_n),
        // Yazma portu — FSM'den (TODO: fsm write output portları eklenince bağlanacak)
        .wr_en          (1'b0),
        .wr_data        (8'h0),
        .wr_addr        (13'h0),
        // Ağırlık okuma
        .weight_rd_addr (ibuf_weight_rd_addr),
        .weight_data    (ibuf_weight_data),
        // Satır tamponu
        .col_idx        (ibuf_col_idx),
        .line_buf_data  (ibuf_line_buf)
    );
    /* verilator lint_on PINMISSING */

    depthwise_conv2d #(
        .NUM_FILTERS (NUM_FILTERS),
        .KERNEL_H    (KERNEL_H),
        .KERNEL_W    (KERNEL_W)
    ) u_dw_conv (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (dw_start),
        .done           (dw_done),
        .col_rd_idx     (ibuf_col_idx),
        .line_buf       (ibuf_line_buf),
        .weight_rd_addr (ibuf_weight_rd_addr),
        .weight_data    (ibuf_weight_data),
        .out_wr_en      (lbuf_wr_en),
        .out_wr_addr    (lbuf_wr_addr),
        .out_wr_data    (lbuf_wr_data)
    );

    local_buffer #(
        .DEPTH      (FC_INPUTS),
        .DATA_WIDTH (8)
    ) u_local_buf (
        .clk     (clk),
        .wr_en   (lbuf_wr_en),
        .wr_addr (lbuf_wr_addr),
        .wr_data (lbuf_wr_data),
        .rd_addr (lbuf_rd_addr),
        .rd_data (lbuf_rd_data)
    );

    fully_connected #(
        .NUM_OUTPUTS (FC_OUTPUTS),
        .NUM_INPUTS  (FC_INPUTS)
    ) u_fc (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (fc_start),
        .done           (fc_done),
        .in_rd_addr     (lbuf_rd_addr),
        .in_data        (lbuf_rd_data),
        .weight_rd_addr (fc_weight_rd_addr),
        .weight_data    (fc_weight_data),
        .bias_rd_addr   (fc_bias_rd_addr),
        .bias_data      (fc_bias_data),
        .logits         (fc_logits),
        .logits_valid   (fc_logits_valid)
    );

    softmax_argmax #(
        .NUM_CLASSES (FC_OUTPUTS)
    ) u_argmax (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (argmax_start),
        .done    (argmax_done),
        .logits  (fc_logits),
        .result  (fsm_result)
    );

    // Kullanılmayan stub sinyaller — implementasyonda bağlanacak
    /* verilator lint_off UNUSED */
    logic _unused = fc_logits_valid | (|fc_weight_rd_addr) | (|fc_bias_rd_addr);
    /* verilator lint_on UNUSED */

endmodule
