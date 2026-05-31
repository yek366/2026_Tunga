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
endinterface

`endif
