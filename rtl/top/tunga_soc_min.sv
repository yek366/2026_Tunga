// ============================================================
// Module : tunga_soc_min
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-06-06
// Desc   : Minimal boot SoC for the DDK teknotest gate. Self-contained,
//          single clock, single OBI master (CV32E40P). NO AXI
//          interconnect — a small inline OBI fabric routes the data bus
//          to boot ROM / data SRAM / UART0. This is the gate vehicle;
//          the full SoC (tunga_soc_top.sv) supersedes it later.
//
//          Gate-local memory map (provisional):
//            BOOTROM  0x0000_0000  4 KB  (instr + data-side reads)
//            UART0    0x1000_0000  4 KB  (AXI4-Lite via obi2axil)
//            DATA SRAM 0x8000_0000 8 KB
//
//          Boot: core resets to 0x0, runs helloworld from boot ROM,
//          drives UART0 ('R' → 'A' → "Hello World!").
// ============================================================

`timescale 1ns/1ps

module tunga_soc_min (
    input  logic clk_i,
    input  logic rst_ni,      // active-low

    output logic uart0_tx_o,
    input  logic uart0_rx_i
);

    // -------------------------------------------------------------
    // CV32E40P OBI interfaces
    // -------------------------------------------------------------
    // Instruction bus
    logic        instr_req, instr_gnt, instr_rvalid;
    logic [31:0] instr_addr, instr_rdata;
    // Data bus
    logic        data_req, data_gnt, data_rvalid, data_we;
    logic [3:0]  data_be;
    logic [31:0] data_addr, data_wdata, data_rdata;

    // -------------------------------------------------------------
    // Core
    // -------------------------------------------------------------
    cv32e40p_top #(
        .COREV_PULP      (0),
        .COREV_CLUSTER   (0),
        .FPU             (0),
        .ZFINX           (0),
        .NUM_MHPMCOUNTERS(1)
    ) u_core (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),

        .pulp_clock_en_i(1'b1),
        .scan_cg_en_i   (1'b0),

        .boot_addr_i        (32'h0000_0000),
        .mtvec_addr_i       (32'h0000_0000),
        .dm_halt_addr_i     (32'h0000_0000),
        .hart_id_i          (32'h0000_0000),
        .dm_exception_addr_i(32'h0000_0000),

        .instr_req_o   (instr_req),
        .instr_gnt_i   (instr_gnt),
        .instr_rvalid_i(instr_rvalid),
        .instr_addr_o  (instr_addr),
        .instr_rdata_i (instr_rdata),

        .data_req_o   (data_req),
        .data_gnt_i   (data_gnt),
        .data_rvalid_i(data_rvalid),
        .data_we_o    (data_we),
        .data_be_o    (data_be),
        .data_addr_o  (data_addr),
        .data_wdata_o (data_wdata),
        .data_rdata_i (data_rdata),

        .irq_i     (32'h0),
        .irq_ack_o (),
        .irq_id_o  (),

        .debug_req_i      (1'b0),
        .debug_havereset_o(),
        .debug_running_o  (),
        .debug_halted_o   (),

        .fetch_enable_i(1'b1),
        .core_sleep_o  ()
    );

    // -------------------------------------------------------------
    // Boot ROM (dual read port: A=instr, B=data)
    // -------------------------------------------------------------
    logic        romB_req, romB_gnt, romB_rvalid;
    logic [31:0] romB_rdata;

    obi_bootrom #(.WORDS(1024)) u_bootrom (
        .clk   (clk_i),
        .rst_n (rst_ni),
        // Port A — instruction fetch
        .a_req   (instr_req),
        .a_gnt   (instr_gnt),
        .a_addr  (instr_addr),
        .a_rdata (instr_rdata),
        .a_rvalid(instr_rvalid),
        // Port B — data side (.data load image, rodata)
        .b_req   (romB_req),
        .b_gnt   (romB_gnt),
        .b_addr  (data_addr),
        .b_we    (data_we),
        .b_rdata (romB_rdata),
        .b_rvalid(romB_rvalid)
    );

    // -------------------------------------------------------------
    // Data SRAM (8 KB)
    // -------------------------------------------------------------
    logic        sram_req, sram_gnt, sram_rvalid;
    logic [31:0] sram_rdata;

    obi_sram #(.WORDS(2048)) u_sram (
        .clk   (clk_i),
        .rst_n (rst_ni),
        .obi_req   (sram_req),
        .obi_gnt   (sram_gnt),
        .obi_addr  (data_addr),
        .obi_we    (data_we),
        .obi_be    (data_be),
        .obi_wdata (data_wdata),
        .obi_rdata (sram_rdata),
        .obi_rvalid(sram_rvalid)
    );

    // -------------------------------------------------------------
    // UART0 (AXI4-Lite) behind an OBI→AXI-Lite adapter
    // -------------------------------------------------------------
    logic        uart_req, uart_gnt, uart_rvalid;
    logic [31:0] uart_rdata;

    logic [7:0]  ua_awaddr,  ua_araddr;
    logic        ua_awvalid, ua_awready, ua_wvalid, ua_wready;
    logic        ua_bvalid,  ua_bready,  ua_arvalid, ua_arready;
    logic        ua_rvalid,  ua_rready;
    logic [31:0] ua_wdata,   ua_rdata;
    logic [3:0]  ua_wstrb;
    logic [1:0]  ua_bresp,   ua_rresp;

    obi2axil #(.AXIL_ADDR_W(8)) u_obi2axil (
        .clk   (clk_i),
        .rst_n (rst_ni),
        .obi_req   (uart_req),
        .obi_gnt   (uart_gnt),
        .obi_addr  (data_addr),
        .obi_we    (data_we),
        .obi_be    (data_be),
        .obi_wdata (data_wdata),
        .obi_rdata (uart_rdata),
        .obi_rvalid(uart_rvalid),

        .m_axil_awaddr (ua_awaddr),
        .m_axil_awvalid(ua_awvalid),
        .m_axil_awready(ua_awready),
        .m_axil_wdata  (ua_wdata),
        .m_axil_wstrb  (ua_wstrb),
        .m_axil_wvalid (ua_wvalid),
        .m_axil_wready (ua_wready),
        .m_axil_bresp  (ua_bresp),
        .m_axil_bvalid (ua_bvalid),
        .m_axil_bready (ua_bready),
        .m_axil_araddr (ua_araddr),
        .m_axil_arvalid(ua_arvalid),
        .m_axil_arready(ua_arready),
        .m_axil_rdata  (ua_rdata),
        .m_axil_rresp  (ua_rresp),
        .m_axil_rvalid (ua_rvalid),
        .m_axil_rready (ua_rready)
    );

    uart_peripheral #(
        .SYS_CLK_HZ  (50_000_000),
        .DEFAULT_BAUD(115_200),
        .AXI_ADDR_W  (8),
        .AXI_DATA_W  (32)
    ) u_uart (
        .clk   (clk_i),
        .rst_n (rst_ni),
        .s_axil_awaddr (ua_awaddr),
        .s_axil_awvalid(ua_awvalid),
        .s_axil_awready(ua_awready),
        .s_axil_wdata  (ua_wdata),
        .s_axil_wstrb  (ua_wstrb),
        .s_axil_wvalid (ua_wvalid),
        .s_axil_wready (ua_wready),
        .s_axil_bresp  (ua_bresp),
        .s_axil_bvalid (ua_bvalid),
        .s_axil_bready (ua_bready),
        .s_axil_araddr (ua_araddr),
        .s_axil_arvalid(ua_arvalid),
        .s_axil_arready(ua_arready),
        .s_axil_rdata  (ua_rdata),
        .s_axil_rresp  (ua_rresp),
        .s_axil_rvalid (ua_rvalid),
        .s_axil_rready (ua_rready),
        .uart_rxd(uart0_rx_i),
        .uart_txd(uart0_tx_o),
        .uart_irq()
    );

    // -------------------------------------------------------------
    // Inline data-bus OBI fabric (one outstanding transaction)
    //   decode by data_addr[31:28]:
    //     0x0 → boot ROM (port B)
    //     0x1 → UART0
    //     0x8 → data SRAM
    //     else → error responder (rvalid, rdata=0)
    // -------------------------------------------------------------
    localparam logic [1:0] SEL_ROM  = 2'd0;
    localparam logic [1:0] SEL_UART = 2'd1;
    localparam logic [1:0] SEL_SRAM = 2'd2;
    localparam logic [1:0] SEL_ERR  = 2'd3;

    logic [1:0] sel;
    always_comb begin
        unique case (data_addr[31:28])
            4'h0:    sel = SEL_ROM;
            4'h1:    sel = SEL_UART;
            4'h8:    sel = SEL_SRAM;
            default: sel = SEL_ERR;
        endcase
    end

    logic       busy_q;
    logic [1:0] sel_q;
    logic       err_resp_q;

    // Route request to the selected slave only while idle
    wire idle = ~busy_q;
    assign romB_req = idle & data_req & (sel == SEL_ROM);
    assign uart_req = idle & data_req & (sel == SEL_UART);
    assign sram_req = idle & data_req & (sel == SEL_SRAM);
    wire   err_req  = idle & data_req & (sel == SEL_ERR);
    wire   err_gnt  = ~err_resp_q;

    // Master grant = selected slave grant (idle only)
    always_comb begin
        unique case (sel)
            SEL_ROM:  data_gnt = idle & romB_gnt;
            SEL_UART: data_gnt = idle & uart_gnt;
            SEL_SRAM: data_gnt = idle & sram_gnt;
            default:  data_gnt = idle & err_gnt;
        endcase
    end

    // Response mux (busy phase)
    logic       err_rvalid;
    assign err_rvalid = err_resp_q;
    always_comb begin
        unique case (sel_q)
            SEL_ROM:  begin data_rvalid = romB_rvalid; data_rdata = romB_rdata; end
            SEL_UART: begin data_rvalid = uart_rvalid; data_rdata = uart_rdata; end
            SEL_SRAM: begin data_rvalid = sram_rvalid; data_rdata = sram_rdata; end
            default:  begin data_rvalid = err_rvalid;  data_rdata = 32'h0;      end
        endcase
        if (!busy_q) data_rvalid = 1'b0;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q     <= 1'b0;
            sel_q      <= SEL_ROM;
            err_resp_q <= 1'b0;
        end else begin
            // error responder: 1-cycle delayed rvalid
            err_resp_q <= err_req & err_gnt;
            if (!busy_q) begin
                if (data_req & data_gnt) begin
                    busy_q <= 1'b1;
                    sel_q  <= sel;
                end
            end else begin
                if (data_rvalid) busy_q <= 1'b0;
            end
        end
    end

endmodule
