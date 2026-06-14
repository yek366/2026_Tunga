// ============================================================
// Module : obi_bootrom
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-06-06
// Desc   : Dual read-port boot ROM for the teknotest gate.
//          Port A = CV32E40P instruction fetch, Port B = data side
//          (.data load-image copy + .rodata reads). Read-only; writes
//          are acknowledged but ignored. One outstanding txn per port,
//          1-cycle read latency.
//
//          Memory array is named `rom` so the teknotest testbench can
//          load it hierarchically:
//            $readmemh("helloworld.mem", dut.u_soc.u_bootrom.rom);
//          (helloworld.mem filename is fixed by DDK — do not rename.)
// ============================================================

`timescale 1ns/1ps

module obi_bootrom #(
    parameter int WORDS = 1024  // 1024 × 32-bit = 4 KB
) (
    input  logic        clk,
    input  logic        rst_n,

    // Port A — instruction fetch (read-only)
    input  logic        a_req,
    output logic        a_gnt,
    input  logic [31:0] a_addr,
    output logic [31:0] a_rdata,
    output logic        a_rvalid,

    // Port B — data side (read; writes ignored)
    input  logic        b_req,
    output logic        b_gnt,
    input  logic [31:0] b_addr,
    input  logic        b_we,
    output logic [31:0] b_rdata,
    output logic        b_rvalid
);

    localparam int AW = $clog2(WORDS);

    // Loaded by the testbench via hierarchical $readmemh into `rom`
    // (helloworld.mem). Externally driven → waive UNDRIVEN for lint.
    /* verilator lint_off UNDRIVEN */
    logic [31:0] rom [0:WORDS-1];
    /* verilator lint_on UNDRIVEN */

    // ---- Port A ----
    logic        a_pending_q;
    logic [31:0] a_rdata_q;
    assign a_gnt = ~a_pending_q;
    wire   a_accept = a_req & a_gnt;
    wire [AW-1:0] a_idx = a_addr[AW+1:2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_pending_q <= 1'b0;
            a_rdata_q   <= 32'h0;
        end else begin
            a_pending_q <= a_accept;
            if (a_accept) a_rdata_q <= rom[a_idx];
        end
    end
    assign a_rdata  = a_rdata_q;
    assign a_rvalid = a_pending_q;

    // ---- Port B ----
    logic        b_pending_q;
    logic [31:0] b_rdata_q;
    assign b_gnt = ~b_pending_q;
    wire   b_accept = b_req & b_gnt;
    wire [AW-1:0] b_idx = b_addr[AW+1:2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_pending_q <= 1'b0;
            b_rdata_q   <= 32'h0;
        end else begin
            b_pending_q <= b_accept;
            if (b_accept) b_rdata_q <= rom[b_idx]; // writes ignored (ROM)
        end
    end
    assign b_rdata  = b_rdata_q;
    assign b_rvalid = b_pending_q;

    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, a_addr[31:AW+2], a_addr[1:0],
                          b_addr[31:AW+2], b_addr[1:0], b_we};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
