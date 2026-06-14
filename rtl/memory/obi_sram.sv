// ============================================================
// Module : obi_sram
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-06-06
// Desc   : Single-port OBI data SRAM (read/write, byte-enable).
//          CV32E40P data-side memory. One outstanding transaction:
//          gnt high when idle, rvalid one cycle after an accepted
//          request. No response backpressure (OBI has no rready).
// ============================================================

`timescale 1ns/1ps

module obi_sram #(
    parameter int WORDS = 2048  // 2048 × 32-bit = 8 KB
) (
    input  logic        clk,
    input  logic        rst_n,

    // OBI slave
    input  logic        obi_req,
    output logic        obi_gnt,
    input  logic [31:0] obi_addr,
    input  logic        obi_we,
    input  logic [3:0]  obi_be,
    input  logic [31:0] obi_wdata,
    output logic [31:0] obi_rdata,
    output logic        obi_rvalid
);

    localparam int AW = $clog2(WORDS);

    logic [31:0] mem [0:WORDS-1];

    logic        pending_q;
    logic [31:0] rdata_q;

    // Accept a new request only while not presenting a response → one
    // outstanding transaction, deterministic 1-cycle latency.
    assign obi_gnt = ~pending_q;

    wire        accept = obi_req & obi_gnt;
    wire [AW-1:0] widx  = obi_addr[AW+1:2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_q <= 1'b0;
            rdata_q   <= 32'h0;
        end else begin
            pending_q <= accept;
            if (accept) begin
                if (obi_we) begin
                    if (obi_be[0]) mem[widx][7:0]   <= obi_wdata[7:0];
                    if (obi_be[1]) mem[widx][15:8]  <= obi_wdata[15:8];
                    if (obi_be[2]) mem[widx][23:16] <= obi_wdata[23:16];
                    if (obi_be[3]) mem[widx][31:24] <= obi_wdata[31:24];
                    rdata_q <= 32'h0;
                end else begin
                    rdata_q <= mem[widx];
                end
            end
        end
    end

    assign obi_rdata  = rdata_q;
    assign obi_rvalid = pending_q;

    // Upper address bits are decoded by the bus fabric, not here.
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, obi_addr[31:AW+2], obi_addr[1:0]};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
