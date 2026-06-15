`timescale 1ns / 1ps
// ==============================================================================
//  axi_wrapper.sv
//  Top-Level SoC Bus Wrapper (Integrating Core, Bridges, Interconnect & SRAM)
// ==============================================================================

import obi_pkg::*;
import axi_pkg::*;

module axi_wrapper #(
    parameter int unsigned AxiAddrWidth = 32,
    parameter int unsigned AxiDataWidth = 32,
    parameter int unsigned AxiUserWidth = 0,
    parameter bit          AxiLite      = 1'b1
) (
    // Clock & Reset
    input  logic        clk_i,
    input  logic        rst_ni,

    // Interrupt Lines
    input  logic [31:0] irq_i,

    // External ROM Interface (Slave 0)
    output axi_req_t    rom_axi_req_o,
    input  axi_rsp_t    rom_axi_rsp_i,

    // External Peripheral AXI-Lite Interfaces (Slaves 2 to 7)
    output axi_req_t    uart_axi_req_o,
    input  axi_rsp_t    uart_axi_rsp_i,

    output axi_req_t    gpio_axi_req_o,
    input  axi_rsp_t    gpio_axi_rsp_i,

    output axi_req_t    timer_axi_req_o,
    input  axi_rsp_t    timer_axi_rsp_i,

    output axi_req_t    i2c_axi_req_o,
    input  axi_rsp_t    i2c_axi_rsp_i,

    output axi_req_t    qspi_axi_req_o,
    input  axi_rsp_t    qspi_axi_rsp_i,

    output axi_req_t    npu_axi_req_o,
    input  axi_rsp_t    npu_axi_rsp_i
);

    // --- OBI INTERCONNECTION SIGNALS ---
    obi_req_t instr_obi_req;
    obi_rsp_t instr_obi_rsp;

    obi_req_t data_obi_req;
    obi_rsp_t data_obi_rsp;

    // Drive unused fields of OBI request structs to safe defaults to prevent X propagation
    always_comb begin
        instr_obi_req.a.we         = 1'b0;    // Always read for instruction fetch
        instr_obi_req.a.be         = 4'b1111; // 32-bit width by default
        instr_obi_req.a.wdata      = 32'h0;
        instr_obi_req.a.aid        = 1'b0;
        instr_obi_req.a.a_optional = '0;

        data_obi_req.a.aid         = 1'b0;
        data_obi_req.a.a_optional  = '0;
    end

    // --- AXI MASTER SIGNALS (Bridges to Interconnect) ---
    axi_req_t [1:0] master_axi_req;
    axi_rsp_t [1:0] master_axi_rsp;

    // --- AXI SLAVE SIGNALS (Interconnect to Slaves) ---
    axi_req_t [7:0] slave_axi_req;
    axi_rsp_t [7:0] slave_axi_rsp;

    // --- 1. İŞLEMCİ ÇEKİRDEĞİ (CV32E40P) ---
    cv32e40p_top #(
        .COREV_PULP ( 0 ),
        .FPU        ( 0 )
    ) i_core (
        .clk_i           ( clk_i ),
        .rst_ni          ( rst_ni ),

        .pulp_clock_en_i ( 1'b0 ),
        .scan_cg_en_i    ( 1'b0 ),

        .boot_addr_i         ( 32'h00000000 ),
        .mtvec_addr_i        ( 32'h00000000 ),
        .dm_halt_addr_i      ( 32'h00000000 ),
        .hart_id_i           ( 32'h00000000 ),
        .dm_exception_addr_i ( 32'h00000000 ),

        // Instruction OBI Portu
        .instr_req_o     ( instr_obi_req.req ),
        .instr_gnt_i     ( instr_obi_rsp.gnt ),
        .instr_addr_o    ( instr_obi_req.a.addr ),
        .instr_rvalid_i  ( instr_obi_rsp.rvalid ),
        .instr_rdata_i   ( instr_obi_rsp.r.rdata ),

        // Data OBI Portu
        .data_req_o      ( data_obi_req.req ),
        .data_gnt_i      ( data_obi_rsp.gnt ),
        .data_addr_o     ( data_obi_req.a.addr ),
        .data_we_o       ( data_obi_req.a.we ),
        .data_be_o       ( data_obi_req.a.be ),
        .data_wdata_o    ( data_obi_req.a.wdata ),
        .data_rvalid_i   ( data_obi_rsp.rvalid ),
        .data_rdata_i    ( data_obi_rsp.r.rdata ),

        // Kontrol ve Kesmeler
        .irq_i           ( irq_i ),
        .fetch_enable_i  ( 1'b1 ),
        .debug_req_i     ( 1'b0 )
    );

    // --- 2. KÖPRÜ 1: INSTRUCTION TO AXI ---
    obi_to_axi #(
        .AxiLite     ( AxiLite ),
        .MaxRequests ( 2 ),
        .obi_req_t   ( obi_req_t ),
        .obi_rsp_t   ( obi_rsp_t ),
        .axi_req_t   ( axi_req_t ),
        .axi_rsp_t   ( axi_rsp_t )
    ) i_instr_bridge (
        .clk_i       ( clk_i ),
        .rst_ni      ( rst_ni ),
        .obi_req_i   ( instr_obi_req ),
        .obi_rsp_o   ( instr_obi_rsp ),
        .axi_req_o   ( master_axi_req[0] ),
        .axi_rsp_i   ( master_axi_rsp[0] ),
        .user_i      ( '0 ),
        .obi_rsp_user_i ( '0 )
    );

    // --- 3. KÖPRÜ 2: DATA TO AXI ---
    obi_to_axi #(
        .AxiLite     ( AxiLite ),
        .MaxRequests ( 4 ),
        .obi_req_t   ( obi_req_t ),
        .obi_rsp_t   ( obi_rsp_t ),
        .axi_req_t   ( axi_req_t ),
        .axi_rsp_t   ( axi_rsp_t )
    ) i_data_bridge (
        .clk_i       ( clk_i ),
        .rst_ni      ( rst_ni ),
        .obi_req_i   ( data_obi_req ),
        .obi_rsp_o   ( data_obi_rsp ),
        .axi_req_o   ( master_axi_req[1] ),
        .axi_rsp_i   ( master_axi_rsp[1] ),
        .user_i      ( '0 ),
        .obi_rsp_user_i ( '0 )
    );

    // --- 4. AXI LITE INTERCONNECT ---
    axi_lite_interconnect #(
        .req_t       ( axi_req_t ),
        .rsp_t       ( axi_rsp_t )
    ) i_interconnect (
        .clk_i       ( clk_i ),
        .rst_ni      ( rst_ni ),
        .master_req_i( master_axi_req ),
        .master_rsp_o( master_axi_rsp ),
        .slave_req_o ( slave_axi_req ),
        .slave_rsp_i ( slave_axi_rsp )
    );

    // --- 5. INTERNAL SRAM MODULE (Slave 1) ---
    sram_module #(
        .DepthBytes  ( 1048576 ), // 1 MB SRAM
        .req_t       ( axi_req_t ),
        .rsp_t       ( axi_rsp_t )
    ) i_sram (
        .clk_i       ( clk_i ),
        .rst_ni      ( rst_ni ),
        .axi_req_i   ( slave_axi_req[1] ),
        .axi_rsp_o   ( slave_axi_rsp[1] )
    );

    // --- 6. EXTERNAL SLAVES WIRING ---
    // Slave 0: ROM
    assign rom_axi_req_o    = slave_axi_req[0];
    assign slave_axi_rsp[0] = rom_axi_rsp_i;

    // Slave 2: UART
    assign uart_axi_req_o   = slave_axi_req[2];
    assign slave_axi_rsp[2] = uart_axi_rsp_i;

    // Slave 3: GPIO
    assign gpio_axi_req_o   = slave_axi_req[3];
    assign slave_axi_rsp[3] = gpio_axi_rsp_i;

    // Slave 4: TIMER
    assign timer_axi_req_o  = slave_axi_req[4];
    assign slave_axi_rsp[4] = timer_axi_rsp_i;

    // Slave 5: I2C
    assign i2c_axi_req_o    = slave_axi_req[5];
    assign slave_axi_rsp[5] = i2c_axi_rsp_i;

    // Slave 6: QSPI
    assign qspi_axi_req_o   = slave_axi_req[6];
    assign slave_axi_rsp[6] = qspi_axi_rsp_i;

    // Slave 7: NPU
    assign npu_axi_req_o    = slave_axi_req[7];
    assign slave_axi_rsp[7] = npu_axi_rsp_i;

endmodule