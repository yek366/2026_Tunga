// ============================================================
// Module : npu_subsystem_tb
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-06-15
// Desc   : NPU ALT-SİSTEM sistem-seviye self-checking testbench'i.
//          npu_subsystem = npu_top + ai_mem (gerçek AXI4 bellek modülü).
//          npu_tb'den FARKI: AXI4 slave artık inline BFM değil, gerçek
//          ai_mem.sv modülü; NPU master onu GERÇEK AXI4 üzerinden okur →
//          sistem bağlamında uçtan-uca doğrulama (CPU davranışı: CSR yaz →
//          START → IRQ bekle → RESULT oku → self-check).
//
//          Önyükleme: AI_MEM'e ağırlık blob (taban+0) + giriş (taban+0x4400)
//          hiyerarşik $readmemh ile yüklenir. Golden:
//             python3 draft/ali_salih/npu_golden.py --emit
//          Çalıştırma: repo kökünden (weights/ göreli yol).
// ============================================================

`timescale 1ns/1ps

module npu_subsystem_tb
    import npu_pkg::*;
;
    localparam int CLK_PERIOD  = 10;          // 100 MHz
    localparam int TIMEOUT_CYC = 2_000_000;

    localparam int AXI_ADDR_W = 32, AXI_DATA_W = 32, AXI_ID_W = 4, CSR_ADDR_W = 8;

    // AI_MEM taban + yerleşim (subsystem default AIMEM_BASE ile uyumlu)
    localparam logic [31:0] AIMEM_BASE  = 32'h0001_0000;
    localparam int          AIMEM_SIZE  = 30720;
    localparam logic [31:0] WEIGHT_OFF  = 32'h0000_0000;       // mem iç offset
    localparam logic [31:0] INPUT_OFF   = 32'h0000_4400;       // 17408 > BLOB_BYTES
    localparam logic [31:0] WEIGHT_ADDR = AIMEM_BASE + WEIGHT_OFF;
    localparam logic [31:0] INPUT_ADDR  = AIMEM_BASE + INPUT_OFF;

    // ---- Clock / reset ----
    logic clk = 0, rst_n = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
    end

    // ---- CSR (AXI4-Lite) DUT bağlantıları ----
    logic [CSR_ADDR_W-1:0] s_axil_awaddr;  logic s_axil_awvalid, s_axil_awready;
    logic [31:0] s_axil_wdata; logic [3:0] s_axil_wstrb; logic s_axil_wvalid, s_axil_wready;
    logic [1:0]  s_axil_bresp; logic s_axil_bvalid, s_axil_bready;
    logic [CSR_ADDR_W-1:0] s_axil_araddr; logic s_axil_arvalid, s_axil_arready;
    logic [31:0] s_axil_rdata; logic [1:0] s_axil_rresp; logic s_axil_rvalid, s_axil_rready;
    logic npu_irq;

    npu_subsystem #(
        .AXI_ADDR_WIDTH(AXI_ADDR_W), .AXI_DATA_WIDTH(AXI_DATA_W),
        .AXI_ID_WIDTH(AXI_ID_W), .CSR_ADDR_WIDTH(CSR_ADDR_W),
        .AIMEM_BASE(AIMEM_BASE), .AIMEM_SIZE(AIMEM_SIZE), .AIMEM_INIT("")
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .npu_irq(npu_irq)
    );

    // ---- CSR sürücü varsayılanları ----
    initial begin
        s_axil_awvalid = 0; s_axil_awaddr = '0;
        s_axil_wvalid  = 0; s_axil_wdata = '0; s_axil_wstrb = 4'hF;
        s_axil_bready  = 1;
        s_axil_arvalid = 0; s_axil_araddr = '0;
        s_axil_rready  = 1;
    end

    // ========================================================
    // SVA — sistem protokol kontrolleri (şartname §4)
    // ========================================================
    default disable iff (!rst_n);

    // NPU iç durum (busy/done) + iç AXI4 master hattı (subsystem içi)
    wire fsm_busy_w  = u_dut.u_npu.fsm_busy;
    wire fsm_done_w  = u_dut.u_npu.fsm_done;
    wire ar_valid_w  = u_dut.axi_arvalid;
    wire ar_ready_w  = u_dut.axi_arready;
    wire [31:0] ar_addr_w = u_dut.axi_araddr;
    wire [7:0]  ar_len_w  = u_dut.axi_arlen;
    wire [2:0]  ar_size_w = u_dut.axi_arsize;
    wire [1:0]  ar_burst_w= u_dut.axi_arburst;
    wire r_valid_w   = u_dut.axi_rvalid;
    wire r_ready_w   = u_dut.axi_rready;
    wire [31:0] r_data_w = u_dut.axi_rdata;
    wire r_last_w    = u_dut.axi_rlast;

    // CSR slave: B kanalı kararlılığı
    a_b_hold: assert property (@(posedge clk)
        (s_axil_bvalid && !s_axil_bready) |=> (s_axil_bvalid && $stable(s_axil_bresp)));
    // CSR slave: R kanalı kararlılığı
    a_r_hold: assert property (@(posedge clk)
        (s_axil_rvalid && !s_axil_rready) |=> (s_axil_rvalid && $stable(s_axil_rdata)));
    // Master AR kararlılığı (NPU↔AI_MEM iç hattı)
    a_ar_hold: assert property (@(posedge clk)
        (ar_valid_w && !ar_ready_w) |=> (ar_valid_w && $stable(ar_addr_w)));
    // Master AR sabitleri: tek-beat, byte, INCR
    a_ar_attr: assert property (@(posedge clk)
        ar_valid_w |-> (ar_len_w == 8'h0 && ar_size_w == 3'b000 && ar_burst_w == 2'b01));
    // AI_MEM R kararlılığı: rvalid&&!rready → rvalid + rdata sabit, rlast=1
    a_aimem_r_hold: assert property (@(posedge clk)
        (r_valid_w && !r_ready_w) |=> (r_valid_w && $stable(r_data_w)));
    a_aimem_rlast: assert property (@(posedge clk) r_valid_w |-> r_last_w);
    // IRQ tek-çevrim puls
    a_irq_pulse: assert property (@(posedge clk) npu_irq |=> !npu_irq);
    // BUSY ve DONE aynı anda olamaz
    a_busy_done: assert property (@(posedge clk) !(fsm_busy_w && fsm_done_w));

    // ========================================================
    // CSR erişim task'ları (negedge'de sür)
    // ========================================================
    task automatic axil_write(input logic [7:0] addr, input logic [31:0] data);
        @(negedge clk);
        s_axil_awaddr = addr; s_axil_awvalid = 1;
        s_axil_wdata  = data; s_axil_wvalid  = 1; s_axil_wstrb = 4'hF;
        do @(posedge clk); while (!(s_axil_awready && s_axil_wready));
        @(negedge clk); s_axil_awvalid = 0; s_axil_wvalid = 0;
        do @(posedge clk); while (!s_axil_bvalid);
        if (s_axil_bresp !== 2'b00) $error("[AXIL] yazma resp=%b @0x%02X", s_axil_bresp, addr);
    endtask

    task automatic axil_read(input logic [7:0] addr, output logic [31:0] data);
        @(negedge clk);
        s_axil_araddr = addr; s_axil_arvalid = 1;
        do @(posedge clk); while (!s_axil_arready);
        @(negedge clk); s_axil_arvalid = 0;
        do @(posedge clk); while (!s_axil_rvalid);
        data = s_axil_rdata;
        if (s_axil_rresp !== 2'b00) $error("[AXIL] okuma resp=%b @0x%02X", s_axil_rresp, addr);
    endtask

    // ========================================================
    // Golden referans verileri
    // ========================================================
    logic [7:0]         exp_dwout  [0:FC_FLAT-1];
    logic signed [7:0]  exp_logits [0:FC_OUTPUTS-1];
    integer             exp_class;

    task automatic load_expected_class;
        integer fd, rc;
        fd = $fopen("weights/npu_expected_class.txt", "r");
        if (fd == 0) $fatal(1, "[FATAL] npu_expected_class.txt yok (golden --emit calistir)");
        rc = $fscanf(fd, "%d", exp_class);
        if (rc != 1) $fatal(1, "[FATAL] beklenen sinif okunamadi");
        $fclose(fd);
    endtask

    integer pass_cnt = 0, fail_cnt = 0;
    logic [31:0] rd;
    integer i, mism;

    task automatic check(input string nm, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin $display("[PASS] %s = 0x%08X", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s got=0x%08X exp=0x%08X", nm, got, exp); fail_cnt++; end
    endtask

    initial begin
        // AI_MEM'i sıfırla + golden blob/giriş yükle (hiyerarşik)
        for (i = 0; i < AIMEM_SIZE; i++) u_dut.u_aimem.mem[i] = 8'h00;
        $readmemh("weights/npu_weights.mem", u_dut.u_aimem.mem, WEIGHT_OFF[$clog2(AIMEM_SIZE)-1:0]);
        $readmemh("weights/npu_input.mem",   u_dut.u_aimem.mem, INPUT_OFF[$clog2(AIMEM_SIZE)-1:0]);
        $readmemh("weights/npu_dwout.mem",   exp_dwout);
        $readmemh("weights/npu_logits.mem",  exp_logits);
        load_expected_class();

        @(posedge rst_n);
        repeat (5) @(posedge clk);
        $display("=== TUNGA NPU ALT-SISTEM Self-Checking TB === (golden sinif=%0d)", exp_class);
        $display("    AI_MEM taban=0x%08X  WEIGHT@0x%08X  INPUT@0x%08X",
                 AIMEM_BASE, WEIGHT_ADDR, INPUT_ADDR);

        // Reset durumu
        axil_read(8'h04, rd);
        check("NPU_STATUS reset", rd, 32'h0);

        // Adresleri programla (gerçek AI_MEM taban adresleriyle)
        axil_write(8'h08, INPUT_ADDR);
        axil_write(8'h0C, WEIGHT_ADDR);
        axil_read(8'h08, rd); check("NPU_INPUT_ADDR",  rd, INPUT_ADDR);
        axil_read(8'h0C, rd); check("NPU_WEIGHT_ADDR", rd, WEIGHT_ADDR);

        // START
        axil_write(8'h00, 32'h1);
        axil_read(8'h04, rd);
        if (rd[1]) $display("[PASS] BUSY set"); else $display("[WARN] BUSY gorulmedi");

        // IRQ bekle
        $display("[INFO] cikarim... IRQ bekleniyor (NPU AI_MEM'i AXI4 ile okuyor)");
        fork
            begin @(posedge npu_irq); $display("[PASS] IRQ alindi"); pass_cnt++; end
            begin repeat (TIMEOUT_CYC) @(posedge clk);
                  $fatal(1, "[TIMEOUT] IRQ %0d cyc'de gelmedi", TIMEOUT_CYC); end
        join_any
        disable fork;

        // Sonuç
        axil_read(8'h10, rd);
        $display("[INFO] NPU_RESULT = %0d (%s)", rd[1:0],
            rd[1:0]==0?"silence":rd[1:0]==1?"unknown":rd[1:0]==2?"yes":"no");
        check("NPU sinif == golden", {30'h0, rd[1:0]}, exp_class[31:0]);

        axil_read(8'h04, rd);
        check("DONE biti", {31'h0, rd[0]}, 32'h1);
        check("BUSY biti temiz", {31'h0, rd[1]}, 32'h0);

        // DERİN kontrol 1: FC logit'leri golden ile bit-bit
        mism = 0;
        for (i = 0; i < FC_OUTPUTS; i++)
            if (u_dut.u_npu.u_fc.logits[i] !== exp_logits[i]) begin
                mism++;
                $display("[FAIL] logit[%0d] got=%0d exp=%0d", i, u_dut.u_npu.u_fc.logits[i], exp_logits[i]);
            end
        if (mism == 0) begin
            $display("[PASS] FC logit'leri golden ile bit-exact (4 noron)"); pass_cnt++;
        end else begin
            $display("[FAIL] FC logit'lerinde %0d uyusmazlik", mism); fail_cnt++;
        end

        // DERİN kontrol 2: DW çıkışı golden ile bit-bit
        mism = 0;
        for (i = 0; i < FC_FLAT; i++)
            if (u_dut.u_npu.u_lbuf.mem[i] !== $signed(exp_dwout[i])) begin
                mism++;
                if (mism <= 10)
                    $display("[FAIL] DWout[%0d] got=%0d exp=%0d", i,
                             u_dut.u_npu.u_lbuf.mem[i], $signed(exp_dwout[i]));
            end
        if (mism == 0) begin
            $display("[PASS] DW cikisi golden ile bit-exact (4000 eleman)"); pass_cnt++;
        end else begin
            $display("[FAIL] DW cikisinda %0d/%0d uyusmazlik", mism, FC_FLAT); fail_cnt++;
        end

        $display("=========================================");
        $display("TUNGA NPU ALT-SISTEM TB:  PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("  >>> TUM TESTLER GECTI <<<");
        else               $display("  >>> %0d TEST BASARISIZ <<<", fail_cnt);
        $display("=========================================");
        if (fail_cnt != 0) $fatal(1, "NPU ALT-SISTEM TB FAIL");
        $finish;
    end

endmodule
