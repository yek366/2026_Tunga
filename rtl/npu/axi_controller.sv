// ============================================================
// Module : axi_controller
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Desc   : NPU AXI denetleyicisi.
//          - AXI4-Lite slave (CSR): CPU'dan NPU_CTRL/STATUS/INPUT_ADDR/
//            WEIGHT_ADDR/RESULT erişimi.
//          - AXI4 master okuma motoru: AI_MEM'den bayt akışı (tek-beat,
//            tam AR/R handshake). FSM'e (rd_byte, rd_valid, rd_done) sunar.
//          NOT: tek-beat (AxLEN=0) doğru ama yavaş; INCR burst sonraki
//          optimizasyon (rd_len zaten beat sayısını taşıyor).
//          Yazma kanalı kullanılmaz (sonuç CSR'dan okunur) → boşta.
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

    // ---- AXI4 Master (AI_MEM erişimi) ----
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

    // ---- CSR → FSM ----
    output logic        csr_start,
    output logic [31:0] csr_input_addr,
    output logic [31:0] csr_weight_addr,

    // ---- FSM → CSR ----
    input  logic        fsm_done,
    input  logic        fsm_busy,
    input  logic [1:0]  fsm_result,

    // ---- FSM ↔ AXI okuma motoru ----
    input  logic        rd_start,           // puls: okuma başlat
    input  logic [31:0] rd_addr,            // başlangıç bayt adresi
    input  logic [15:0] rd_len,             // beat sayısı - 1
    output logic [7:0]  rd_byte,            // okunan bayt
    output logic        rd_valid,           // beat geçerli (1 cyc)
    output logic        rd_busy,
    output logic        rd_done             // tüm beat'ler tamam (puls)
);

    // ========================================================
    // CSR adres sabitleri
    // ========================================================
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_CTRL_ADDR       = 8'h00;
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_STATUS_ADDR     = 8'h04;
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_INPUT_ADDR_REG  = 8'h08;
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_WEIGHT_ADDR_REG = 8'h0C;
    localparam logic [CSR_ADDR_WIDTH-1:0] NPU_RESULT_ADDR     = 8'h10;

    logic        reg_start;
    logic [31:0] reg_input_addr;
    logic [31:0] reg_weight_addr;

    assign csr_start       = reg_start;
    assign csr_input_addr  = reg_input_addr;
    assign csr_weight_addr = reg_weight_addr;

    // ---- AXI4-Lite YAZMA kanalı (combinational ready) ----
    // Master aw+w'yi birlikte sunar (CV32E40P köprüsü / TB). ready'ler idle'da
    // KOMBİNASYONEL yüksek → back-to-back transferlerde "registered ready 0'a
    // ezilme" hatası yok; master ready=1'i aynı çevrimde gözlemler.
    typedef enum logic [0:0] {W_IDLE, W_RESP} axil_wr_state_t;
    axil_wr_state_t wr_state;

    assign s_axil_awready = (wr_state == W_IDLE);
    assign s_axil_wready  = (wr_state == W_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state        <= W_IDLE;
            reg_start       <= 1'b0;
            reg_input_addr  <= 32'h0;
            reg_weight_addr <= 32'h0;
            s_axil_bvalid   <= 1'b0;
            s_axil_bresp    <= 2'b00;
        end else begin
            if (reg_start) reg_start <= 1'b0;   // START tek-çevrim puls
            case (wr_state)
                W_IDLE: begin
                    if (s_axil_awvalid && s_axil_wvalid) begin
                        case (s_axil_awaddr)
                            NPU_CTRL_ADDR:       reg_start       <= s_axil_wdata[0];
                            NPU_INPUT_ADDR_REG:  reg_input_addr  <= s_axil_wdata;
                            NPU_WEIGHT_ADDR_REG: reg_weight_addr <= s_axil_wdata;
                            default: ;
                        endcase
                        s_axil_bvalid <= 1'b1;
                        s_axil_bresp  <= 2'b00;
                        wr_state      <= W_RESP;
                    end
                end
                W_RESP: begin
                    if (s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        wr_state      <= W_IDLE;
                    end
                end
            endcase
        end
    end

    // ---- AXI4-Lite OKUMA kanalı (combinational ready) ----
    typedef enum logic [0:0] {R_IDLE, R_RESP} axil_rd_state_t;
    axil_rd_state_t rd_state_csr;

    assign s_axil_arready = (rd_state_csr == R_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state_csr  <= R_IDLE;
            s_axil_rvalid <= 1'b0;
            s_axil_rdata  <= 32'h0;
            s_axil_rresp  <= 2'b00;
        end else begin
            case (rd_state_csr)
                R_IDLE: begin
                    if (s_axil_arvalid) begin
                        s_axil_rresp <= 2'b00;
                        case (s_axil_araddr)
                            NPU_CTRL_ADDR:       s_axil_rdata <= {31'h0, reg_start};
                            NPU_STATUS_ADDR:     s_axil_rdata <= {30'h0, fsm_busy, fsm_done};
                            NPU_INPUT_ADDR_REG:  s_axil_rdata <= reg_input_addr;
                            NPU_WEIGHT_ADDR_REG: s_axil_rdata <= reg_weight_addr;
                            NPU_RESULT_ADDR:     s_axil_rdata <= {30'h0, fsm_result};
                            default:             s_axil_rdata <= 32'hDEAD_BEEF;
                        endcase
                        s_axil_rvalid <= 1'b1;
                        rd_state_csr  <= R_RESP;
                    end
                end
                R_RESP: begin
                    if (s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        rd_state_csr  <= R_IDLE;
                    end
                end
            endcase
        end
    end

    // ========================================================
    // AXI4 Master okuma motoru (tek-beat, tam handshake)
    // ========================================================
    typedef enum logic [1:0] {M_IDLE, M_AR, M_DATA} rd_eng_state_t;
    rd_eng_state_t r_state;

    logic [31:0] r_base;
    logic [16:0] r_total;   // beat sayısı (rd_len+1, 0..65536)
    logic [16:0] r_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= M_IDLE;
            r_base  <= 32'h0;
            r_total <= 17'h0;
            r_cnt   <= 17'h0;
            rd_done <= 1'b0;
        end else begin
            rd_done <= 1'b0;
            case (r_state)
                M_IDLE: begin
                    if (rd_start) begin
                        r_base  <= rd_addr;
                        r_total <= {1'b0, rd_len} + 17'h1;
                        r_cnt   <= 17'h0;
                        r_state <= M_AR;
                    end
                end
                M_AR: begin
                    if (m_axi_arready) r_state <= M_DATA;
                end
                M_DATA: begin
                    if (m_axi_rvalid) begin
                        if (r_cnt + 17'h1 == r_total) begin
                            rd_done <= 1'b1;
                            r_state <= M_IDLE;
                        end else begin
                            r_cnt   <= r_cnt + 17'h1;
                            r_state <= M_AR;
                        end
                    end
                end
                default: r_state <= M_IDLE;
            endcase
        end
    end

    assign rd_busy  = (r_state != M_IDLE);
    assign rd_valid = (r_state == M_DATA) && m_axi_rvalid;
    // AXI4-uyumlu: bayt, adres lane'inde (8*addr[1:0]) gelir → dogru lane'den al.
    // arsize=0 dar transfer; lane = araddr[1:0] (asagidaki AR ile ayni ifade).
    logic [31:0] rd_cur_addr;
    logic [1:0]  rd_lane;
    assign rd_cur_addr = r_base + {15'h0, r_cnt};   // m_axi_araddr ile ayni
    assign rd_lane     = rd_cur_addr[1:0];
    assign rd_byte     = m_axi_rdata[8*rd_lane +: 8];

    // AR kanalı
    assign m_axi_arid    = '0;
    assign m_axi_araddr  = r_base + {15'h0, r_cnt};
    assign m_axi_arlen   = 8'h00;     // tek-beat
    assign m_axi_arsize  = 3'b000;    // 1 bayt
    assign m_axi_arburst = 2'b01;     // INCR
    assign m_axi_arvalid = (r_state == M_AR);
    assign m_axi_rready  = (r_state == M_DATA);

    // Yazma kanalı kullanılmıyor — boşta tut
    assign m_axi_awid    = '0;
    assign m_axi_awaddr  = '0;
    assign m_axi_awlen   = '0;
    assign m_axi_awsize  = 3'b000;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = 1'b0;
    assign m_axi_wdata   = '0;
    assign m_axi_wstrb   = '0;
    assign m_axi_wlast   = 1'b0;
    assign m_axi_wvalid  = 1'b0;
    assign m_axi_bready  = 1'b1;

    // Kullanılmayan giriş sinyalleri (lint)
    logic _unused;
    assign _unused = (|s_axil_wstrb) | (|m_axi_bid) | (|m_axi_bresp) | m_axi_bvalid
                   | (|m_axi_rid) | (|m_axi_rresp) | m_axi_rlast | (|m_axi_rdata[31:8])
                   | m_axi_awready | m_axi_wready;

endmodule
