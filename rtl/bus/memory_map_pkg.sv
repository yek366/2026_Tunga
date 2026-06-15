`timescale 1ns / 1ps
// Tunga SoC memory map

package memory_map_pkg;

  // ROM (Instruction Boot ROM): 16 KB
  localparam logic [31:0] ROM_BASE_ADDR   = 32'h0000_0000;
  localparam logic [31:0] ROM_HIGH_ADDR   = 32'h0000_3FFF;

  // SRAM (Main Data & Instruction Memory): 1 MB
  localparam logic [31:0] SRAM_BASE_ADDR  = 32'h1000_0000;
  localparam logic [31:0] SRAM_HIGH_ADDR  = 32'h100F_FFFF;

  // UART Peripheral: 256 Bytes
  localparam logic [31:0] UART_BASE_ADDR  = 32'h2000_0000;
  localparam logic [31:0] UART_HIGH_ADDR  = 32'h2000_00FF;

  // GPIO Peripheral: 256 Bytes
  localparam logic [31:0] GPIO_BASE_ADDR  = 32'h2000_1000;
  localparam logic [31:0] GPIO_HIGH_ADDR  = 32'h2000_10FF;

  // Timer Peripheral: 256 Bytes
  localparam logic [31:0] TIMER_BASE_ADDR = 32'h2000_2000;
  localparam logic [31:0] TIMER_HIGH_ADDR = 32'h2000_20FF;

  // I2C Peripheral: 256 Bytes
  localparam logic [31:0] I2C_BASE_ADDR   = 32'h2000_3000;
  localparam logic [31:0] I2C_HIGH_ADDR   = 32'h2000_30FF;

  // QSPI Peripheral: 256 Bytes
  localparam logic [31:0] QSPI_BASE_ADDR  = 32'h2000_4000;
  localparam logic [31:0] QSPI_HIGH_ADDR  = 32'h2000_40FF;

  // NPU (Neural Processing Unit Accelerator): 4 KB
  localparam logic [31:0] NPU_BASE_ADDR   = 32'h2000_5000;
  localparam logic [31:0] NPU_HIGH_ADDR   = 32'h2000_5FFF;

endpackage
