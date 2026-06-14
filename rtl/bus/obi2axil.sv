// ============================================================
// Module : obi2axil
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-06-06
// Desc   : OBI slave → AXI4-Lite master adapter (single 32-bit beat).
//          Bridges the CV32E40P data bus to an AXI4-Lite peripheral
//          (UART0). One outstanding transaction. Read and write both
//          return an OBI rvalid pulse (CV32E40P expects a response on
//          stores too). Write strobe = OBI byte-enable.
// ============================================================

`timescale 1ns/1ps

module obi2axil #(
    parameter int AXIL_ADDR_W = 8
) (
    input  logic        clk,
    input  logic        rst_n,

    // ---- OBI slave (CV32E40P data side) ----
    input  logic        obi_req,
    output logic        obi_gnt,
    input  logic [31:0] obi_addr,
    input  logic        obi_we,
    input  logic [3:0]  obi_be,
    input  logic [31:0] obi_wdata,
    output logic [31:0] obi_rdata,
    output logic        obi_rvalid,

    // ---- AXI4-Lite master ----
    output logic [AXIL_ADDR_W-1:0] m_axil_awaddr,
    output logic                   m_axil_awvalid,
    input  logic                   m_axil_awready,
    output logic [31:0]            m_axil_wdata,
    output logic [3:0]             m_axil_wstrb,
    output logic                   m_axil_wvalid,
    input  logic                   m_axil_wready,
    input  logic [1:0]             m_axil_bresp,
    input  logic                   m_axil_bvalid,
    output logic                   m_axil_bready,
    output logic [AXIL_ADDR_W-1:0] m_axil_araddr,
    output logic                   m_axil_arvalid,
    input  logic                   m_axil_arready,
    input  logic [31:0]            m_axil_rdata,
    input  logic [1:0]             m_axil_rresp,
    input  logic                   m_axil_rvalid,
    output logic                   m_axil_rready
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_RADDR,
        ST_RDATA,
        ST_WRITE,
        ST_WRESP
    } state_t;

    state_t st;

    logic [AXIL_ADDR_W-1:0] addr_q;
    logic [31:0]            wdata_q;
    logic [3:0]             be_q;
    logic                   aw_done_q;
    logic                   w_done_q;
    logic [31:0]            rdata_q;
    logic                   rvalid_q;

    assign obi_gnt = (st == ST_IDLE);
    wire   accept  = obi_req & obi_gnt;

    // AXI-Lite drive
    assign m_axil_araddr  = addr_q;
    assign m_axil_arvalid = (st == ST_RADDR);
    assign m_axil_rready   = (st == ST_RDATA);

    assign m_axil_awaddr  = addr_q;
    assign m_axil_awvalid = (st == ST_WRITE) & ~aw_done_q;
    assign m_axil_wdata   = wdata_q;
    assign m_axil_wstrb   = be_q;
    assign m_axil_wvalid  = (st == ST_WRITE) & ~w_done_q;
    assign m_axil_bready  = (st == ST_WRESP);

    assign obi_rdata  = rdata_q;
    assign obi_rvalid = rvalid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_IDLE;
            addr_q    <= '0;
            wdata_q   <= 32'h0;
            be_q      <= 4'h0;
            aw_done_q <= 1'b0;
            w_done_q  <= 1'b0;
            rdata_q   <= 32'h0;
            rvalid_q  <= 1'b0;
        end else begin
            rvalid_q <= 1'b0; // single-cycle OBI response pulse

            unique case (st)
                ST_IDLE: begin
                    if (accept) begin
                        addr_q  <= obi_addr[AXIL_ADDR_W-1:0];
                        wdata_q <= obi_wdata;
                        be_q    <= obi_be;
                        if (obi_we) begin
                            aw_done_q <= 1'b0;
                            w_done_q  <= 1'b0;
                            st        <= ST_WRITE;
                        end else begin
                            st <= ST_RADDR;
                        end
                    end
                end

                ST_RADDR: begin
                    if (m_axil_arready) st <= ST_RDATA;
                end

                ST_RDATA: begin
                    if (m_axil_rvalid) begin
                        rdata_q  <= m_axil_rdata;
                        rvalid_q <= 1'b1;
                        st       <= ST_IDLE;
                    end
                end

                ST_WRITE: begin
                    if (m_axil_awready) aw_done_q <= 1'b1;
                    if (m_axil_wready)  w_done_q  <= 1'b1;
                    if ((aw_done_q | m_axil_awready) &&
                        (w_done_q  | m_axil_wready)) begin
                        st <= ST_WRESP;
                    end
                end

                ST_WRESP: begin
                    if (m_axil_bvalid) begin
                        rdata_q  <= 32'h0;
                        rvalid_q <= 1'b1;
                        st       <= ST_IDLE;
                    end
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

    // bresp/rresp not surfaced to OBI (no error path needed for the gate)
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, m_axil_bresp, m_axil_rresp, obi_addr[31:AXIL_ADDR_W]};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
