`timescale 1ns / 1ps
// ==============================================================================
//  sram_module.sv
//  AXI-Lite Synchronous SRAM Controller
// ==============================================================================

import axi_pkg::*;

module sram_module #(
    parameter int unsigned DepthBytes = 1048576, // 1 MB default
    parameter type req_t = axi_pkg::axi_req_t,
    parameter type rsp_t = axi_pkg::axi_rsp_t
) (
    input  logic  clk_i,
    input  logic  rst_ni,

    input  req_t  axi_req_i,
    output rsp_t  axi_rsp_o
);

  localparam int unsigned Words = DepthBytes / 4;
  localparam int unsigned AddrWidth = $clog2(Words);

  // RAM array (32-bit width, byte writable)
  logic [31:0] mem [Words];

  // Address conversion: convert byte address to word address (discard lowest 2 bits)
  logic [AddrWidth-1:0] write_addr;
  logic [AddrWidth-1:0] read_addr;

  assign write_addr = axi_req_i.aw.addr[AddrWidth+1:2];
  assign read_addr  = axi_req_i.ar.addr[AddrWidth+1:2];

  // --- WRITE CHANNEL LOGIC ---
  logic b_valid_q, b_valid_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      b_valid_q <= 1'b0;
    end else begin
      b_valid_q <= b_valid_d;
    end
  end

  // Write transaction is granted when both AW and W are valid and we aren't holding a response
  logic write_en;
  assign write_en = axi_req_i.aw_valid && axi_req_i.w_valid && !b_valid_q;

  assign axi_rsp_o.aw_ready = write_en;
  assign axi_rsp_o.w_ready  = write_en;

  // B (Write Response) Handshake
  assign axi_rsp_o.b_valid = b_valid_q;
  assign axi_rsp_o.b.resp  = axi_pkg::RESP_OKAY;
  assign axi_rsp_o.b.user  = '0;

  always_comb begin
    b_valid_d = b_valid_q;
    if (write_en) begin
      b_valid_d = 1'b1;
    end else if (b_valid_q && axi_req_i.b_ready) begin
      b_valid_d = 1'b0;
    end
  end

  // Synchronous Memory Write with byte strobes
  always_ff @(posedge clk_i) begin
    if (write_en) begin
      if (axi_req_i.w.strb[0]) mem[write_addr][7:0]   <= axi_req_i.w.data[7:0];
      if (axi_req_i.w.strb[1]) mem[write_addr][15:8]  <= axi_req_i.w.data[15:8];
      if (axi_req_i.w.strb[2]) mem[write_addr][23:16] <= axi_req_i.w.data[23:16];
      if (axi_req_i.w.strb[3]) mem[write_addr][31:24] <= axi_req_i.w.data[31:24];
    end
  end

  // --- READ CHANNEL LOGIC ---
  logic r_valid_q, r_valid_d;
  logic [31:0] rdata_q, rdata_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_valid_q <= 1'b0;
      rdata_q   <= 32'h0;
    end else begin
      r_valid_q <= r_valid_d;
      rdata_q   <= rdata_d;
    end
  end

  // Read transaction is granted when AR is valid and we aren't holding a response
  logic read_en;
  assign read_en = axi_req_i.ar_valid && !r_valid_q;

  assign axi_rsp_o.ar_ready = read_en;

  // R (Read Response) Handshake
  assign axi_rsp_o.r_valid = r_valid_q;
  assign axi_rsp_o.r.data  = rdata_q;
  assign axi_rsp_o.r.resp  = axi_pkg::RESP_OKAY;
  assign axi_rsp_o.r.last  = 1'b1;
  assign axi_rsp_o.r.user  = '0;

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
