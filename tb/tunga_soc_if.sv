`ifndef TUNGA_SOC_IF_SV
`define TUNGA_SOC_IF_SV

interface tunga_soc_if(input logic clk, input logic rst_n);
    // AXI-Lite Sinyalleri
    logic [31:0] awaddr;
    logic        awvalid;
    logic        awready;

    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;

    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    logic [31:0] araddr;
    logic        arvalid;
    logic        arready;

    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    // JTAG, UART vb. ek sinyaller gerekiyorsa buraya eklenebilir.
    logic [31:0] uart_baud_rate;
    logic        ai_interrupt;

    // =========================================================================
    // SYSTEMVERILOG ASSERTIONS (SVA) - AXI PROTOKOL KONTROLLERİ
    // =========================================================================
    
    // 1. AWVALID sinyali AWREADY gelene kadar DÜŞÜRÜLEMEZ
    property p_awvalid_hold;
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> awvalid;
    endproperty
    assert_awvalid_hold: assert property(p_awvalid_hold)
        else $error("[SVA HATA] AWVALID, AWREADY beklenmeden dusuruldu!");

    // 2. ARVALID sinyali ARREADY gelene kadar DÜŞÜRÜLEMEZ
    property p_arvalid_hold;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> arvalid;
    endproperty
    assert_arvalid_hold: assert property(p_arvalid_hold)
        else $error("[SVA HATA] ARVALID, ARREADY beklenmeden dusuruldu!");

    // 3. WVALID sinyali WREADY gelene kadar DÜŞÜRÜLEMEZ
    property p_wvalid_hold;
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> wvalid;
    endproperty
    assert_wvalid_hold: assert property(p_wvalid_hold)
        else $error("[SVA HATA] WVALID, WREADY beklenmeden dusuruldu!");

endinterface

`endif
