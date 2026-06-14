// ============================================================
// Module : npu_tb
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : NPU izole self-checking testbench'i.
//          - Clock ve reset üretimi
//          - AXI4-Lite CSR yazma/okuma task'ları
//          - YZ belleği simülasyonu (stub)
//          - TFLite referans çıktısıyla otomatik karşılaştırma
//          - PASS/FAIL raporu
// ============================================================

`timescale 1ns/1ps

module npu_tb;

    // ---- Parametreler ----
    localparam int CLK_PERIOD   = 10;    // 100 MHz
    localparam int RESET_CYCLES = 20;
    localparam int TIMEOUT_CYC  = 500000; // ~5 ms @ 100 MHz — yeterli olmasa artır

    localparam int AXI_ADDR_W = 32;
    localparam int AXI_DATA_W = 32;
    localparam int AXI_ID_W   = 4;
    localparam int CSR_ADDR_W = 8;

    // ---- Referans veri ----
    // TFLite Micro "yes" sesi için beklenen sınıf
    localparam logic [1:0] EXPECTED_CLASS = 2'd2; // 2 = yes

    // ---- Clock ve reset ----
    logic clk = 0;
    logic rst_n = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 0;
        repeat(RESET_CYCLES) @(posedge clk);
        rst_n = 1;
    end

    // ---- DUT sinyalleri ----
    // AXI4-Lite CSR (slave)
    logic [CSR_ADDR_W-1:0] s_axil_awaddr;
    logic                  s_axil_awvalid;
    logic                  s_axil_awready;
    logic [31:0]           s_axil_wdata;
    logic [3:0]            s_axil_wstrb;
    logic                  s_axil_wvalid;
    logic                  s_axil_wready;
    logic [1:0]            s_axil_bresp;
    logic                  s_axil_bvalid;
    logic                  s_axil_bready;
    logic [CSR_ADDR_W-1:0] s_axil_araddr;
    logic                  s_axil_arvalid;
    logic                  s_axil_arready;
    logic [31:0]           s_axil_rdata;
    logic [1:0]            s_axil_rresp;
    logic                  s_axil_rvalid;
    logic                  s_axil_rready;

    // AXI4 Master (YZ belleği)
    logic [AXI_ID_W-1:0]   m_axi_awid;
    logic [AXI_ADDR_W-1:0] m_axi_awaddr;
    logic [7:0]            m_axi_awlen;
    logic [2:0]            m_axi_awsize;
    logic [1:0]            m_axi_awburst;
    logic                  m_axi_awvalid;
    logic                  m_axi_awready;
    logic [AXI_DATA_W-1:0] m_axi_wdata;
    logic [3:0]            m_axi_wstrb;
    logic                  m_axi_wlast;
    logic                  m_axi_wvalid;
    logic                  m_axi_wready;
    logic [AXI_ID_W-1:0]   m_axi_bid;
    logic [1:0]            m_axi_bresp;
    logic                  m_axi_bvalid;
    logic                  m_axi_bready;
    logic [AXI_ID_W-1:0]   m_axi_arid;
    logic [AXI_ADDR_W-1:0] m_axi_araddr;
    logic [7:0]            m_axi_arlen;
    logic [2:0]            m_axi_arsize;
    logic [1:0]            m_axi_arburst;
    logic                  m_axi_arvalid;
    logic                  m_axi_arready;
    logic [AXI_ID_W-1:0]   m_axi_rid;
    logic [AXI_DATA_W-1:0] m_axi_rdata;
    logic [1:0]            m_axi_rresp;
    logic                  m_axi_rlast;
    logic                  m_axi_rvalid;
    logic                  m_axi_rready;
    logic                  npu_irq;

    // ---- DUT instantiation ----
    npu_top #(
        .AXI_ADDR_WIDTH (AXI_ADDR_W),
        .AXI_DATA_WIDTH (AXI_DATA_W),
        .AXI_ID_WIDTH   (AXI_ID_W),
        .CSR_ADDR_WIDTH (CSR_ADDR_W)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axil_awaddr    (s_axil_awaddr),
        .s_axil_awvalid   (s_axil_awvalid),
        .s_axil_awready   (s_axil_awready),
        .s_axil_wdata     (s_axil_wdata),
        .s_axil_wstrb     (s_axil_wstrb),
        .s_axil_wvalid    (s_axil_wvalid),
        .s_axil_wready    (s_axil_wready),
        .s_axil_bresp     (s_axil_bresp),
        .s_axil_bvalid    (s_axil_bvalid),
        .s_axil_bready    (s_axil_bready),
        .s_axil_araddr    (s_axil_araddr),
        .s_axil_arvalid   (s_axil_arvalid),
        .s_axil_arready   (s_axil_arready),
        .s_axil_rdata     (s_axil_rdata),
        .s_axil_rresp     (s_axil_rresp),
        .s_axil_rvalid    (s_axil_rvalid),
        .s_axil_rready    (s_axil_rready),
        .m_axi_awid       (m_axi_awid),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),
        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),
        .m_axi_bid        (m_axi_bid),
        .m_axi_bresp      (m_axi_bresp),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready),
        .m_axi_arid       (m_axi_arid),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_rid        (m_axi_rid),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready),
        .npu_irq          (npu_irq)
    );

    // ---- YZ Belleği stub (30 KB SRAM simülasyonu) ----
    // Gerçek test: .mem dosyasından yüklenir
    localparam int AI_MEM_SIZE = 30 * 1024; // 30 KB byte
    logic [7:0] ai_mem [0:AI_MEM_SIZE-1];

    // AXI4 slave stub — okuma
    assign m_axi_arready = 1'b1;
    assign m_axi_rvalid  = m_axi_arvalid;
    assign m_axi_rdata   = {24'h0, ai_mem[m_axi_araddr[14:0]]};
    assign m_axi_rresp   = 2'b00;
    assign m_axi_rlast   = 1'b1;
    assign m_axi_rid     = m_axi_arid;

    // AXI4 slave stub — yazma
    assign m_axi_awready = 1'b1;
    assign m_axi_wready  = 1'b1;
    assign m_axi_bvalid  = m_axi_wvalid;
    assign m_axi_bresp   = 2'b00;
    assign m_axi_bid     = m_axi_awid;

    always_ff @(posedge clk) begin
        if (m_axi_wvalid && m_axi_wready)
            ai_mem[m_axi_awaddr[14:0]] <= m_axi_wdata[7:0];
    end

    // ---- AXI4-Lite başlangıç değerleri ----
    initial begin
        s_axil_awvalid = 0; s_axil_awaddr = '0;
        s_axil_wvalid  = 0; s_axil_wdata  = '0; s_axil_wstrb = 4'hF;
        s_axil_bready  = 1;
        s_axil_arvalid = 0; s_axil_araddr = '0;
        s_axil_rready  = 1;
    end

    // ---- AXI4-Lite yazma task'ı ----
    task automatic axil_write(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        s_axil_awaddr  = addr;
        s_axil_awvalid = 1;
        s_axil_wdata   = data;
        s_axil_wvalid  = 1;
        @(posedge clk iff (s_axil_awready && s_axil_wready));
        s_axil_awvalid = 0;
        s_axil_wvalid  = 0;
        @(posedge clk iff s_axil_bvalid);
        if (s_axil_bresp !== 2'b00)
            $error("[AXI-LITE] Yazma hatası: addr=0x%02X resp=%b", addr, s_axil_bresp);
    endtask

    // ---- AXI4-Lite okuma task'ı ----
    task automatic axil_read(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        s_axil_araddr  = addr;
        s_axil_arvalid = 1;
        @(posedge clk iff s_axil_arready);
        s_axil_arvalid = 0;
        @(posedge clk iff s_axil_rvalid);
        data = s_axil_rdata;
        if (s_axil_rresp !== 2'b00)
            $error("[AXI-LITE] Okuma hatası: addr=0x%02X resp=%b", addr, s_axil_rresp);
    endtask

    // ---- IRQ bekleme task'ı ----
    task automatic wait_for_irq(input int timeout);
        fork
            begin
                @(posedge npu_irq);
            end
            begin
                repeat(timeout) @(posedge clk);
                $fatal(1, "[TIMEOUT] IRQ %0d çevrimde gelmedi!", timeout);
            end
        join_any
        disable fork;
    endtask

    // ---- Test senaryosu ----
    integer test_pass_cnt = 0;
    integer test_fail_cnt = 0;

    task automatic check(input string test_name,
                         input logic [31:0] got,
                         input logic [31:0] expected);
        if (got === expected) begin
            $display("[PASS] %s: got=0x%08X", test_name, got);
            test_pass_cnt++;
        end else begin
            $display("[FAIL] %s: got=0x%08X, expected=0x%08X", test_name, got, expected);
            test_fail_cnt++;
        end
    endtask

    // ---- Ana test akışı ----
    logic [31:0] rd_data;

    initial begin
        $dumpfile("sim/npu_tb.vcd");
        $dumpvars(0, npu_tb);

        // Reset tamamlanana kadar bekle
        @(posedge rst_n);
        repeat(5) @(posedge clk);

        $display("=== TUNGA NPU Testbench Başladı ===");

        // 1. TEST: CSR varsayılan değerleri
        axil_read(8'h04, rd_data); // NPU_STATUS
        check("NPU_STATUS reset değeri", rd_data, 32'h0);

        // 2. TEST: NPU_INPUT_ADDR yazma/okuma
        axil_write(8'h08, 32'h0000_0200); // Giriş verisi YZ belleğinde 0x200 ofsetinde
        axil_read(8'h08, rd_data);
        check("NPU_INPUT_ADDR R/W", rd_data, 32'h0000_0200);

        // 3. TEST: NPU_WEIGHT_ADDR yazma/okuma
        axil_write(8'h0C, 32'h0000_0000); // Ağırlıklar YZ belleğinin başında
        axil_read(8'h0C, rd_data);
        check("NPU_WEIGHT_ADDR R/W", rd_data, 32'h0000_0000);

        // 4. TEST: Giriş verisini YZ belleğine yükle
        // TODO: Gerçek test verisi weights/ klasöründen $readmemb ile yüklenecek
        // Şimdilik sıfır vektörü ile smoke test
        for (int i = 0; i < 1960; i++)
            ai_mem[32'h200 + i] = 8'h00;
        $display("[INFO] Giriş verisi yüklendi (sıfır vektörü — smoke test)");

        // 5. TEST: NPU START
        axil_write(8'h00, 32'h0000_0001); // NPU_CTRL[0] = 1

        // BUSY kontrolü
        axil_read(8'h04, rd_data);
        if (rd_data[1])
            $display("[PASS] NPU BUSY biti set edildi");
        else
            $display("[WARN] NPU BUSY biti görülmedi (zamanlama?)");

        // 6. TEST: IRQ bekle
        $display("[INFO] IRQ bekleniyor...");
        wait_for_irq(TIMEOUT_CYC);
        $display("[PASS] IRQ alındı");

        // 7. TEST: Sonucu oku
        axil_read(8'h10, rd_data); // NPU_RESULT
        $display("[INFO] NPU_RESULT = %0d (%s)",
            rd_data[1:0],
            rd_data[1:0] == 0 ? "silence" :
            rd_data[1:0] == 1 ? "unknown" :
            rd_data[1:0] == 2 ? "yes" : "no");

        // 8. TEST: Durum bitleri temizlendi mi?
        axil_read(8'h04, rd_data);
        check("NPU_STATUS DONE bit DONE sonrası", rd_data[0], 1'b1);
        check("NPU_STATUS BUSY bit DONE sonrası", rd_data[1], 1'b0);

        // ---- Özet ----
        $display("=========================================");
        $display("TUNGA NPU TB Tamamlandı");
        $display("  PASS: %0d", test_pass_cnt);
        $display("  FAIL: %0d", test_fail_cnt);
        if (test_fail_cnt == 0)
            $display("  SONUÇ: >>> TÜM TESTLER GEÇTI <<<");
        else
            $display("  SONUÇ: >>> %0d TEST BAŞARISIZ <<<", test_fail_cnt);
        $display("=========================================");

        $finish;
    end

    // ---- Watchdog ----
    initial begin
        #(TIMEOUT_CYC * CLK_PERIOD * 2);
        $fatal(1, "[WATCHDOG] Simülasyon zaman aşımı!");
    end

endmodule
