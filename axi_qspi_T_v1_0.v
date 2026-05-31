`timescale 1 ns / 1 ps

module axi_qspi_T_v1_0 #
(
    parameter integer C_S00_AXI_DATA_WIDTH    = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH    = 4,
    parameter integer C_S_AXI_INTR_DATA_WIDTH = 32,
    parameter integer C_S_AXI_INTR_ADDR_WIDTH = 5,
    parameter integer C_NUM_OF_INTR           = 1
)
(
    // Fiziksel Pinler
    output wire SCLK_pad,
    output wire CS_pad,
    inout  wire [3:0] dq_pad,

    // AXI Portları
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire  s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire  s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire  s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire  s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire  s00_axi_rvalid,
    input wire  s00_axi_rready,

    // Interrupt Portları
    input wire  s_axi_intr_aclk,
    input wire  s_axi_intr_aresetn,
    input wire [C_S_AXI_INTR_ADDR_WIDTH-1 : 0] s_axi_intr_awaddr,
    input wire [2 : 0] s_axi_intr_awprot,
    input wire  s_axi_intr_awvalid,
    output wire  s_axi_intr_awready,
    input wire [C_S_AXI_INTR_DATA_WIDTH-1 : 0] s_axi_intr_wdata,
    input wire [(C_S_AXI_INTR_DATA_WIDTH/8)-1 : 0] s_axi_intr_wstrb,
    input wire  s_axi_intr_wvalid,
    output wire  s_axi_intr_wready,
    output wire [1 : 0] s_axi_intr_bresp,
    output wire  s_axi_intr_bvalid,
    input wire  s_axi_intr_bready,
    input wire [C_S_AXI_INTR_ADDR_WIDTH-1 : 0] s_axi_intr_araddr,
    input wire [2 : 0] s_axi_intr_arprot,
    input wire  s_axi_intr_arvalid,
    output wire  s_axi_intr_arready,
    output wire [C_S_AXI_INTR_DATA_WIDTH-1 : 0] s_axi_intr_rdata,
    output wire [1 : 0] s_axi_intr_rresp,
    output wire  s_axi_intr_rvalid,
    input wire  s_axi_intr_rready,
    output wire  irq
);

    // Ara Sinyaller
    wire [3:0] dq_o;
    wire [3:0] dq_i;
    wire [3:0] dq_oe;

    // --- TRISTATE MANTIĞI DÜZELTİLDİ ---
    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin : gen_simple_io
            assign dq_pad[k] = (dq_oe[k]) ? dq_o[k] : 1'bz;
            assign dq_i[k] = dq_pad[k];
        end
    endgenerate // <--- HATA BURADAYDI, endgenerate yapıldı.

    // --- S00_AXI ÇAĞRISI ---
    axi_qspi_T_v1_0_S00_AXI # ( 
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) axi_qspi_T_v1_0_S00_AXI_inst (
        .SCLK_pad(SCLK_pad),      
        .CS_pad(CS_pad),        
        .dq_o(dq_o),
        .dq_i(dq_i),
        .dq_oe(dq_oe),
        .S_AXI_ACLK(s00_axi_aclk),
        .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR(s00_axi_awaddr),
        .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID(s00_axi_awvalid),
        .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA(s00_axi_wdata),
        .S_AXI_WSTRB(s00_axi_wstrb),
        .S_AXI_WVALID(s00_axi_wvalid),
        .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP(s00_axi_bresp),
        .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY(s00_axi_bready),
        .S_AXI_ARADDR(s00_axi_araddr),
        .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID(s00_axi_arvalid),
        .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA(s00_axi_rdata),
        .S_AXI_RRESP(s00_axi_rresp),
        .S_AXI_RVALID(s00_axi_rvalid),
        .S_AXI_RREADY(s00_axi_rready)
    );

    // IRQ Bağlantısı (İsteğe bağlı, motor_done'a bağlanabilir)
    assign irq = 1'b0; 

endmodule