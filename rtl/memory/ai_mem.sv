// ============================================================
// Module : ai_mem
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-06-15
// Desc   : AI_MEM — NPU'nun AXI4 master'ının agirlik blob'u + giris
//          oznitelik vektorunu okudugu on-chip bellek. TAM AXI4 slave
//          (okuma + yazma). Tek-outstanding, tek-beat, 1 cyc gecikme.
//
//          OKUMA: NPU master (arsize=0 byte, arlen=0) okur. Istenen bayt
//          AXI4-uyumlu sekilde adres lane'ine (8*addr[1:0]) yerlestirilir
//          → standart 32-bit master da dogru baytı alir (lane-aligned).
//          YAZMA: AW/W/B kanallari aktif (wstrb bayt-enable). FPGA'da
//          AI_MEM'i UART1 stream / CPU / DMA doldurabilsin diye. wstrb ile
//          bayt-bazli yazma.
//
//          ARALIK KONTROLU: araddr/awaddr [BASE, BASE+SIZE) disindaysa
//          OOB erisim YOK (indeks 0'a kelepcelenir) ve rresp/bresp = SLVERR
//          (2'b10) doner — sessiz cop/tasma engellenir.
//
//          Sentez: senkron-okuma (rdata kayitli) + bayt-enable yazma →
//          FPGA/ASIC BRAM/SRAM (simple-dual-port) inference. INIT_FILE ile
//          $readmemh onyukleme (BRAM init) veya TB hiyerarsik yukleme.
// ============================================================

`timescale 1ns/1ps

module ai_mem #(
    parameter int           ADDR_WIDTH = 32,
    parameter int           DATA_WIDTH = 32,
    parameter int           ID_WIDTH   = 4,
    parameter logic [31:0]  BASE_ADDR  = 32'h0001_0000, // AI_MEM taban adresi
    parameter int           SIZE_BYTES = 30720,         // 30 KB
    parameter string        INIT_FILE  = ""             // onyukleme (bos=yok)
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4 Slave: Okuma adresi kanali ----
    input  logic [ID_WIDTH-1:0]   s_axi_arid,
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [7:0]            s_axi_arlen,
    input  logic [2:0]            s_axi_arsize,
    input  logic [1:0]            s_axi_arburst,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,
    // ---- AXI4 Slave: Okuma veri kanali ----
    output logic [ID_WIDTH-1:0]   s_axi_rid,
    output logic [DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rlast,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // ---- AXI4 Slave: Yazma kanallari ----
    input  logic [ID_WIDTH-1:0]   s_axi_awid,
    input  logic [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [7:0]            s_axi_awlen,
    input  logic [2:0]            s_axi_awsize,
    input  logic [1:0]            s_axi_awburst,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,
    input  logic [DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]            s_axi_wstrb,
    input  logic                  s_axi_wlast,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,
    output logic [ID_WIDTH-1:0]   s_axi_bid,
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready
);

    localparam int          IDXW   = $clog2(SIZE_BYTES);
    localparam logic [1:0]  RESP_OKAY  = 2'b00;
    localparam logic [1:0]  RESP_SLVERR = 2'b10;

    // BRAM-inferable bayt bellegi
    (* ram_style = "block" *)
    logic [7:0] mem [0:SIZE_BYTES-1];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    // ================= OKUMA =================
    // Adres -> ofset (taban cikar) + aralik kontrolu (tasma & alt-tasma)
    logic [ADDR_WIDTH-1:0] ar_off;
    logic                  ar_in_range;
    logic [IDXW-1:0]       ar_idx;
    logic [1:0]            ar_lane;
    assign ar_off      = s_axi_araddr - BASE_ADDR;
    assign ar_in_range = (ar_off < SIZE_BYTES[ADDR_WIDTH-1:0]); // unsigned: alt-tasma da yakalanir
    assign ar_idx      = ar_in_range ? ar_off[IDXW-1:0] : '0;   // OOB indeks engellendi
    assign ar_lane     = ar_off[1:0];

    logic [DATA_WIDTH-1:0] rdata_q;
    logic [ID_WIDTH-1:0]   rid_q;
    logic [1:0]            rresp_q;
    logic                  rvalid_q;

    assign s_axi_arready = !rvalid_q;   // yeni AR yalniz bekleyen yanit yokken

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_q <= 1'b0;
            rdata_q  <= '0;
            rid_q    <= '0;
            rresp_q  <= RESP_OKAY;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                // Bayt, AXI4-uyumlu adres lane'ine (8*addr[1:0]) yerlesir
                rdata_q  <= ({{(DATA_WIDTH-8){1'b0}}, mem[ar_idx]}) << (8*ar_lane);
                rid_q    <= s_axi_arid;
                rresp_q  <= ar_in_range ? RESP_OKAY : RESP_SLVERR;
                rvalid_q <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                rvalid_q <= 1'b0;
            end
        end
    end

    assign s_axi_rvalid = rvalid_q;
    assign s_axi_rdata  = rdata_q;
    assign s_axi_rid    = rid_q;
    assign s_axi_rresp  = rresp_q;
    assign s_axi_rlast  = 1'b1;    // tek-beat (arlen=0)

    // ================= YAZMA =================
    // AW + W birlikte kabul (tek-beat); wstrb bayt-enable; aralik kontrollu.
    logic [ADDR_WIDTH-1:0] aw_off;
    logic                  aw_in_range;
    assign aw_off      = s_axi_awaddr - BASE_ADDR;
    assign aw_in_range = (aw_off < SIZE_BYTES[ADDR_WIDTH-1:0]);

    logic                  bvalid_q;
    logic [1:0]            bresp_q;
    logic [ID_WIDTH-1:0]   bid_q;

    assign s_axi_awready = !bvalid_q;   // bekleyen B yokken kabul
    assign s_axi_wready  = !bvalid_q;

    integer j;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid_q <= 1'b0;
            bresp_q  <= RESP_OKAY;
            bid_q    <= '0;
        end else begin
            if (s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready) begin
                // Bayt-bazli yazma (yalniz aralik icindeki baytlar)
                for (j = 0; j < 4; j++) begin
                    if (s_axi_wstrb[j] && ((aw_off + j[ADDR_WIDTH-1:0]) < SIZE_BYTES[ADDR_WIDTH-1:0]))
                        mem[(aw_off + j[ADDR_WIDTH-1:0]) >> 0] <= s_axi_wdata[8*j +: 8];
                end
                bid_q    <= s_axi_awid;
                bresp_q  <= aw_in_range ? RESP_OKAY : RESP_SLVERR;
                bvalid_q <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                bvalid_q <= 1'b0;
            end
        end
    end

    assign s_axi_bvalid = bvalid_q;
    assign s_axi_bresp  = bresp_q;
    assign s_axi_bid    = bid_q;

    // ---- Kullanilmayan girisler (lint) ----
    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused;
    assign _unused = (|s_axi_arlen) | (|s_axi_arsize) | (|s_axi_arburst)
                   | (|s_axi_awlen) | (|s_axi_awsize) | (|s_axi_awburst)
                   | s_axi_wlast | (|ar_off[ADDR_WIDTH-1:IDXW]);
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
