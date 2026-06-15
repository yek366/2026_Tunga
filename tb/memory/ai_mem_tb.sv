`timescale 1ns/1ps

module ai_mem_tb;
    localparam int          ADDR_W = 32, DATA_W = 32, ID_W = 4;
    localparam logic [31:0] BASE   = 32'h0001_0000;
    localparam int          SIZE   = 30720;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // AR/R
    logic [ID_W-1:0]  arid;  logic [ADDR_W-1:0] araddr; logic [7:0] arlen;
    logic [2:0] arsize; logic [1:0] arburst; logic arvalid, arready;
    logic [ID_W-1:0]  rid;   logic [DATA_W-1:0] rdata;  logic [1:0] rresp;
    logic rlast, rvalid, rready;
    // AW/W/B
    logic [ID_W-1:0]  awid;  logic [ADDR_W-1:0] awaddr; logic [7:0] awlen;
    logic [2:0] awsize; logic [1:0] awburst; logic awvalid, awready;
    logic [DATA_W-1:0] wdata; logic [3:0] wstrb; logic wlast, wvalid, wready;
    logic [ID_W-1:0]  bid;   logic [1:0] bresp; logic bvalid, bready;

    ai_mem #(.ADDR_WIDTH(ADDR_W), .DATA_WIDTH(DATA_W), .ID_WIDTH(ID_W),
             .BASE_ADDR(BASE), .SIZE_BYTES(SIZE), .INIT_FILE("")) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
        .s_axi_arsize(arsize), .s_axi_arburst(arburst), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rlast(rlast),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen), .s_axi_awsize(awsize),
        .s_axi_awburst(awburst), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready)
    );

    int pass = 0, fail = 0;
    task automatic chk(input string nm, input logic c);
        if (c) begin $display("[PASS] %s", nm); pass++; end
        else   begin $display("[FAIL] %s", nm); fail++; end
    endtask

    // tek-beat yazma
    task automatic wr(input logic [31:0] a, input logic [31:0] d, input logic [3:0] s,
                      output logic [1:0] resp);
        @(negedge clk);
        awaddr=a; awid='0; awlen=0; awsize=3'b010; awburst=2'b01; awvalid=1;
        wdata=d; wstrb=s; wlast=1; wvalid=1;
        do @(posedge clk); while (!(awready && wready));
        @(negedge clk); awvalid=0; wvalid=0;
        do @(posedge clk); while (!bvalid);
        resp = bresp;
        @(negedge clk);
    endtask

    // tek-beat okuma
    task automatic rd(input logic [31:0] a, output logic [31:0] d, output logic [1:0] resp);
        @(negedge clk);
        araddr=a; arid='0; arlen=0; arsize=3'b000; arburst=2'b01; arvalid=1;
        do @(posedge clk); while (!arready);
        @(negedge clk); arvalid=0;
        do @(posedge clk); while (!rvalid);
        d = rdata; resp = rresp;
        @(negedge clk);
    endtask

    logic [31:0] rv; logic [1:0] rsp;

    initial begin
        arvalid=0; awvalid=0; wvalid=0; bready=1; rready=1;
        arid='0; araddr='0; arlen=0; arsize=0; arburst=2'b01;
        awid='0; awaddr='0; awlen=0; awsize=0; awburst=2'b01; wdata='0; wstrb=0; wlast=0;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        $display("=== ai_mem birim TB ===");

        // 1) Yazma + geri okuma (lane 0). BASE+0 word=0xAABBCCDD, byte0=0xDD
        wr(BASE+0, 32'hAABBCCDD, 4'hF, rsp);
        chk("yazma BASE+0 bresp OKAY", rsp === 2'b00);
        rd(BASE+0, rv, rsp);  // arsize=0 → byte0 lane0
        chk("oku BASE+0 = 0xDD lane0 + OKAY", rv[7:0]===8'hDD && rsp===2'b00);

        // 2) Lane hizalama: BASE+1 byte=0xCC lane1, BASE+2=0xBB lane2, BASE+3=0xAA lane3
        rd(BASE+1, rv, rsp); chk("BASE+1 lane1 = 0xCC<<8",  rv===32'h0000_CC00 && rsp===2'b00);
        rd(BASE+2, rv, rsp); chk("BASE+2 lane2 = 0xBB<<16", rv===32'h00BB_0000 && rsp===2'b00);
        rd(BASE+3, rv, rsp); chk("BASE+3 lane3 = 0xAA<<24", rv===32'hAA00_0000 && rsp===2'b00);

        // 3) wstrb bayt-enable: sadece byte2 yaz
        wr(BASE+4, 32'h1122_3344, 4'b0100, rsp);  // yalniz wdata[23:16]=0x22 -> BASE+6
        rd(BASE+6, rv, rsp); chk("wstrb byte2 -> BASE+6 = 0x22", rv[23:16]===8'h22 && rsp===2'b00);
        rd(BASE+4, rv, rsp); chk("BASE+4 yazilmadi (strb kapali) = 0x00", rv[7:0]===8'h00);

        // 4) Aralik USTU OOB: BASE+SIZE -> SLVERR
        rd(BASE + SIZE, rv, rsp);     chk("OOB (BASE+SIZE) okuma rresp=SLVERR", rsp===2'b10);
        wr(BASE + SIZE, 32'h0, 4'hF, rsp); chk("OOB yazma bresp=SLVERR", rsp===2'b10);

        // 5) Alt-tasma: BASE-4 -> SLVERR (unsigned wrap yakalanir)
        rd(BASE - 4, rv, rsp);        chk("alt-tasma (BASE-4) rresp=SLVERR", rsp===2'b10);

        // 6) Son gecerli adres BASE+SIZE-1 OKAY
        rd(BASE + SIZE - 1, rv, rsp); chk("son gecerli adres OKAY", rsp===2'b00);

        $display("=========================================");
        $display("ai_mem TB:  PASS=%0d  FAIL=%0d", pass, fail);
        if (fail==0) $display("  >>> TUM TESTLER GECTI <<<");
        else         $display("  >>> %0d BASARISIZ <<<", fail);
        if (fail!=0) $fatal(1, "ai_mem TB FAIL");
        $finish;
    end

    // timeout
    initial begin #100000; $fatal(1, "[TIMEOUT] ai_mem TB"); end
endmodule
