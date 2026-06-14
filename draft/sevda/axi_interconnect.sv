// ============================================================
// Module : axi_interconnect
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Sevda Oğraş
// Date   : 2026-05-XX
// Desc   : AXI4 Interconnect — adres çözümleyici + multiplexer.
//          Master'lardan gelen istekleri adrese göre Slave'lere yönlendirir.
//
//          MASTER'LAR (5 adet):
//            0: CV32E40P Buyruk OBI-AXI köprüsü (read-only)
//            1: CV32E40P Veri OBI-AXI köprüsü
//            2: NPU AXI4 master
//            3: UART1 stream AXI4 master
//            4: DMA (ilerisi için rezerv)
//
//          SLAVE'LER ve adres haritası:
//            0: Boot ROM     0x0000_0000 – 0x0000_03FF  (1  KB)
//            1: IMEM         0x0000_1000 – 0x0000_2FFF  (8  KB)
//            2: DMEM         0x0000_3000 – 0x0000_4FFF  (8  KB)
//            3: AI MEM       0x0001_0000 – 0x0001_7FFF  (30 KB)
//            4: GPIO         0x2000_0000 – 0x2000_0FFF
//            5: Timer        0x2000_1000 – 0x2000_1FFF
//            6: UART0        0x2000_2000 – 0x2000_2FFF
//            7: UART1 (cfg)  0x2000_3000 – 0x2000_3FFF
//            8: QSPI         0x2000_4000 – 0x2000_4FFF
//            9: I2C          0x2000_5000 – 0x2000_5FFF
//           10: NPU CSR      0x2000_6000 – 0x2000_6FFF
// ============================================================

`timescale 1ns/1ps

module axi_interconnect #(
    parameter int NUM_MASTERS  = 5,
    parameter int NUM_SLAVES   = 11,
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int ID_WIDTH     = 4
) (
    input  logic clk,
    input  logic rst_n,

    // ======================================================
    // AXI4 SLAVE portları — Master cihazlar buraya bağlanır
    // Indeks: 0=INSTR_BRIDGE, 1=DATA_BRIDGE, 2=NPU, 3=UART1, 4=DMA
    // ======================================================
    input  logic [ID_WIDTH-1:0]   s_axi_awid    [0:NUM_MASTERS-1],
    input  logic [ADDR_WIDTH-1:0] s_axi_awaddr  [0:NUM_MASTERS-1],
    input  logic [7:0]            s_axi_awlen   [0:NUM_MASTERS-1],
    input  logic [2:0]            s_axi_awsize  [0:NUM_MASTERS-1],
    input  logic [1:0]            s_axi_awburst [0:NUM_MASTERS-1],
    input  logic                  s_axi_awvalid [0:NUM_MASTERS-1],
    output logic                  s_axi_awready [0:NUM_MASTERS-1],
    input  logic [DATA_WIDTH-1:0] s_axi_wdata   [0:NUM_MASTERS-1],
    input  logic [3:0]            s_axi_wstrb   [0:NUM_MASTERS-1],
    input  logic                  s_axi_wlast   [0:NUM_MASTERS-1],
    input  logic                  s_axi_wvalid  [0:NUM_MASTERS-1],
    output logic                  s_axi_wready  [0:NUM_MASTERS-1],
    output logic [ID_WIDTH-1:0]   s_axi_bid     [0:NUM_MASTERS-1],
    output logic [1:0]            s_axi_bresp   [0:NUM_MASTERS-1],
    output logic                  s_axi_bvalid  [0:NUM_MASTERS-1],
    input  logic                  s_axi_bready  [0:NUM_MASTERS-1],
    input  logic [ID_WIDTH-1:0]   s_axi_arid    [0:NUM_MASTERS-1],
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr  [0:NUM_MASTERS-1],
    input  logic [7:0]            s_axi_arlen   [0:NUM_MASTERS-1],
    input  logic [2:0]            s_axi_arsize  [0:NUM_MASTERS-1],
    input  logic [1:0]            s_axi_arburst [0:NUM_MASTERS-1],
    input  logic                  s_axi_arvalid [0:NUM_MASTERS-1],
    output logic                  s_axi_arready [0:NUM_MASTERS-1],
    output logic [ID_WIDTH-1:0]   s_axi_rid     [0:NUM_MASTERS-1],
    output logic [DATA_WIDTH-1:0] s_axi_rdata   [0:NUM_MASTERS-1],
    output logic [1:0]            s_axi_rresp   [0:NUM_MASTERS-1],
    output logic                  s_axi_rlast   [0:NUM_MASTERS-1],
    output logic                  s_axi_rvalid  [0:NUM_MASTERS-1],
    input  logic                  s_axi_rready  [0:NUM_MASTERS-1],

    // ======================================================
    // AXI4 MASTER portları — Slave cihazlar buraya bağlanır
    // Indeks: 0=BootROM, 1=IMEM, 2=DMEM, 3=AIMEM, 4=GPIO,
    //         5=Timer, 6=UART0, 7=UART1cfg, 8=QSPI, 9=I2C, 10=NPUCSR
    // ======================================================
    output logic [ID_WIDTH-1:0]   m_axi_awid    [0:NUM_SLAVES-1],
    output logic [ADDR_WIDTH-1:0] m_axi_awaddr  [0:NUM_SLAVES-1],
    output logic [7:0]            m_axi_awlen   [0:NUM_SLAVES-1],
    output logic [2:0]            m_axi_awsize  [0:NUM_SLAVES-1],
    output logic [1:0]            m_axi_awburst [0:NUM_SLAVES-1],
    output logic                  m_axi_awvalid [0:NUM_SLAVES-1],
    input  logic                  m_axi_awready [0:NUM_SLAVES-1],
    output logic [DATA_WIDTH-1:0] m_axi_wdata   [0:NUM_SLAVES-1],
    output logic [3:0]            m_axi_wstrb   [0:NUM_SLAVES-1],
    output logic                  m_axi_wlast   [0:NUM_SLAVES-1],
    output logic                  m_axi_wvalid  [0:NUM_SLAVES-1],
    input  logic                  m_axi_wready  [0:NUM_SLAVES-1],
    input  logic [ID_WIDTH-1:0]   m_axi_bid     [0:NUM_SLAVES-1],
    input  logic [1:0]            m_axi_bresp   [0:NUM_SLAVES-1],
    input  logic                  m_axi_bvalid  [0:NUM_SLAVES-1],
    output logic                  m_axi_bready  [0:NUM_SLAVES-1],
    output logic [ID_WIDTH-1:0]   m_axi_arid    [0:NUM_SLAVES-1],
    output logic [ADDR_WIDTH-1:0] m_axi_araddr  [0:NUM_SLAVES-1],
    output logic [7:0]            m_axi_arlen   [0:NUM_SLAVES-1],
    output logic [2:0]            m_axi_arsize  [0:NUM_SLAVES-1],
    output logic [1:0]            m_axi_arburst [0:NUM_SLAVES-1],
    output logic                  m_axi_arvalid [0:NUM_SLAVES-1],
    input  logic                  m_axi_arready [0:NUM_SLAVES-1],
    input  logic [ID_WIDTH-1:0]   m_axi_rid     [0:NUM_SLAVES-1],
    input  logic [DATA_WIDTH-1:0] m_axi_rdata   [0:NUM_SLAVES-1],
    input  logic [1:0]            m_axi_rresp   [0:NUM_SLAVES-1],
    input  logic                  m_axi_rlast   [0:NUM_SLAVES-1],
    input  logic                  m_axi_rvalid  [0:NUM_SLAVES-1],
    output logic                  m_axi_rready  [0:NUM_SLAVES-1]
);

    // ---- Adres haritası sabitleri ----
    localparam logic [ADDR_WIDTH-1:0] BOOT_ROM_BASE  = 32'h0000_0000;
    localparam logic [ADDR_WIDTH-1:0] BOOT_ROM_END   = 32'h0000_03FF;
    localparam logic [ADDR_WIDTH-1:0] IMEM_BASE       = 32'h0000_1000;
    localparam logic [ADDR_WIDTH-1:0] IMEM_END        = 32'h0000_2FFF;
    localparam logic [ADDR_WIDTH-1:0] DMEM_BASE       = 32'h0000_3000;
    localparam logic [ADDR_WIDTH-1:0] DMEM_END        = 32'h0000_4FFF;
    localparam logic [ADDR_WIDTH-1:0] AI_MEM_BASE     = 32'h0001_0000;
    localparam logic [ADDR_WIDTH-1:0] AI_MEM_END      = 32'h0001_7FFF;
    localparam logic [ADDR_WIDTH-1:0] GPIO_BASE        = 32'h2000_0000;
    localparam logic [ADDR_WIDTH-1:0] TIMER_BASE       = 32'h2000_1000;
    localparam logic [ADDR_WIDTH-1:0] UART0_BASE       = 32'h2000_2000;
    localparam logic [ADDR_WIDTH-1:0] UART1_BASE       = 32'h2000_3000;
    localparam logic [ADDR_WIDTH-1:0] QSPI_BASE        = 32'h2000_4000;
    localparam logic [ADDR_WIDTH-1:0] I2C_BASE         = 32'h2000_5000;
    localparam logic [ADDR_WIDTH-1:0] NPU_CSR_BASE     = 32'h2000_6000;
    localparam logic [ADDR_WIDTH-1:0] PERIPH_END_MASK  = 32'h0000_0FFF; // 4 KB her çevre birimi

    // ================================================================
    // TODO: Adres çözümleyici (decode) fonksiyonu — her master için
    //
    // Yaklaşım: Round-robin arbiter + adres decoder + mux
    //
    // 1. Adres decode: gelen ARADDR/AWADDR hangi slave'e ait?
    //    function automatic logic [3:0] decode_addr(input [31:0] addr);
    //
    // 2. Arbiter: aynı slave'e birden fazla master isterse sırayla ver
    //    (Round-robin önerilen)
    //
    // 3. Mux: seçilen master'ın sinyallerini slave'e bağla
    //
    // NOT: Basit implementasyon için tek master/single-port mux yeterli.
    //      Çakışan erişimler için arbiter şart.
    // ================================================================

    // Stub — tüm portları varsayılan değere bağla
    genvar m;
    generate
        for (m = 0; m < NUM_MASTERS; m++) begin : gen_master_stub
            assign s_axi_awready[m] = 1'b0;
            assign s_axi_wready[m]  = 1'b0;
            assign s_axi_bid[m]     = '0;
            assign s_axi_bresp[m]   = 2'b00;
            assign s_axi_bvalid[m]  = 1'b0;
            assign s_axi_arready[m] = 1'b0;
            assign s_axi_rid[m]     = '0;
            assign s_axi_rdata[m]   = '0;
            assign s_axi_rresp[m]   = 2'b00;
            assign s_axi_rlast[m]   = 1'b0;
            assign s_axi_rvalid[m]  = 1'b0;
        end
    endgenerate

    genvar s;
    generate
        for (s = 0; s < NUM_SLAVES; s++) begin : gen_slave_stub
            assign m_axi_awid[s]    = '0;
            assign m_axi_awaddr[s]  = '0;
            assign m_axi_awlen[s]   = 8'h0;
            assign m_axi_awsize[s]  = 3'b010;
            assign m_axi_awburst[s] = 2'b01;
            assign m_axi_awvalid[s] = 1'b0;
            assign m_axi_wdata[s]   = '0;
            assign m_axi_wstrb[s]   = '0;
            assign m_axi_wlast[s]   = 1'b0;
            assign m_axi_wvalid[s]  = 1'b0;
            assign m_axi_bready[s]  = 1'b1;
            assign m_axi_arid[s]    = '0;
            assign m_axi_araddr[s]  = '0;
            assign m_axi_arlen[s]   = 8'h0;
            assign m_axi_arsize[s]  = 3'b010;
            assign m_axi_arburst[s] = 2'b01;
            assign m_axi_arvalid[s] = 1'b0;
            assign m_axi_rready[s]  = 1'b1;
        end
    endgenerate

    // Kullanılmayan parametreler — implementasyonda kullanılacak
    /* verilator lint_off UNUSEDPARAM */
    localparam _addr_params_used = 1; // BOOT_ROM_BASE vb. TODO bloğunda kullanılacak
    /* verilator lint_on UNUSEDPARAM */

endmodule
