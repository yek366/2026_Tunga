`timescale 1ns / 1ps
// ==============================================================================
//  memory_map_pkg.sv
//  Tunga SoC Memory Map Definition
// ==============================================================================

package memory_map_pkg;

  // ROM (Instruction Boot ROM): 16 KB / up to 1GB mapped in the design
  localparam logic [31:0] ROM_BASE_ADDR         = 32'h0000_0000;
  localparam logic [31:0] ROM_HIGH_ADDR         = 32'h3FFF_FFFF;

  // SRAM (Main Data & Instruction Memory): 8 KB
  localparam logic [31:0] SRAM_BASE_ADDR        = 32'hC000_0000;
  localparam logic [31:0] SRAM_HIGH_ADDR        = 32'hC000_1FFF;

  // UART Stream (Console/Rx/Tx): 4 KB
  localparam logic [31:0] UART_STREAM_BASE_ADDR = 32'h4001_0000;
  localparam logic [31:0] UART_STREAM_HIGH_ADDR = 32'h4001_0FFF;

  // UART Control (Peripheral Registers): 4 KB
  localparam logic [31:0] UART_CTRL_BASE_ADDR   = 32'h4001_1000;
  localparam logic [31:0] UART_CTRL_HIGH_ADDR   = 32'h4001_1FFF;

  // GPIO Peripheral: 64 KB
  localparam logic [31:0] GPIO_BASE_ADDR        = 32'h4000_0000;
  localparam logic [31:0] GPIO_HIGH_ADDR        = 32'h4000_FFFF;

  // Timer Peripheral: 64 KB
  localparam logic [31:0] TIMER_BASE_ADDR       = 32'h41C0_0000;
  localparam logic [31:0] TIMER_HIGH_ADDR       = 32'h41C0_FFFF;

  // I2C Peripheral: 64 KB
  localparam logic [31:0] I2C_BASE_ADDR         = 32'h4080_0000;
  localparam logic [31:0] I2C_HIGH_ADDR         = 32'h4080_FFFF;

  // QSPI Peripheral (NOR Flash): 128 KB
  localparam logic [31:0] QSPI_BASE_ADDR        = 32'h44A0_0000;
  localparam logic [31:0] QSPI_HIGH_ADDR        = 32'h44A1_FFFF;

  // NPU CSR Registers: 4 KB
  localparam logic [31:0] NPU_BASE_ADDR         = 32'h4500_0000;
  localparam logic [31:0] NPU_HIGH_ADDR         = 32'h4500_0FFF;

  // Interrupt Controller (INTC): 64 KB
  localparam logic [31:0] INTC_BASE_ADDR         = 32'h4120_0000;
  localparam logic [31:0] INTC_HIGH_ADDR         = 32'h4120_FFFF;

endpackage
