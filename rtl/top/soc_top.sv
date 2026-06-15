`timescale 1ns / 1ps
// ==============================================================================
//  soc_top.sv
//  Top-Level SoC Module (Integrating Core Bus Wrapper & Peripherals)
// ==============================================================================

import obi_pkg::*;
import axi_pkg::*;

module soc_top #(
    // AI_MEM onyukleme dosyasi (sim/bring-up). Bos = onyukleme yok
    // (FPGA'da AI_MEM UART1 stream yazma yoluyla doldurulacak — sonraki adim).
    parameter string AIMEM_INIT = ""
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // UART0 (Console)
    output logic        uart0_tx_o,
    input  logic        uart0_rx_i,

    // UART1 (Audio stream to NPU)
    input  logic        uart1_rx_i,

    // GPIO
    input  logic [15:0] gpio_in_i,
    output logic [15:0] gpio_out_o,
    output logic [15:0] gpio_tx_en_o,

    // I2C
    inout  wire         i2c_scl_io,
    inout  wire         i2c_sda_io,

    // QSPI
    output logic        qspi_sck_o,
    output logic        qspi_csn_o,
    inout  wire  [3:0]  qspi_io
);

    // --- INTERCONNECT REQUEST / RESPONSE SIGNALS ---
    axi_req_t rom_req;
    axi_rsp_t rom_rsp;
    axi_req_t uart_stream_req;
    axi_rsp_t uart_stream_rsp;
    axi_req_t uart_ctrl_req;
    axi_rsp_t uart_ctrl_rsp;
    axi_req_t gpio_req;
    axi_rsp_t gpio_rsp;
    axi_req_t timer_req;
    axi_rsp_t timer_rsp;
    axi_req_t i2c_req;
    axi_rsp_t i2c_rsp;
    axi_req_t qspi_req;
    axi_rsp_t qspi_rsp;
    axi_req_t npu_req;
    axi_rsp_t npu_rsp;
    axi_req_t intc_req;
    axi_rsp_t intc_rsp;

    // --- INTERRUPT SIGNALS ---
    logic [31:0] irq_vector;
    logic        npu_irq;
    logic        timer_irq;
    logic        uart_stream_irq;
    logic        uart_peripheral_irq;
    logic        i2c_irq;
    logic        gpio_irq;

    // Aggregate interrupts according to configuration:
    assign irq_vector = {
        24'b0,
        gpio_irq,            // bit 7
        i2c_irq,             // bit 6
        uart_peripheral_irq, // bit 5
        uart_stream_irq,     // bit 4
        timer_irq,           // bit 3
        npu_irq,             // bit 2
        2'b0
    };

    // Ground INTC (Slave 9) responses as it is not used in RTL simulation
    assign intc_rsp = '0;

    // --- 1. BUS WRAPPER (CPU + BRIDGES + INTERCONNECT + SRAM) ---
    axi_wrapper u_bus_wrapper (
        .clk_i                   ( clk_i ),
        .rst_ni                  ( rst_ni ),
        .irq_i                   ( irq_vector ),

        // ROM
        .rom_axi_req_o           ( rom_req ),
        .rom_axi_rsp_i           ( rom_rsp ),

        // UART Stream
        .uart_stream_axi_req_o   ( uart_stream_req ),
        .uart_stream_axi_rsp_i   ( uart_stream_rsp ),

        // UART Control
        .uart_ctrl_axi_req_o     ( uart_ctrl_req ),
        .uart_ctrl_axi_rsp_i     ( uart_ctrl_rsp ),

        // GPIO
        .gpio_axi_req_o          ( gpio_req ),
        .gpio_axi_rsp_i          ( gpio_rsp ),

        // Timer
        .timer_axi_req_o         ( timer_req ),
        .timer_axi_rsp_i         ( timer_rsp ),

        // I2C
        .i2c_axi_req_o           ( i2c_req ),
        .i2c_axi_rsp_i           ( i2c_rsp ),

        // QSPI
        .qspi_axi_req_o          ( qspi_req ),
        .qspi_axi_rsp_i          ( qspi_rsp ),

        // NPU
        .npu_axi_req_o           ( npu_req ),
        .npu_axi_rsp_i           ( npu_rsp ),

        // INTC
        .intc_axi_req_o          ( intc_req ),
        .intc_axi_rsp_i          ( intc_rsp )
    );

    // --- 2. BOOT ROM ---
    boot_rom u_boot_rom (
        .clk            ( clk_i ),
        .rst_n          ( rst_ni ),
        .s_axi_araddr   ( rom_req.ar.addr ),
        .s_axi_arvalid  ( rom_req.ar_valid ),
        .s_axi_arready  ( rom_rsp.ar_ready ),
        .s_axi_rdata    ( rom_rsp.r.rdata ),
        .s_axi_rresp    ( rom_rsp.r.resp ),
        .s_axi_rvalid   ( rom_rsp.r_valid ),
        .s_axi_rready   ( rom_req.r_ready )
    );

    // --- 3. UART STREAM PERIPHERAL (UART1) ---
    uart_stream_peripheral u_uart_stream (
        .clk             ( clk_i ),
        .rst_n           ( rst_ni ),

        .s_axil_awaddr   ( uart_stream_req.aw.addr[7:0] ),
        .s_axil_awvalid  ( uart_stream_req.aw_valid ),
        .s_axil_awready  ( uart_stream_rsp.aw_ready ),
        .s_axil_wdata    ( uart_stream_req.w.data ),
        .s_axil_wstrb    ( uart_stream_req.w.strb ),
        .s_axil_wvalid   ( uart_stream_req.w_valid ),
        .s_axil_wready   ( uart_stream_rsp.w_ready ),
        .s_axil_bresp    ( uart_stream_rsp.b.resp ),
        .s_axil_bvalid   ( uart_stream_rsp.b_valid ),
        .s_axil_bready   ( uart_stream_req.b_ready ),
        .s_axil_araddr   ( uart_stream_req.ar.addr[7:0] ),
        .s_axil_arvalid  ( uart_stream_req.ar_valid ),
        .s_axil_arready  ( uart_stream_rsp.ar_ready ),
        .s_axil_rdata    ( uart_stream_rsp.r.rdata ),
        .s_axil_rresp    ( uart_stream_rsp.r.resp ),
        .s_axil_rvalid   ( uart_stream_rsp.r_valid ),
        .s_axil_rready   ( uart_stream_req.r_ready ),

        .m_axil_awready  ( 1'b0 ),
        .m_axil_wready   ( 1'b0 ),
        .m_axil_bvalid   ( 1'b0 ),

        .uart_rxd        ( uart1_rx_i ),
        .uart_txd        ( ),
        .uart_stream_irq ( uart_stream_irq ),
        .fifo_empty      ( ),
        .fifo_full       ( )
    );

    // --- 4. UART CONTROL PERIPHERAL (UART0) ---
    uart_peripheral u_uart_peripheral (
        .clk             ( clk_i ),
        .rst_n           ( rst_ni ),

        .s_axil_awaddr   ( uart_ctrl_req.aw.addr[7:0] ),
        .s_axil_awvalid  ( uart_ctrl_req.aw_valid ),
        .s_axil_awready  ( uart_ctrl_rsp.aw_ready ),
        .s_axil_wdata    ( uart_ctrl_req.w.data ),
        .s_axil_wstrb    ( uart_ctrl_req.w.strb ),
        .s_axil_wvalid   ( uart_ctrl_req.w_valid ),
        .s_axil_wready   ( uart_ctrl_rsp.w_ready ),
        .s_axil_bresp    ( uart_ctrl_rsp.b.resp ),
        .s_axil_bvalid   ( uart_ctrl_rsp.b_valid ),
        .s_axil_bready   ( uart_ctrl_req.b_ready ),
        .s_axil_araddr   ( uart_ctrl_req.ar.addr[7:0] ),
        .s_axil_arvalid  ( uart_ctrl_req.ar_valid ),
        .s_axil_arready  ( uart_ctrl_rsp.ar_ready ),
        .s_axil_rdata    ( uart_ctrl_rsp.r.rdata ),
        .s_axil_rresp    ( uart_ctrl_rsp.r.resp ),
        .s_axil_rvalid   ( uart_ctrl_rsp.r_valid ),
        .s_axil_rready   ( uart_ctrl_req.r_ready ),

        .uart_txd        ( uart0_tx_o ),
        .uart_rxd        ( uart0_rx_i ),
        .uart_stream_irq ( uart_peripheral_irq )
    );

    // --- 5. GPIO PERIPHERAL ---
    gpio_peripheral #(
        .AXI_ADDR_W      ( 8 ),
        .AXI_DATA_W      ( 32 )
    ) u_gpio (
        .clk             ( clk_i ),
        .rst_n           ( rst_ni ),

        .gpio_i          ( gpio_in_i ),
        .gpio_o          ( gpio_out_o ),
        .gpio_tx_en_o    ( gpio_tx_en_o ),
        .global_interrupt_o ( gpio_irq ),

        .s_axil_awaddr   ( gpio_req.aw.addr[7:0] ),
        .s_axil_awvalid  ( gpio_req.aw_valid ),
        .s_axil_awready  ( gpio_rsp.aw_ready ),
        .s_axil_wdata    ( gpio_req.w.data ),
        .s_axil_wstrb    ( gpio_req.w.strb ),
        .s_axil_wvalid   ( gpio_req.w_valid ),
        .s_axil_wready   ( gpio_rsp.w_ready ),
        .s_axil_bresp    ( gpio_rsp.b.resp ),
        .s_axil_bvalid   ( gpio_rsp.b_valid ),
        .s_axil_bready   ( gpio_req.b_ready ),
        .s_axil_araddr   ( gpio_req.ar.addr[7:0] ),
        .s_axil_arvalid  ( gpio_req.ar_valid ),
        .s_axil_arready  ( gpio_rsp.ar_ready ),
        .s_axil_rdata    ( gpio_rsp.r.rdata ),
        .s_axil_rresp    ( gpio_rsp.r.resp ),
        .s_axil_rvalid   ( gpio_rsp.r_valid ),
        .s_axil_rready   ( gpio_req.r_ready )
    );

    // --- 6. TIMER PERIPHERAL ---
    timer_peripheral #(
        .S_AXI_ADDR_WIDTH( 12 ),
        .S_AXI_DATA_WIDTH( 32 )
    ) u_timer (
        .s_axi_aclk      ( clk_i ),
        .s_axi_aresetn   ( rst_ni ),

        .s_axi_awaddr    ( timer_req.aw.addr[11:0] ),
        .s_axi_awprot    ( 3'b0 ),
        .s_axi_awvalid   ( timer_req.aw_valid ),
        .s_axi_awready   ( timer_rsp.aw_ready ),
        .s_axi_wdata     ( timer_req.w.data ),
        .s_axi_wstrb     ( timer_req.w.strb ),
        .s_axi_wvalid    ( timer_req.w_valid ),
        .s_axi_wready    ( timer_rsp.w_ready ),
        .s_axi_bresp     ( timer_rsp.b.resp ),
        .s_axi_bvalid    ( timer_rsp.b_valid ),
        .s_axi_bready    ( timer_req.b_ready ),
        .s_axi_araddr    ( timer_req.ar.addr[11:0] ),
        .s_axi_arprot    ( 3'b0 ),
        .s_axi_arvalid   ( timer_req.ar_valid ),
        .s_axi_arready   ( timer_rsp.ar_ready ),
        .s_axi_rdata     ( timer_rsp.r.rdata ),
        .s_axi_rresp     ( timer_rsp.r.resp ),
        .s_axi_rvalid    ( timer_rsp.r_valid ),
        .s_axi_rready    ( timer_req.r_ready ),

        .timer_irq       ( timer_irq )
    );

    // --- 7. I2C PERIPHERAL ---
    i2c_peripheral #(
        .SYS_CLK_FREQ    ( 50_000_000 ),
        .I2C_FREQ        ( 400_000 )
    ) u_i2c (
        .clk             ( clk_i ),
        .rst_n           ( rst_ni ),

        .s_axi_awaddr    ( i2c_req.aw.addr[7:0] ),
        .s_axi_awprot    ( 3'b0 ),
        .s_axi_awvalid   ( i2c_req.aw_valid ),
        .s_axi_awready   ( i2c_rsp.aw_ready ),
        .s_axi_wdata     ( i2c_req.w.data ),
        .s_axi_wstrb     ( i2c_req.w.strb ),
        .s_axi_wvalid    ( i2c_req.w_valid ),
        .s_axi_wready    ( i2c_rsp.w_ready ),
        .s_axi_bresp     ( i2c_rsp.b.resp ),
        .s_axi_bvalid    ( i2c_rsp.b_valid ),
        .s_axi_bready    ( i2c_req.b_ready ),
        .s_axi_araddr    ( i2c_req.ar.addr[7:0] ),
        .s_axi_arprot    ( 3'b0 ),
        .s_axi_arvalid   ( i2c_req.ar_valid ),
        .s_axi_arready   ( i2c_rsp.ar_ready ),
        .s_axi_rdata     ( i2c_rsp.r.rdata ),
        .s_axi_rresp     ( i2c_rsp.r.resp ),
        .s_axi_rvalid    ( i2c_rsp.r_valid ),
        .s_axi_rready    ( i2c_req.r_ready ),

        .i2c_irq         ( i2c_irq ),
        .sda             ( i2c_sda_io ),
        .scl             ( i2c_scl_io )
    );

    // --- 8. QSPI PERIPHERAL (Demultiplexed for Dual-AXI slave ports) ---
    logic        qspi_sel_intr;
    assign qspi_sel_intr = qspi_req.ar_valid ? qspi_req.ar.addr[16] : qspi_req.aw.addr[16];

    logic        s00_awvalid, s00_wvalid, s00_arvalid;
    logic        intr_awvalid, intr_wvalid, intr_arvalid;

    assign s00_awvalid  = qspi_req.aw_valid && !qspi_sel_intr;
    assign s00_wvalid   = qspi_req.w_valid  && !qspi_sel_intr;
    assign s00_arvalid  = qspi_req.ar_valid && !qspi_sel_intr;

    assign intr_awvalid = qspi_req.aw_valid && qspi_sel_intr;
    assign intr_wvalid  = qspi_req.w_valid  && qspi_sel_intr;
    assign intr_arvalid = qspi_req.ar_valid && qspi_sel_intr;

    logic        qspi_awready_s00, qspi_wready_s00, qspi_bvalid_s00, qspi_arready_s00, qspi_rvalid_s00;
    logic [1:0]  qspi_bresp_s00, qspi_rresp_s00;
    logic [31:0] qspi_rdata_s00;

    logic        qspi_awready_intr, qspi_wready_intr, qspi_bvalid_intr, qspi_arready_intr, qspi_rvalid_intr;
    logic [1:0]  qspi_bresp_intr, qspi_rresp_intr;
    logic [31:0] qspi_rdata_intr;

    always_comb begin
        qspi_rsp = '0;
        if (qspi_sel_intr) begin
            qspi_rsp.aw_ready = qspi_awready_intr;
            qspi_rsp.w_ready  = qspi_wready_intr;
            qspi_rsp.b_valid  = qspi_bvalid_intr;
            qspi_rsp.b.resp   = qspi_bresp_intr;
            qspi_rsp.ar_ready = qspi_arready_intr;
            qspi_rsp.r_valid  = qspi_rvalid_intr;
            qspi_rsp.r.rdata  = qspi_rdata_intr;
            qspi_rsp.r.resp   = qspi_rresp_intr;
        end else begin
            qspi_rsp.aw_ready = qspi_awready_s00;
            qspi_rsp.w_ready  = qspi_wready_s00;
            qspi_rsp.b_valid  = qspi_bvalid_s00;
            qspi_rsp.b.resp   = qspi_bresp_s00;
            qspi_rsp.ar_ready = qspi_arready_s00;
            qspi_rsp.r_valid  = qspi_rvalid_s00;
            qspi_rsp.r.rdata  = qspi_rdata_s00;
            qspi_rsp.r.resp   = qspi_rresp_s00;
        end
    end

    axi_qspi_T_v1_0 u_qspi (
        .SCLK_pad             ( qspi_sck_o ),
        .CS_pad               ( qspi_csn_o ),
        .dq_pad               ( qspi_io ),

        // s00 AXI-Lite
        .s00_axi_aclk         ( clk_i ),
        .s00_axi_aresetn      ( rst_ni ),
        .s00_axi_awaddr       ( qspi_req.aw.addr[3:0] ),
        .s00_axi_awprot       ( 3'b0 ),
        .s00_axi_awvalid      ( s00_awvalid ),
        .s00_axi_awready      ( qspi_awready_s00 ),
        .s00_axi_wdata        ( qspi_req.w.data ),
        .s00_axi_wstrb        ( qspi_req.w.strb ),
        .s00_axi_wvalid       ( s00_wvalid ),
        .s00_axi_wready       ( qspi_wready_s00 ),
        .s00_axi_bresp        ( qspi_bresp_s00 ),
        .s00_axi_bvalid       ( qspi_bvalid_s00 ),
        .s00_axi_bready       ( qspi_req.b_ready ),
        .s00_axi_araddr       ( qspi_req.ar.addr[3:0] ),
        .s00_axi_arprot       ( 3'b0 ),
        .s00_axi_arvalid      ( s00_arvalid ),
        .s00_axi_arready      ( qspi_arready_s00 ),
        .s00_axi_rdata        ( qspi_rdata_s00 ),
        .s00_axi_rresp        ( qspi_rresp_s00 ),
        .s00_axi_rvalid       ( qspi_rvalid_s00 ),
        .s00_axi_rready       ( qspi_req.r_ready ),

        // s_axi_intr AXI-Lite
        .s_axi_intr_aclk      ( clk_i ),
        .s_axi_intr_aresetn   ( rst_ni ),
        .s_axi_intr_awaddr    ( qspi_req.aw.addr[4:0] ),
        .s_axi_intr_awprot    ( 3'b0 ),
        .s_axi_intr_awvalid   ( intr_awvalid ),
        .s_axi_intr_awready   ( qspi_awready_intr ),
        .s_axi_intr_wdata     ( qspi_req.w.data ),
        .s_axi_intr_wstrb     ( qspi_req.w.strb ),
        .s_axi_intr_wvalid    ( intr_wvalid ),
        .s_axi_intr_wready    ( qspi_wready_intr ),
        .s_axi_intr_bresp     ( qspi_bresp_intr ),
        .s_axi_intr_bvalid    ( qspi_bvalid_intr ),
        .s_axi_intr_bready    ( qspi_req.b_ready ),
        .s_axi_intr_araddr    ( qspi_req.ar.addr[4:0] ),
        .s_axi_intr_arprot    ( 3'b0 ),
        .s_axi_intr_arvalid   ( intr_arvalid ),
        .s_axi_intr_arready   ( qspi_arready_intr ),
        .s_axi_intr_rdata     ( qspi_rdata_intr ),
        .s_axi_intr_rresp     ( qspi_rresp_intr ),
        .s_axi_intr_rvalid    ( qspi_rvalid_intr ),
        .s_axi_intr_rready    ( qspi_req.r_ready ),

        .irq                  ( )
    );

    // --- NPU AXI4 master <-> AI_MEM (point-to-point, alt-sistem deseni) ---
    logic [3:0]  npu_m_awid;   logic [31:0] npu_m_awaddr;  logic [7:0] npu_m_awlen;
    logic [2:0]  npu_m_awsize;  logic [1:0]  npu_m_awburst; logic npu_m_awvalid, npu_m_awready;
    logic [31:0] npu_m_wdata;   logic [3:0]  npu_m_wstrb;   logic npu_m_wlast, npu_m_wvalid, npu_m_wready;
    logic [3:0]  npu_m_bid;     logic [1:0]  npu_m_bresp;   logic npu_m_bvalid, npu_m_bready;
    logic [3:0]  npu_m_arid;   logic [31:0] npu_m_araddr;  logic [7:0] npu_m_arlen;
    logic [2:0]  npu_m_arsize;  logic [1:0]  npu_m_arburst; logic npu_m_arvalid, npu_m_arready;
    logic [3:0]  npu_m_rid;     logic [31:0] npu_m_rdata;   logic [1:0] npu_m_rresp;
    logic        npu_m_rlast, npu_m_rvalid, npu_m_rready;

    // --- 9. NPU PERIPHERAL ---
    npu_top u_npu (
        .clk                  ( clk_i ),
        .rst_n                ( rst_ni ),

        .s_axil_awaddr        ( npu_req.aw.addr[7:0] ),
        .s_axil_awvalid       ( npu_req.aw_valid ),
        .s_axil_awready       ( npu_rsp.aw_ready ),
        .s_axil_wdata         ( npu_req.w.data ),
        .s_axil_wstrb         ( npu_req.w.strb ),
        .s_axil_wvalid        ( npu_req.w_valid ),
        .s_axil_wready        ( npu_rsp.w_ready ),
        .s_axil_bresp         ( npu_rsp.b.resp ),
        .s_axil_bvalid        ( npu_rsp.b_valid ),
        .s_axil_bready        ( npu_req.b_ready ),
        .s_axil_araddr        ( npu_req.ar.addr[7:0] ),
        .s_axil_arvalid       ( npu_req.ar_valid ),
        .s_axil_arready       ( npu_rsp.ar_ready ),
        .s_axil_rdata         ( npu_rsp.r.rdata ),
        .s_axil_rresp         ( npu_rsp.r.resp ),
        .s_axil_rvalid        ( npu_rsp.r_valid ),
        .s_axil_rready        ( npu_req.r_ready ),

        // NPU AXI4 master -> AI_MEM (agirlik blob + giris okumasi)
        .m_axi_awid           ( npu_m_awid ),
        .m_axi_awaddr         ( npu_m_awaddr ),
        .m_axi_awlen          ( npu_m_awlen ),
        .m_axi_awsize         ( npu_m_awsize ),
        .m_axi_awburst        ( npu_m_awburst ),
        .m_axi_awvalid        ( npu_m_awvalid ),
        .m_axi_awready        ( npu_m_awready ),
        .m_axi_wdata          ( npu_m_wdata ),
        .m_axi_wstrb          ( npu_m_wstrb ),
        .m_axi_wlast          ( npu_m_wlast ),
        .m_axi_wvalid         ( npu_m_wvalid ),
        .m_axi_wready         ( npu_m_wready ),
        .m_axi_bid            ( npu_m_bid ),
        .m_axi_bresp          ( npu_m_bresp ),
        .m_axi_bvalid         ( npu_m_bvalid ),
        .m_axi_bready         ( npu_m_bready ),
        .m_axi_arid           ( npu_m_arid ),
        .m_axi_araddr         ( npu_m_araddr ),
        .m_axi_arlen          ( npu_m_arlen ),
        .m_axi_arsize         ( npu_m_arsize ),
        .m_axi_arburst        ( npu_m_arburst ),
        .m_axi_arvalid        ( npu_m_arvalid ),
        .m_axi_arready        ( npu_m_arready ),
        .m_axi_rid            ( npu_m_rid ),
        .m_axi_rdata          ( npu_m_rdata ),
        .m_axi_rresp          ( npu_m_rresp ),
        .m_axi_rlast          ( npu_m_rlast ),
        .m_axi_rvalid         ( npu_m_rvalid ),
        .m_axi_rready         ( npu_m_rready ),

        .npu_irq              ( npu_irq )
    );

    // --- AI_MEM: NPU master'in okudugu agirlik+giris bellegi (30 KB) ---
    // Point-to-point (salt-okunur). AIMEM_INIT ile onyuklenir; FPGA'da
    // UART1 stream yazma yolu eklenince bus'a tasinabilir (master portu hazir).
    ai_mem #(
        .ADDR_WIDTH (32), .DATA_WIDTH (32), .ID_WIDTH (4),
        .BASE_ADDR  (32'h0001_0000), .SIZE_BYTES (30720), .INIT_FILE (AIMEM_INIT)
    ) u_ai_mem (
        .clk          ( clk_i ),
        .rst_n        ( rst_ni ),
        .s_axi_arid   ( npu_m_arid ),
        .s_axi_araddr ( npu_m_araddr ),
        .s_axi_arlen  ( npu_m_arlen ),
        .s_axi_arsize ( npu_m_arsize ),
        .s_axi_arburst( npu_m_arburst ),
        .s_axi_arvalid( npu_m_arvalid ),
        .s_axi_arready( npu_m_arready ),
        .s_axi_rid    ( npu_m_rid ),
        .s_axi_rdata  ( npu_m_rdata ),
        .s_axi_rresp  ( npu_m_rresp ),
        .s_axi_rlast  ( npu_m_rlast ),
        .s_axi_rvalid ( npu_m_rvalid ),
        .s_axi_rready ( npu_m_rready ),
        .s_axi_awid   ( npu_m_awid ),
        .s_axi_awaddr ( npu_m_awaddr ),
        .s_axi_awlen  ( npu_m_awlen ),
        .s_axi_awsize ( npu_m_awsize ),
        .s_axi_awburst( npu_m_awburst ),
        .s_axi_awvalid( npu_m_awvalid ),
        .s_axi_awready( npu_m_awready ),
        .s_axi_wdata  ( npu_m_wdata ),
        .s_axi_wstrb  ( npu_m_wstrb ),
        .s_axi_wlast  ( npu_m_wlast ),
        .s_axi_wvalid ( npu_m_wvalid ),
        .s_axi_wready ( npu_m_wready ),
        .s_axi_bid    ( npu_m_bid ),
        .s_axi_bresp  ( npu_m_bresp ),
        .s_axi_bvalid ( npu_m_bvalid ),
        .s_axi_bready ( npu_m_bready )
    );

endmodule
