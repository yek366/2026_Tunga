
`timescale 1ns / 1ps

module jtag_debug_wrapper (
    // --- Sistem Saat ve Reset (AXI Bus ile Senkron) ---
    input  logic        m_axi_aclk,
    input  logic        m_axi_aresetn,

    // --- Fiziksel JTAG Pinleri (Dış Dünyaya / Pad'lere Gider) ---
    input  logic        jtag_tck_i,
    input  logic        jtag_tms_i,
    input  logic        jtag_trst_ni,
    input  logic        jtag_tdi_i,
    output logic        jtag_tdo_o,
    output logic        jtag_tdo_oe_o,

    // --- CV32E40P Çekirdek Bağlantıları & Kesme Hattı ---
    output logic        debug_req_o,    // İşlemciyi donduracak Halt sinyali
    output logic        debug_irq_o,    // EKLENDİ: Ana işlemciye/PLIC'e giden Debug Kesmesi!

    // --- AXI4-Lite Master Arayüzü (SBA - Sistem Bellek Erişimi) ---
    // Write Address Channel
    output logic [31:0] m_axi_awaddr,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    
    // Write Data Channel
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    
    // Write Response Channel
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    
    // Read Address Channel
    output logic [31:0] m_axi_araddr,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    
    // Read Data Channel
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    // --- Vivado IP Packager Hatasını Önlemek İçin Düzleştirilmiş Sinyaller ---
    // Alt modüllerin struct/interface bağımlılıkları bu flat kablolarla izole ediliyor.
    logic [40:0] dmi_req_bus;
    logic        dmi_req_valid;
    logic        dmi_req_ready;
    
    logic [33:0] dmi_resp_bus;
    logic        dmi_resp_valid;
    logic        dmi_resp_ready;

    // --- dm_top SBA İç Veriyolu ---
    logic        sb_req;
    logic [31:0] sb_address;
    logic        sb_we;
    logic [31:0] sb_wdata;
    logic [3:0]  sb_be;
    logic        sb_gnt;
    logic        sb_vld;
    logic [31:0] sb_rdata;

    // AXI Sabit Korumaları
    assign m_axi_awprot = 3'b000;
    assign m_axi_arprot = 3'b000;

    // 1. JTAG DTM (TAP) Instantiation
    dmi_jtag #(
        .IdcodeValue (32'h10E31913)
    ) i_dmi_jtag (
        .clk_i            (m_axi_aclk),
        .rst_ni           (m_axi_aresetn),
        .testmode_i       (1'b0),
        
        .tck_i            (jtag_tck_i),
        .tms_i            (jtag_tms_i),
        .trst_ni          (jtag_trst_ni),
        .td_i             (jtag_tdi_i),
        .td_o             (jtag_tdo_o),
        .tdo_oe_o         (jtag_tdo_oe_o),
        
        .dmi_rst_no       (), 
        .dmi_req_o        (dmi_req_bus),
        .dmi_req_valid_o  (dmi_req_valid),
        .dmi_req_ready_i  (dmi_req_ready),
        
        .dmi_resp_i       (dmi_resp_bus),
        .dmi_resp_ready_o (dmi_resp_ready),
        .dmi_resp_valid_i (dmi_resp_valid)
    );

    // 2. Debug Modülü (DM TOP) Instantiation
    dm_top #(
        .NrHarts          (1),
        .BusWidth         (32),
        .SelectableHarts  (1'b1)
    ) i_dm_top (
        .clk_i            (m_axi_aclk),
        .rst_ni           (m_axi_aresetn),
        .testmode_i       (1'b0),
        .ndmreset_o       (), 
        .dmactive_o       (debug_irq_o),   // KESME BAĞLANTISI: dmactive durumu kesme olarak dışarı sürülüyor!
        .debug_req_o      (debug_req_o),
        .unavailable_i    (1'b0),
        
        // DMI İstekleri
        .dmi_req_valid_i  (dmi_req_valid),
        .dmi_req_ready_o  (dmi_req_ready),
        .dmi_req_i        (dmi_req_bus),   
        
        // DMI Cevapları
        .dmi_resp_valid_o (dmi_resp_valid),
        .dmi_resp_ready_i (dmi_resp_ready),
        .dmi_resp_o       (dmi_resp_bus),   
        
        // SBA Çıkışları
        .master_req_o     (sb_req),
        .master_add_o     (sb_address),
        .master_we_o      (sb_we),
        .master_wdata_o   (sb_wdata),
        .master_be_o      (sb_be),
        .master_gnt_i     (sb_gnt),
        .master_r_valid_i (sb_vld),
        .master_r_rdata_i (sb_rdata)
    );

    // 3. SBA to AXI4-Lite FSM Bridge
    typedef enum logic [1:0] {AXI_IDLE, AXI_W_ADDR, AXI_W_DATA, AXI_R_REQ} axi_state_t;
    axi_state_t state_q, state_d;

    always_comb begin
        state_d = state_q;
        
        m_axi_awaddr  = sb_address;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = sb_wdata;
        m_axi_wstrb   = sb_be;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b1;
        m_axi_araddr  = sb_address;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b1;
        
        sb_gnt   = 1'b0;
        sb_vld   = 1'b0;
        sb_rdata = m_axi_rdata;

        case (state_q)
            AXI_IDLE: begin
                if (sb_req) begin
                    sb_gnt = 1'b1;
                    if (sb_we) begin
                        state_d = AXI_W_ADDR;
                    end else begin
                        state_d = AXI_R_REQ;
                    end
                end
            end

            AXI_W_ADDR: begin
                m_axi_awvalid = 1'b1;
                if (m_axi_awready) begin
                    state_d = AXI_W_DATA;
                end
            end

            AXI_W_DATA: begin
                m_axi_wvalid = 1'b1;
                if (m_axi_wready) begin
                    sb_vld  = m_axi_bvalid;
                    state_d = AXI_IDLE;
                end
            end

            AXI_R_REQ: begin
                m_axi_arvalid = 1'b1;
                if (m_axi_arready) begin
                    sb_vld  = m_axi_rvalid;
                    if (m_axi_rvalid) state_d = AXI_IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge m_axi_aclk or negedge m_axi_aresetn) begin
        if (!m_axi_aresetn) begin
            state_q <= AXI_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

endmodule