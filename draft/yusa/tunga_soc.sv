// ============================================================
// Module : tunga_soc
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Yuşa Eren Karaca
// Date   : 2026-05-XX
// Desc   : TUNGA SoC üst modülü — tüm IP bloklarını bağlar.
//          CV32E40P çekirdeği OBI-AXI köprüsü üzerinden AXI Interconnect'e,
//          Interconnect tüm slave'lere bağlanır.
// ============================================================

`timescale 1ns/1ps

module tunga_soc (
    input  logic clk,
    input  logic rst_n,

    // ---- GPIO ----
    input  logic [15:0] gpio_in,
    output logic [15:0] gpio_out,

    // ---- UART0 (genel) ----
    output logic uart0_tx,
    input  logic uart0_rx,

    // ---- UART1 (stream → NPU) ----
    input  logic uart1_rx,

    // ---- QSPI (NOR Flash) ----
    output logic       qspi_sck,
    output logic       qspi_csn,
    inout  wire  [3:0] qspi_io,

    // ---- I2C ----
    inout wire i2c_scl,
    inout wire i2c_sda
);

    // ================================================================
    // Sistem parametreleri
    // ================================================================
    localparam int AXI_ADDR_W  = 32;
    localparam int AXI_DATA_W  = 32;
    localparam int AXI_ID_W    = 4;
    localparam int NUM_MASTERS = 5;   // INSTR_BR, DATA_BR, NPU, UART1, DMA
    localparam int NUM_SLAVES  = 11;  // BootROM, IMEM, DMEM, AIMEM, GPIO,
                                      // Timer, UART0, UART1cfg, QSPI, I2C, NPUCSR

    // ================================================================
    // İç sinyaller — AXI Master (köprüden Interconnect'e)
    // Indeks: 0=INSTR, 1=DATA, 2=NPU, 3=UART1, 4=DMA(rezerv)
    // ================================================================
    logic [AXI_ID_W-1:0]   m_axi_awid    [0:NUM_MASTERS-1];
    logic [AXI_ADDR_W-1:0] m_axi_awaddr  [0:NUM_MASTERS-1];
    logic [7:0]            m_axi_awlen   [0:NUM_MASTERS-1];
    logic [2:0]            m_axi_awsize  [0:NUM_MASTERS-1];
    logic [1:0]            m_axi_awburst [0:NUM_MASTERS-1];
    logic                  m_axi_awvalid [0:NUM_MASTERS-1];
    logic                  m_axi_awready [0:NUM_MASTERS-1];
    logic [AXI_DATA_W-1:0] m_axi_wdata   [0:NUM_MASTERS-1];
    logic [3:0]            m_axi_wstrb   [0:NUM_MASTERS-1];
    logic                  m_axi_wlast   [0:NUM_MASTERS-1];
    logic                  m_axi_wvalid  [0:NUM_MASTERS-1];
    logic                  m_axi_wready  [0:NUM_MASTERS-1];
    logic [AXI_ID_W-1:0]   m_axi_bid     [0:NUM_MASTERS-1];
    logic [1:0]            m_axi_bresp   [0:NUM_MASTERS-1];
    logic                  m_axi_bvalid  [0:NUM_MASTERS-1];
    logic                  m_axi_bready  [0:NUM_MASTERS-1];
    logic [AXI_ID_W-1:0]   m_axi_arid    [0:NUM_MASTERS-1];
    logic [AXI_ADDR_W-1:0] m_axi_araddr  [0:NUM_MASTERS-1];
    logic [7:0]            m_axi_arlen   [0:NUM_MASTERS-1];
    logic [2:0]            m_axi_arsize  [0:NUM_MASTERS-1];
    logic [1:0]            m_axi_arburst [0:NUM_MASTERS-1];
    logic                  m_axi_arvalid [0:NUM_MASTERS-1];
    logic                  m_axi_arready [0:NUM_MASTERS-1];
    logic [AXI_ID_W-1:0]   m_axi_rid     [0:NUM_MASTERS-1];
    logic [AXI_DATA_W-1:0] m_axi_rdata   [0:NUM_MASTERS-1];
    logic [1:0]            m_axi_rresp   [0:NUM_MASTERS-1];
    logic                  m_axi_rlast   [0:NUM_MASTERS-1];
    logic                  m_axi_rvalid  [0:NUM_MASTERS-1];
    logic                  m_axi_rready  [0:NUM_MASTERS-1];

    // ================================================================
    // İç sinyaller — AXI Slave (Interconnect'ten IP'lere)
    // Indeks: 0=BootROM, 1=IMEM, 2=DMEM, 3=AIMEM, 4=GPIO,
    //         5=Timer, 6=UART0, 7=UART1cfg, 8=QSPI, 9=I2C, 10=NPUCSR
    // ================================================================
    logic [AXI_ID_W-1:0]   s_axi_awid    [0:NUM_SLAVES-1];
    logic [AXI_ADDR_W-1:0] s_axi_awaddr  [0:NUM_SLAVES-1];
    logic [7:0]            s_axi_awlen   [0:NUM_SLAVES-1];
    logic [2:0]            s_axi_awsize  [0:NUM_SLAVES-1];
    logic [1:0]            s_axi_awburst [0:NUM_SLAVES-1];
    logic                  s_axi_awvalid [0:NUM_SLAVES-1];
    logic                  s_axi_awready [0:NUM_SLAVES-1];
    logic [AXI_DATA_W-1:0] s_axi_wdata   [0:NUM_SLAVES-1];
    logic [3:0]            s_axi_wstrb   [0:NUM_SLAVES-1];
    logic                  s_axi_wlast   [0:NUM_SLAVES-1];
    logic                  s_axi_wvalid  [0:NUM_SLAVES-1];
    logic                  s_axi_wready  [0:NUM_SLAVES-1];
    logic [AXI_ID_W-1:0]   s_axi_bid     [0:NUM_SLAVES-1];
    logic [1:0]            s_axi_bresp   [0:NUM_SLAVES-1];
    logic                  s_axi_bvalid  [0:NUM_SLAVES-1];
    logic                  s_axi_bready  [0:NUM_SLAVES-1];
    logic [AXI_ID_W-1:0]   s_axi_arid    [0:NUM_SLAVES-1];
    logic [AXI_ADDR_W-1:0] s_axi_araddr  [0:NUM_SLAVES-1];
    logic [7:0]            s_axi_arlen   [0:NUM_SLAVES-1];
    logic [2:0]            s_axi_arsize  [0:NUM_SLAVES-1];
    logic [1:0]            s_axi_arburst [0:NUM_SLAVES-1];
    logic                  s_axi_arvalid [0:NUM_SLAVES-1];
    logic                  s_axi_arready [0:NUM_SLAVES-1];
    logic [AXI_ID_W-1:0]   s_axi_rid     [0:NUM_SLAVES-1];
    logic [AXI_DATA_W-1:0] s_axi_rdata   [0:NUM_SLAVES-1];
    logic [1:0]            s_axi_rresp   [0:NUM_SLAVES-1];
    logic                  s_axi_rlast   [0:NUM_SLAVES-1];
    logic                  s_axi_rvalid  [0:NUM_SLAVES-1];
    logic                  s_axi_rready  [0:NUM_SLAVES-1];

    // ================================================================
    // CV32E40P OBI portları
    // ================================================================
    // Buyruk OBI
    logic        instr_req;
    logic        instr_gnt;
    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;
    logic        instr_rvalid;

    // Veri OBI
    logic        data_req;
    logic        data_gnt;
    logic [31:0] data_addr;
    logic        data_we;
    logic [3:0]  data_be;
    logic [31:0] data_wdata;
    logic [31:0] data_rdata;
    logic        data_rvalid;
    logic        data_err;

    // Kesme sinyalleri
    logic npu_irq;
    logic timer_irq;
    logic uart0_irq;
    logic uart1_irq;
    logic [31:0] irq_lines;

    // IRQ toplayıcı — CV32E40P irq_i portuna bağlanır
    assign irq_lines = {24'h0, uart1_irq, uart0_irq, timer_irq, 4'h0, npu_irq, 1'b0};

    // ================================================================
    // TODO: Modül instantiationları
    //
    // 1. cv32e40p_core — rtl/core/cv32e40p klasöründen
    //    .clk_i(clk), .rst_ni(rst_n)
    //    .instr_req_o, .instr_gnt_i, .instr_addr_o, .instr_rdata_i, .instr_rvalid_i
    //    .data_req_o, .data_gnt_i, .data_addr_o, .data_we_o, .data_be_o,
    //    .data_wdata_o, .data_rdata_i, .data_rvalid_i, .data_err_i
    //    .irq_i(irq_lines)
    //
    // 2. obi_axi_bridge × 2 (buyruk + veri) → m_axi[0] ve m_axi[1]
    //
    // 3. axi_interconnect → m_axi[0..4] girişleri, s_axi[0..10] çıkışları
    //
    // 4. boot_rom        → s_axi[0]
    // 5. IMEM (SRAM ctrl)→ s_axi[1]   (ileride memory controller yazılacak)
    // 6. DMEM (SRAM ctrl)→ s_axi[2]
    // 7. AI_MEM ctrl     → s_axi[3]
    // 8. gpio            → s_axi[4]
    // 9. timer           → s_axi[5]
    // 10.uart0           → s_axi[6]
    // 11.uart1_stream    → s_axi[7] (cfg), m_axi[3] (AI_MEM yazma)
    // 12.qspi_master     → s_axi[8]
    // 13.i2c_master      → s_axi[9]
    // 14.npu_top         → s_axi[10] (CSR), m_axi[2] (AI_MEM okuma)
    // ================================================================

    // Stub çıkışlar
    assign uart0_tx = 1'b1;
    assign qspi_sck = 1'b0;
    assign qspi_csn = 1'b1;

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (|gpio_in) | uart0_rx | uart1_rx | (|qspi_io)
                  | i2c_scl | i2c_sda
                  | instr_req | instr_gnt | (|instr_addr) | (|instr_rdata) | instr_rvalid
                  | data_req | data_gnt | (|data_addr) | data_we | (|data_be)
                  | (|data_wdata) | (|data_rdata) | data_rvalid | data_err
                  | npu_irq | timer_irq | uart0_irq | uart1_irq
                  | m_axi_awready[0] | s_axi_awvalid[0];
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
