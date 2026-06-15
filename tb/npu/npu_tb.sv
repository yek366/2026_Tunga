// ============================================================
// Module : npu_tb
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-06-14
// Desc   : NPU izole SELF-CHECKING testbench'i (golden referansa karşı).
//          - AI_MEM AXI4 slave BFM (NPU master okumalarına handshake yanıtı)
//          - Golden blob ($readmemh): weights/npu_weights.mem + npu_input.mem
//          - CSR ile WEIGHT/INPUT adres + START; IRQ bekle; NPU_RESULT oku
//          - Sınıf, golden beklenen sınıfla (npu_expected_class.txt) karşılaştırılır
//          - DERİN kontrol: DW çıkışı (local_buffer) golden npu_dwout.mem ile
//            bit-bit karşılaştırılır → quant/conv hattı doğrulanır
//          Vektörler: python3 draft/ali_salih/npu_golden.py --emit
//          Çalıştırma: repo kökünden (weights/ göreli yol)
// ============================================================

`timescale 1ns/1ps

module npu_tb
    import npu_pkg::*;
;
    localparam int CLK_PERIOD  = 10;       // 100 MHz
    localparam int TIMEOUT_CYC = 2_000_000;

    localparam int AXI_ADDR_W = 32, AXI_DATA_W = 32, AXI_ID_W = 4, CSR_ADDR_W = 8;

    // AI_MEM yerleşimi (golden ile uyumlu)
    localparam logic [31:0] WEIGHT_BASE = 32'h0000_0000;
    localparam logic [31:0] INPUT_BASE  = 32'h0000_4400;  // 17408 > BLOB_BYTES(16756)

    // ---- Clock / reset ----
    logic clk = 0, rst_n = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
    end

    // ---- DUT sinyalleri ----
    logic [CSR_ADDR_W-1:0] s_axil_awaddr;  logic s_axil_awvalid, s_axil_awready;
    logic [31:0] s_axil_wdata; logic [3:0] s_axil_wstrb; logic s_axil_wvalid, s_axil_wready;
    logic [1:0]  s_axil_bresp; logic s_axil_bvalid, s_axil_bready;
    logic [CSR_ADDR_W-1:0] s_axil_araddr; logic s_axil_arvalid, s_axil_arready;
    logic [31:0] s_axil_rdata; logic [1:0] s_axil_rresp; logic s_axil_rvalid, s_axil_rready;

    logic [AXI_ID_W-1:0]   m_axi_awid;   logic [AXI_ADDR_W-1:0] m_axi_awaddr;
    logic [7:0] m_axi_awlen; logic [2:0] m_axi_awsize; logic [1:0] m_axi_awburst;
    logic m_axi_awvalid, m_axi_awready;
    logic [AXI_DATA_W-1:0] m_axi_wdata; logic [3:0] m_axi_wstrb; logic m_axi_wlast, m_axi_wvalid, m_axi_wready;
    logic [AXI_ID_W-1:0] m_axi_bid; logic [1:0] m_axi_bresp; logic m_axi_bvalid, m_axi_bready;
    logic [AXI_ID_W-1:0]   m_axi_arid;   logic [AXI_ADDR_W-1:0] m_axi_araddr;
    logic [7:0] m_axi_arlen; logic [2:0] m_axi_arsize; logic [1:0] m_axi_arburst;
    logic m_axi_arvalid, m_axi_arready;
    logic [AXI_ID_W-1:0] m_axi_rid; logic [AXI_DATA_W-1:0] m_axi_rdata;
    logic [1:0] m_axi_rresp; logic m_axi_rlast, m_axi_rvalid, m_axi_rready;
    logic npu_irq;

    npu_top #(
        .AXI_ADDR_WIDTH(AXI_ADDR_W), .AXI_DATA_WIDTH(AXI_DATA_W),
        .AXI_ID_WIDTH(AXI_ID_W), .CSR_ADDR_WIDTH(CSR_ADDR_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid), .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .npu_irq(npu_irq)
    );

    // ========================================================
    // AI_MEM AXI4 slave BFM (tek-outstanding, 1 cyc gecikme)
    // ========================================================
    localparam int AI_MEM_WORDS = 32768;
    logic [7:0] ai_mem [0:AI_MEM_WORDS-1];

    logic [AXI_ADDR_W-1:0] ar_addr_q;
    logic                  r_pending;

    assign m_axi_arready = !r_pending;
    assign m_axi_rvalid  = r_pending;
    // AXI4-uyumlu: bayt adres lane'ine (8*addr[1:0]) yerlesir (ai_mem ile ayni)
    assign m_axi_rdata   = ({24'h0, ai_mem[ar_addr_q[14:0]]}) << (8*ar_addr_q[1:0]);
    assign m_axi_rresp   = 2'b00;
    assign m_axi_rlast   = 1'b1;
    assign m_axi_rid     = '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_pending <= 1'b0;
            ar_addr_q <= '0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                ar_addr_q <= m_axi_araddr;
                r_pending <= 1'b1;
            end
            if (m_axi_rvalid && m_axi_rready) r_pending <= 1'b0;
        end
    end

    // Yazma kanalı kullanılmıyor — terbiyeli tut
    assign m_axi_awready = 1'b1;
    assign m_axi_wready  = 1'b1;
    assign m_axi_bvalid  = 1'b0;
    assign m_axi_bresp   = 2'b00;
    assign m_axi_bid     = '0;

    // ========================================================
    // AXI4-Lite CSR sürücüleri
    // ========================================================
    initial begin
        s_axil_awvalid = 0; s_axil_awaddr = '0;
        s_axil_wvalid  = 0; s_axil_wdata = '0; s_axil_wstrb = 4'hF;
        s_axil_bready  = 1;
        s_axil_arvalid = 0; s_axil_araddr = '0;
        s_axil_rready  = 1;
    end

    // ========================================================
    // SVA — protokol kontrolleri (şartname §4 "Protokol Kontrolleri")
    // AXI handshake kararlılığı + NPU invariantları. Verilator --assert ile.
    // ========================================================
    default disable iff (!rst_n);

    // Gözlem: NPU iç durum (assertion için hiyerarşik)
    wire fsm_busy_w = dut.fsm_busy;
    wire fsm_done_w = dut.fsm_done;

    // AXI4-Lite slave: B kanalı bvalid&&!bready → bvalid + bresp sabit kalır
    a_b_hold: assert property (@(posedge clk)
        (s_axil_bvalid && !s_axil_bready) |=> (s_axil_bvalid && $stable(s_axil_bresp)));
    // AXI4-Lite slave: R kanalı rvalid&&!rready → rvalid + rdata sabit
    a_r_hold: assert property (@(posedge clk)
        (s_axil_rvalid && !s_axil_rready) |=> (s_axil_rvalid && $stable(s_axil_rdata)));
    // AXI4 master AR: arvalid&&!arready → arvalid + araddr sabit
    a_ar_hold: assert property (@(posedge clk)
        (m_axi_arvalid && !m_axi_arready) |=> (m_axi_arvalid && $stable(m_axi_araddr)));
    // AXI4 master AR sabitleri: tek-beat, byte size, INCR
    a_ar_attr: assert property (@(posedge clk)
        m_axi_arvalid |-> (m_axi_arlen == 8'h0 && m_axi_arsize == 3'b000 && m_axi_arburst == 2'b01));
    // IRQ tek-çevrim puls
    a_irq_pulse: assert property (@(posedge clk) npu_irq |=> !npu_irq);
    // BUSY ile DONE aynı anda yüksek olamaz (busy=hesap, done=tamam-sticky)
    a_busy_done: assert property (@(posedge clk) !(fsm_busy_w && fsm_done_w));

    // Stimulus negedge'de sürülür (posedge örneklemesiyle yarışmaz)
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
    logic [7:0]         exp_dwout [0:FC_FLAT-1];     // golden DW çıkışı
    logic signed [7:0]  exp_logits [0:FC_OUTPUTS-1]; // golden FC logit'leri (INT8)
    integer             exp_class;

    task automatic load_expected_class;
        integer fd, rc;
        fd = $fopen("weights/npu_expected_class.txt", "r");
        if (fd == 0) $fatal(1, "[FATAL] npu_expected_class.txt yok (golden --emit calistir)");
        rc = $fscanf(fd, "%d", exp_class);
        if (rc != 1) $fatal(1, "[FATAL] beklenen sinif okunamadi");
        $fclose(fd);
    endtask

    // ---- Test akışı ----
    integer pass_cnt = 0, fail_cnt = 0;
    logic [31:0] rd;

    task automatic check(input string nm, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin $display("[PASS] %s = 0x%08X", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s got=0x%08X exp=0x%08X", nm, got, exp); fail_cnt++; end
    endtask

    integer i, mism;

    initial begin
        // AI_MEM'i sıfırla, golden blob + giriş yükle
        for (i = 0; i < AI_MEM_WORDS; i++) ai_mem[i] = 8'h00;
        $readmemh("weights/npu_weights.mem", ai_mem, WEIGHT_BASE);
        $readmemh("weights/npu_input.mem",   ai_mem, INPUT_BASE);
        $readmemh("weights/npu_dwout.mem",   exp_dwout);
        $readmemh("weights/npu_logits.mem",  exp_logits);
        load_expected_class();

        @(posedge rst_n);
        repeat (5) @(posedge clk);
        $display("=== TUNGA NPU Self-Checking TB === (golden class beklenen=%0d)", exp_class);

        // CSR varsayılan
        axil_read(8'h04, rd);
        check("NPU_STATUS reset", rd, 32'h0);

        // Adresleri programla
        axil_write(8'h08, INPUT_BASE);
        axil_write(8'h0C, WEIGHT_BASE);
        axil_read(8'h08, rd); check("NPU_INPUT_ADDR", rd, INPUT_BASE);
        axil_read(8'h0C, rd); check("NPU_WEIGHT_ADDR", rd, WEIGHT_BASE);

        // START
        axil_write(8'h00, 32'h1);
        axil_read(8'h04, rd);
        if (rd[1]) $display("[PASS] BUSY set"); else $display("[WARN] BUSY gorulmedi");

        // IRQ bekle
        $display("[INFO] cikarim... IRQ bekleniyor");
        fork
            begin @(posedge npu_irq); $display("[PASS] IRQ alindi"); pass_cnt++; end
            begin repeat (TIMEOUT_CYC) @(posedge clk);
                  $fatal(1, "[TIMEOUT] IRQ %0d cyc'de gelmedi", TIMEOUT_CYC); end
        join_any
        disable fork;

        // Sonuç sınıfı
        axil_read(8'h10, rd);
        $display("[INFO] NPU_RESULT = %0d (%s)", rd[1:0],
            rd[1:0]==0?"silence":rd[1:0]==1?"unknown":rd[1:0]==2?"yes":"no");
        check("NPU sinif == golden", {30'h0, rd[1:0]}, exp_class[31:0]);

        // Durum bitleri
        axil_read(8'h04, rd);
        check("DONE biti", {31'h0, rd[0]}, 32'h1);
        check("BUSY biti temiz", {31'h0, rd[1]}, 32'h0);

        // DERİN kontrol 1: FC logit'leri (int32) golden ile bit-bit
        mism = 0;
        for (i = 0; i < FC_OUTPUTS; i++)
            if (dut.u_fc.logits[i] !== exp_logits[i]) begin
                mism++;
                $display("[FAIL] logit[%0d] got=%0d exp=%0d", i, dut.u_fc.logits[i], exp_logits[i]);
            end
        if (mism == 0) begin
            $display("[PASS] FC logit'leri golden ile bit-exact (4 nöron)"); pass_cnt++;
        end else begin
            $display("[FAIL] FC logit'lerinde %0d uyusmazlik", mism); fail_cnt++;
        end

        // DERİN kontrol 2: DW çıkışı (local_buffer) golden ile bit-bit
        mism = 0;
        for (i = 0; i < FC_FLAT; i++)
            if (dut.u_lbuf.mem[i] !== $signed(exp_dwout[i])) begin
                mism++;
                if (mism <= 10)
                    $display("[FAIL] DWout[%0d] got=%0d exp=%0d", i,
                             dut.u_lbuf.mem[i], $signed(exp_dwout[i]));
            end
        if (mism == 0) begin
            $display("[PASS] DW cikisi golden ile bit-exact (4000 eleman)"); pass_cnt++;
        end else begin
            $display("[FAIL] DW cikisinda %0d/%0d uyusmazlik", mism, FC_FLAT); fail_cnt++;
        end

        $display("=========================================");
        $display("TUNGA NPU TB:  PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("  >>> TUM TESTLER GECTI <<<");
        else               $display("  >>> %0d TEST BASARISIZ <<<", fail_cnt);
        $display("=========================================");
        if (fail_cnt != 0) $fatal(1, "NPU TB FAIL");
        $finish;
    end

endmodule
