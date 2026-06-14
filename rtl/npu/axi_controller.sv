// ============================================================
// Module : axi_controller
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : NPU AXI denetleyicisi.
//          - AXI4-Lite slave: CPU'dan CSR yazmaç erişimi (NPU_CTRL, NPU_STATUS,
//            NPU_INPUT_ADDR, NPU_WEIGHT_ADDR, NPU_RESULT)
//          - AXI4 master: 30 KB YZ belleğinden burst okuma / sonuç yazma
// ============================================================

`timescale 1ns/1ps

module axi_controller #(
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 32,
    parameter int AXI_ID_WIDTH    = 4,
    parameter int CSR_ADDR_WIDTH  = 8
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4-Lite Slave (CSR) ----
    input  logic [CSR_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  logic                      s_axil_awvalid,
    output logic                      s_axil_awready,
    input  logic [31:0]               s_axil_wdata,
    input  logic [3:0]                s_axil_wstrb,
    input  logic                      s_axil_wvalid,
    output logic                      s_axil_wready,
    output logic [1:0]                s_axil_bresp,
    output logic                      s_axil_bvalid,
    input  logic                      s_axil_bready,
    input  logic [CSR_ADDR_WIDTH-1:0] s_axil_araddr,
    input  logic                      s_axil_arvalid,
    output logic                      s_axil_arready,
    output logic [31:0]               s_axil_rdata,
    output logic [1:0]                s_axil_rresp,
    output logic                      s_axil_rvalid,
    input  logic                      s_axil_rready,

    // ---- AXI4 Master (YZ bellek erişimi) ----
    output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [3:0]                m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,
    output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,

    // ---- FSM arayüzü ----
    // CSR → FSM
    output logic        csr_start,
    output logic [31:0] csr_input_addr,
    output logic [31:0] csr_weight_addr,

    // FSM → CSR
    input  logic        fsm_done,
    input  logic        fsm_busy,
    input  logic [1:0]  fsm_result,

    // FSM ↔ AXI4 master okuma kanalı
    input  logic        mem_rd_req,
    input  logic [31:0] mem_rd_addr,
    input  logic [15:0] mem_rd_len,
    output logic        mem_rd_valid,
    output logic [7:0]  mem_rd_data,
    output logic        mem_rd_last,

    // FSM ↔ AXI4 master yazma kanalı
    input  logic        mem_wr_req,
    input  logic [31:0] mem_wr_addr,
    input  logic [31:0] mem_wr_data,
    output logic        mem_wr_done
);

    // ---- CSR adres sabitleri ----
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_CTRL_ADDR        = 8'h00;
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_STATUS_ADDR      = 8'h04;
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_INPUT_ADDR_REG   = 8'h08;
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_WEIGHT_ADDR_REG  = 8'h0C;
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_RESULT_ADDR      = 8'h10;

    // ---- CSR yazmaçları ----
    logic        reg_start;
    logic [31:0] reg_input_addr;
    logic [31:0] reg_weight_addr;

    assign csr_start       = reg_start;
    assign csr_input_addr  = reg_input_addr;
    assign csr_weight_addr = reg_weight_addr;

    // ---- AXI4-Lite yazma state machine ----
    typedef enum logic [1:0] {WR_IDLE, WR_ADDR, WR_DATA, WR_RESP} axil_wr_state_t;
    axil_wr_state_t wr_state;

    logic [CSR_ADDR_WIDTH-1:0] wr_addr_lat;
    logic [31:0]               wr_data_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state        <= WR_IDLE;
            reg_start       <= 1'b0;
            reg_input_addr  <= 32'h0;
            reg_weight_addr <= 32'h0;
            s_axil_awready  <= 1'b0;
            s_axil_wready   <= 1'b0;
            s_axil_bvalid   <= 1'b0;
            s_axil_bresp    <= 2'b00;
        end else begin
            // START bitini tek çevrimde temizle (pulse)
            if (reg_start) reg_start <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    s_axil_awready <= 1'b1;
                    s_axil_wready  <= 1'b1;
                    if (s_axil_awvalid && s_axil_wvalid) begin
                        wr_addr_lat    <= s_axil_awaddr;
                        wr_data_lat    <= s_axil_wdata;
                        s_axil_awready <= 1'b0;
                        s_axil_wready  <= 1'b0;
                        wr_state       <= WR_RESP;
                    end else if (s_axil_awvalid) begin
                        wr_addr_lat    <= s_axil_awaddr;
                        s_axil_awready <= 1'b0;
                        wr_state       <= WR_DATA;
                    end else if (s_axil_wvalid) begin
                        wr_data_lat   <= s_axil_wdata;
                        s_axil_wready <= 1'b0;
                        wr_state      <= WR_ADDR;
                    end
                end
                WR_ADDR: begin
                    s_axil_awready <= 1'b1;
                    if (s_axil_awvalid) begin
                        wr_addr_lat    <= s_axil_awaddr;
                        s_axil_awready <= 1'b0;
                        wr_state       <= WR_RESP;
                    end
                end
                WR_DATA: begin
                    s_axil_wready <= 1'b1;
                    if (s_axil_wvalid) begin
                        wr_data_lat   <= s_axil_wdata;
                        s_axil_wready <= 1'b0;
                        wr_state      <= WR_RESP;
                    end
                end
                WR_RESP: begin
                    // Yazmaç güncelle
                    case (wr_addr_lat)
                        NPU_CTRL_ADDR:       reg_start       <= wr_data_lat[0];
                        NPU_INPUT_ADDR_REG:  reg_input_addr  <= wr_data_lat;
                        NPU_WEIGHT_ADDR_REG: reg_weight_addr <= wr_data_lat;
                        default: ;
                    endcase
                    s_axil_bvalid <= 1'b1;
                    s_axil_bresp  <= 2'b00; // OKAY
                    if (s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        wr_state      <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // ---- AXI4-Lite okuma state machine ----
    typedef enum logic [1:0] {RD_IDLE, RD_ADDR, RD_DATA} axil_rd_state_t;
    axil_rd_state_t rd_state;

    logic [CSR_ADDR_WIDTH-1:0] rd_addr_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state       <= RD_IDLE;
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= 32'h0;
            s_axil_rresp   <= 2'b00;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axil_arready <= 1'b1;
                    if (s_axil_arvalid) begin
                        rd_addr_lat    <= s_axil_araddr;
                        s_axil_arready <= 1'b0;
                        rd_state       <= RD_DATA;
                    end
                end
                RD_DATA: begin
                    s_axil_rvalid <= 1'b1;
                    s_axil_rresp  <= 2'b00;
                    case (rd_addr_lat)
                        NPU_CTRL_ADDR:   s_axil_rdata <= {31'h0, reg_start};
                        NPU_STATUS_ADDR: s_axil_rdata <= {30'h0, fsm_busy, fsm_done};
                        NPU_INPUT_ADDR_REG:  s_axil_rdata <= reg_input_addr;
                        NPU_WEIGHT_ADDR_REG: s_axil_rdata <= reg_weight_addr;
                        NPU_RESULT_ADDR: s_axil_rdata <= {30'h0, fsm_result};
                        default:         s_axil_rdata <= 32'hDEAD_BEEF;
                    endcase
                    if (s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        rd_state      <= RD_IDLE;
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // ---- AXI4 Master okuma kanalı ----
    // TODO: burst okuma FSM'i — implementasyon aşamasında tamamlanacak
    // Aşağıdaki giriş sinyalleri stub FSM'de henüz kullanılmıyor
    // Stub FSM'de henüz kullanılmayan giriş sinyalleri — burst FSM implementasyonunda kullanılacak
    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused_axi = m_axi_arready | (|m_axi_rid) | (|m_axi_rresp)
                      | (|m_axi_rdata[31:8]) | (|m_axi_awready) | m_axi_wready
                      | (|m_axi_bid) | (|m_axi_bresp) | (|mem_rd_len)
                      | (|s_axil_wstrb);
    /* verilator lint_on UNUSEDSIGNAL */

    assign m_axi_arid     = '0;
    assign m_axi_araddr   = mem_rd_req ? mem_rd_addr : '0;
    assign m_axi_arlen    = '0;        // tek beat — burst ileride eklenecek
    assign m_axi_arsize   = 3'b000;   // 1 byte
    assign m_axi_arburst  = 2'b01;    // INCR
    assign m_axi_arvalid  = mem_rd_req;
    assign m_axi_rready   = 1'b1;
    assign mem_rd_valid   = m_axi_rvalid;
    assign mem_rd_data    = m_axi_rdata[7:0];
    assign mem_rd_last    = m_axi_rlast;

    // ---- AXI4 Master yazma kanalı ----
    // TODO: yazma FSM'i — implementasyon aşamasında tamamlanacak
    assign m_axi_awid     = '0;
    assign m_axi_awaddr   = mem_wr_req ? mem_wr_addr : '0;
    assign m_axi_awlen    = 8'h00;
    assign m_axi_awsize   = 3'b010;   // 4 byte
    assign m_axi_awburst  = 2'b01;    // INCR
    assign m_axi_awvalid  = mem_wr_req;
    assign m_axi_wdata    = mem_wr_data;
    assign m_axi_wstrb    = 4'hF;
    assign m_axi_wlast    = 1'b1;
    assign m_axi_wvalid   = mem_wr_req;
    assign m_axi_bready   = 1'b1;
    assign mem_wr_done    = m_axi_bvalid;

    // (Yazma kanalı stub sinyalleri _unused_axi içinde zaten kapsanıyor)

endmodule
