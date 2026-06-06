// ============================================================
// Module : boot_rom
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Yağmur Miroğlu
// Date   : 2026-05-XX
// Desc   : 1 KB Boot ROM — AXI4-Lite slave, salt okunur.
//          Çekirdek reset sonrası 0x0000_0000 adresinden başlar.
//          ROM içeriği sw/bootloader/ derlenmiş .mem dosyasından yüklenir.
//
//          Boot akışı:
//            1. QSPI Master'ı konfigüre et
//            2. Flash'tan uygulama kodunu oku (256 byte bloklar halinde)
//            3. Kodu IMEM'e (0x0000_1000) kopyala (code-shadowing)
//            4. IMEM başlangıcına jump et
// ============================================================

`timescale 1ns/1ps

module boot_rom #(
    parameter int ROM_SIZE        = 1024,   // 1 KB (256 × 32-bit word)
    parameter int AXIL_ADDR_WIDTH = 12,     // Boot ROM 0x000-0x3FF → 10-bit ofset yeterli
    parameter string ROM_INIT_FILE = "../../sw/bootloader/bootloader.mem"
) (
    input  logic clk,
    input  logic rst_n,

    // ---- AXI4-Lite Slave (salt okunur) ----
    // Yazma kanalları bağlı ama yanıt SLVERR döner (ROM'a yazılamaz)
    input  logic [AXIL_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  logic                       s_axil_awvalid,
    output logic                       s_axil_awready,
    input  logic [31:0]                s_axil_wdata,
    input  logic [3:0]                 s_axil_wstrb,
    input  logic                       s_axil_wvalid,
    output logic                       s_axil_wready,
    output logic [1:0]                 s_axil_bresp,   // 2'b10 = SLVERR (ROM'a yazılamaz)
    output logic                       s_axil_bvalid,
    input  logic                       s_axil_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0] s_axil_araddr,
    input  logic                       s_axil_arvalid,
    output logic                       s_axil_arready,
    output logic [31:0]                s_axil_rdata,
    output logic [1:0]                 s_axil_rresp,
    output logic                       s_axil_rvalid,
    input  logic                       s_axil_rready
);

    // ---- ROM belleği ----
    // Sentezde BROM/LUT olarak gerçeklenir
    // Simülasyonda $readmemh ile başlatılır
    logic [31:0] rom [0:ROM_SIZE/4-1];  // 256 word × 32-bit

    initial begin
        $readmemh(ROM_INIT_FILE, rom);
    end

    // ---- Okuma adresi latch ----
    logic [AXIL_ADDR_WIDTH-1:0] rd_addr_lat;
    logic                        rd_valid;

    // ================================================================
    // TODO: AXI4-Lite okuma FSM
    //
    // Okuma:
    //   ARVALID gelince araddr latch'le → 1 çevrim sonra rdata ver
    //   rdata = rom[araddr[AXIL_ADDR_WIDTH-1:2]]  (4-byte word hizalama)
    //   rresp = 2'b00 (OKAY)
    //
    // Yazma yanıtı (ROM'a yazma girişimi):
    //   AWVALID + WVALID gelince BRESP = 2'b10 (SLVERR) döndür
    //   Gerçekte hiçbir şey yazılmaz
    //
    // Reset davranışı:
    //   rst_n deassert → tüm AXI sinyaller sıfırla
    // ================================================================

    assign s_axil_awready = 1'b0;
    assign s_axil_wready  = 1'b0;
    assign s_axil_bresp   = 2'b10; // SLVERR — ROM'a yazılamaz
    assign s_axil_bvalid  = 1'b0;
    assign s_axil_arready = 1'b0;
    assign s_axil_rdata   = 32'h0;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_addr_lat <= '0;
            rd_valid    <= 1'b0;
        end
    end
    // TODO: AXI okuma mantığı

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused = (|s_axil_awaddr) | (|s_axil_wdata) | (|s_axil_wstrb)
                  | s_axil_bready | s_axil_rready | rd_addr_lat[0] | rd_valid
                  | rom[0][0];
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
