// ============================================================
// Module : ai_mem
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-06-15
// Desc   : AI_MEM — NPU'nun AXI4 master'ının ağırlık blob'u + giriş
//          öznitelik vektörünü okuduğu on-chip bellek. AXI4 SALT-OKUNUR
//          slave (AR/R kanalları). Tek-outstanding, tek-beat, 1 çevrim
//          gecikme; NPU master'ı (arsize=0 byte, arlen=0) ile birebir.
//
//          Bayt erişim sözleşmesi: NPU master arsize=0 ile bayt ister ve
//          rdata[7:0]'ı tüketir. AI_MEM istenen baytı [7:0] hattına koyar
//          (adres LSB lane mux YOK) — npu_tb BFM'iyle aynı, NPU bit-exact
//          kalır.
//
//          Sentez: senkron-okuma (rdata kayıtlı) → FPGA/ASIC BRAM/SRAM
//          inference. INIT_FILE ile $readmemh önyükleme (BRAM init) veya
//          TB'den hiyerarşik mem[] yüklemesi.
//
//          Yazma yolu (UART1 stream / DMA master) HENÜZ YOK — AI_MEM şu an
//          salt-okunur; yazma master'ı entegre olunca AW/W/B eklenecek.
// ============================================================

`timescale 1ns/1ps

module ai_mem #(
    parameter int           ADDR_WIDTH = 32,
    parameter int           DATA_WIDTH = 32,
    parameter int           ID_WIDTH   = 4,
    parameter logic [31:0]  BASE_ADDR  = 32'h0001_0000, // AI_MEM taban adresi
    parameter int           SIZE_BYTES = 30720,         // 30 KB
    parameter string        INIT_FILE  = ""             // önyükleme (boş=yok)
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4 Slave: Okuma adresi kanalı ----
    input  logic [ID_WIDTH-1:0]   s_axi_arid,
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [7:0]            s_axi_arlen,
    input  logic [2:0]            s_axi_arsize,
    input  logic [1:0]            s_axi_arburst,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,
    // ---- AXI4 Slave: Okuma veri kanalı ----
    output logic [ID_WIDTH-1:0]   s_axi_rid,
    output logic [DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rlast,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // ---- AXI4 Slave: Yazma kanalları (şu an desteklenmiyor) ----
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

    localparam int IDXW = $clog2(SIZE_BYTES);

    // BRAM-inferable bayt belleği
    (* ram_style = "block" *)
    logic [7:0] mem [0:SIZE_BYTES-1];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    // ---- Adres → bellek indeksi (taban çıkar) ----
    logic [ADDR_WIDTH-1:0] ar_off;
    logic [IDXW-1:0]       ar_idx;
    assign ar_off = s_axi_araddr - BASE_ADDR;
    assign ar_idx = ar_off[IDXW-1:0];

    // ---- Tek-outstanding, tek-beat okuma slave (senkron okuma) ----
    logic [DATA_WIDTH-1:0] rdata_q;
    logic [ID_WIDTH-1:0]   rid_q;
    logic                  rvalid_q;

    // Yeni AR yalnızca bekleyen yanıt yokken kabul edilir → rdata kararlı kalır
    assign s_axi_arready = !rvalid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_q <= 1'b0;
            rdata_q  <= '0;
            rid_q    <= '0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                // Senkron-okuma: bellek çıkışı kayıtlanır (BRAM çıkış reg'i)
                rdata_q  <= {{(DATA_WIDTH-8){1'b0}}, mem[ar_idx]};
                rid_q    <= s_axi_arid;
                rvalid_q <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                rvalid_q <= 1'b0;
            end
        end
    end

    assign s_axi_rvalid = rvalid_q;
    assign s_axi_rdata  = rdata_q;
    assign s_axi_rid    = rid_q;
    assign s_axi_rresp  = 2'b00;   // OKAY
    assign s_axi_rlast  = 1'b1;    // tek-beat (arlen=0)

    // ---- Yazma kanalı: AI_MEM salt-okunur — hiçbir yazma kabul edilmez ----
    assign s_axi_awready = 1'b0;
    assign s_axi_wready  = 1'b0;
    assign s_axi_bvalid  = 1'b0;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bid     = '0;

    // ---- Kullanılmayan girişler (lint) ----
    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused;
    assign _unused = (|s_axi_arlen) | (|s_axi_arsize) | (|s_axi_arburst)
                   | (|s_axi_awid)  | (|s_axi_awaddr) | (|s_axi_awlen)
                   | (|s_axi_awsize)| (|s_axi_awburst)| s_axi_awvalid
                   | (|s_axi_wdata) | (|s_axi_wstrb)  | s_axi_wlast | s_axi_wvalid
                   | s_axi_bready   | (|ar_off[ADDR_WIDTH-1:IDXW]);
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
