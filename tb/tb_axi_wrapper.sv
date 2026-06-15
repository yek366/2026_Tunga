`timescale 1ns / 1ps
// ==============================================================================
//  tb_axi_wrapper.sv
//  Integration Testbench for Processor Core and AXI-Lite Bus Wrapper
// ==============================================================================

import axi_pkg::*;

// --- Mock ROM Module (Feeds boot instructions to the CPU) ---
module mock_rom (
    input  logic              clk_i,
    input  logic              rst_ni,
    input  axi_pkg::axi_req_t axi_req_i,
    output axi_pkg::axi_rsp_t axi_rsp_o
);
  import axi_pkg::*;

  logic [31:0] mem [16];

  initial begin
    // Simple Boot Program for RISC-V:
    // Address 0x00000000: lui  x1, 0x12345     -> 32'h123450B7
    // Address 0x00000004: addi x1, x1, 0x678   -> 32'h67808093  (x1 = 0x12345678)
    // Address 0x00000008: lui  x2, 0x10000     -> 32'h10000137  (x2 = 0x10000000: SRAM Base)
    // Address 0x0000000C: sw   x1, 0(x2)       -> 32'h00112023  (SRAM Write)
    // Address 0x00000010: lw   x3, 0(x2)       -> 32'h00012183  (SRAM Read)
    // Address 0x00000014: jal  x0, 0           -> 32'h0000006F  (Infinite Loop)

    mem[0] = 32'h123450B7; // lui x1, 0x12345
    mem[1] = 32'h67808093; // addi x1, x1, 0x678
    mem[2] = 32'h10000137; // lui x2, 0x10000
    mem[3] = 32'h00112023; // sw x1, 0(x2)
    mem[4] = 32'h00012183; // lw x3, 0(x2)
    mem[5] = 32'h0000006F; // jal x0, 0
    for (int i = 6; i < 16; i++) begin
      mem[i] = 32'h00000013; // nop
    end
  end

  logic r_valid_q, r_valid_d;
  logic [31:0] rdata_q, rdata_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_valid_q <= 1'b0;
      rdata_q   <= 32'h0;
    end else begin
      r_valid_q <= r_valid_d;
      rdata_q   <= rdata_d;
      if (axi_req_i.ar_valid && axi_rsp_o.ar_ready) begin
        $display("[ROM DEBUG] Addr 0x%h accepted (index %0d)", axi_req_i.ar.addr, axi_req_i.ar.addr[5:2]);
      end
      if (axi_rsp_o.r_valid && axi_req_i.r_ready) begin
        $display("[ROM DEBUG] Data 0x%h delivered", axi_rsp_o.r.data);
      end
    end
  end

  logic read_en;
  assign read_en = axi_req_i.ar_valid && !r_valid_q;

  assign axi_rsp_o.ar_ready = read_en;
  assign axi_rsp_o.aw_ready = 1'b0;
  assign axi_rsp_o.w_ready  = 1'b0;
  assign axi_rsp_o.b_valid  = 1'b0;
  assign axi_rsp_o.b        = '0;

  assign axi_rsp_o.r_valid = r_valid_q;
  assign axi_rsp_o.r.data  = rdata_q;
  assign axi_rsp_o.r.resp  = RESP_OKAY;
  assign axi_rsp_o.r.last  = 1'b1;
  assign axi_rsp_o.r.user  = '0;

  logic [3:0] read_addr;
  assign read_addr = axi_req_i.ar.addr[5:2];

  always_comb begin
    r_valid_d = r_valid_q;
    rdata_d   = rdata_q;
    if (read_en) begin
      r_valid_d = 1'b1;
      rdata_d   = mem[read_addr];
    end else if (r_valid_q && axi_req_i.r_ready) begin
      r_valid_d = 1'b0;
    end
  end
endmodule


// --- Main Testbench Module ---
module tb_axi_wrapper;

  logic clk;
  logic rst_n;
  logic [31:0] irq;

  // Interconnect signals for ROM
  axi_req_t rom_req;
  axi_rsp_t rom_rsp;

  // Tie off dummy peripheral responses
  axi_rsp_t dummy_rsp;
  assign dummy_rsp.aw_ready = 1'b0;
  assign dummy_rsp.w_ready  = 1'b0;
  assign dummy_rsp.b_valid  = 1'b0;
  assign dummy_rsp.b        = '0;
  assign dummy_rsp.ar_ready = 1'b0;
  assign dummy_rsp.r_valid  = 1'b0;
  assign dummy_rsp.r        = '0;

  // Clock Generation (50 MHz)
  always begin
    clk = 1'b0;
    #10;
    clk = 1'b1;
    #10;
  end

  // DUT Instance
  axi_wrapper i_dut (
      .clk_i               ( clk   ),
      .rst_ni              ( rst_n ),
      .irq_i               ( irq   ),

      // ROM
      .rom_axi_req_o       ( rom_req ),
      .rom_axi_rsp_i       ( rom_rsp ),

      // Peripherals (tied to dummy/idle responses)
      .uart_axi_req_o      ( ),
      .uart_axi_rsp_i      ( dummy_rsp ),
      .gpio_axi_req_o      ( ),
      .gpio_axi_rsp_i      ( dummy_rsp ),
      .timer_axi_req_o     ( ),
      .timer_axi_rsp_i     ( dummy_rsp ),
      .i2c_axi_req_o       ( ),
      .i2c_axi_rsp_i       ( dummy_rsp ),
      .qspi_axi_req_o      ( ),
      .qspi_axi_rsp_i      ( dummy_rsp ),
      .npu_axi_req_o       ( ),
      .npu_axi_rsp_i       ( dummy_rsp )
  );

  // Mock ROM Instance
  mock_rom i_rom (
      .clk_i               ( clk     ),
      .rst_ni              ( rst_n   ),
      .axi_req_i           ( rom_req ),
      .axi_rsp_o           ( rom_rsp )
  );

  // Stimulus process
  initial begin
    irq   = 32'h0;
    rst_n = 1'b0;
    
    // Reset cycle
    #100;
    @(posedge clk);
    #2;
    rst_n = 1'b1;
    $display("[TB] Reset de-asserted, CPU starting execution...");

    // Watch register writes and memory operations
    // Stop simulation after loop address is reached
    #2000;
    $display("[TB] Test finished.");
    $finish;
  end

  // Monitor OBI Instruction fetches, ROM accesses and SRAM transactions
  always @(posedge clk) begin
    if (rst_n) begin
      // 1. Core-level instruction OBI request and grant
      if (i_dut.instr_obi_req.req) begin
        $display("[MONITOR - CORE INSTR REQ] Addr: 0x%h, Grant: %b", 
                 i_dut.instr_obi_req.a.addr, i_dut.instr_obi_rsp.gnt);
      end
      if (i_dut.instr_obi_rsp.rvalid) begin
        $display("[MONITOR - CORE INSTR RESP] Data: 0x%h", 
                 i_dut.instr_obi_rsp.r.rdata);
      end

      // 2. ROM AXI requests
      if (rom_req.ar_valid) begin
        $display("[MONITOR - ROM AXI REQ] Addr: 0x%h, Ready: %b", 
                 rom_req.ar.addr, rom_rsp.ar_ready);
      end
      if (rom_rsp.r_valid) begin
        $display("[MONITOR - ROM AXI RESP] Data: 0x%h, Ready: %b", 
                 rom_rsp.r.data, rom_req.r_ready);
      end

      // 3. SRAM transactions
      if (i_dut.i_sram.write_en) begin
        $display("[MONITOR - SRAM WRITE] Addr: 0x%h, Data: 0x%h, Strobe: %b", 
                 i_dut.i_sram.axi_req_i.aw.addr, 
                 i_dut.i_sram.axi_req_i.w.data, 
                 i_dut.i_sram.axi_req_i.w.strb);
      end
      if (i_dut.i_sram.read_en) begin
        $display("[MONITOR - SRAM READ REQ] Addr: 0x%h", 
                 i_dut.i_sram.axi_req_i.ar.addr);
      end
      if (i_dut.i_sram.axi_rsp_o.r_valid && i_dut.i_sram.axi_req_i.r_ready) begin
        $display("[MONITOR - SRAM READ RESP] Data: 0x%h", 
                 i_dut.i_sram.axi_rsp_o.r.data);
      end
    end
  end

endmodule
