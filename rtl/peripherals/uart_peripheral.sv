// Temel UART çevre birimi (şartname EK-2 yazmaç haritası)

module uart_peripheral #(
    // Sistem saat frekansı (varsayılan 50 MHz)
    parameter int SYS_CLK_HZ    = 50_000_000,
    // Varsayılan baud hızı
    parameter int DEFAULT_BAUD  = 115_200,
    // IP Packager'ın XML motoru için açıkça (explicit) eklenen genişlik parametreleri
    parameter int AXI_ADDR_W    = 8,
    parameter int AXI_DATA_W    = 32
)(
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------
    // AXI4-Lite Slave Arayüzü
    // -------------------------------------------------------------------
    // Yazma adresi kanalı
    input  logic [AXI_ADDR_W-1:0] s_axil_awaddr,
    input  logic                  s_axil_awvalid,
    output logic                  s_axil_awready,

    // Yazma verisi kanalı
    input  logic [AXI_DATA_W-1:0] s_axil_wdata,
    input  logic [3:0]            s_axil_wstrb,
    input  logic                  s_axil_wvalid,
    output logic                  s_axil_wready,

    // Yazma yanıt kanalı
    output logic [1:0]            s_axil_bresp,
    output logic                  s_axil_bvalid,
    input  logic                  s_axil_bready,

    // Okuma adresi kanalı
    input  logic [AXI_ADDR_W-1:0] s_axil_araddr,
    input  logic                  s_axil_arvalid,
    output logic                  s_axil_arready,

    // Okuma verisi kanalı
    output logic [AXI_DATA_W-1:0] s_axil_rdata,
    output logic [1:0]            s_axil_rresp,
    output logic                  s_axil_rvalid,
    input  logic                  s_axil_rready,

    // -------------------------------------------------------------------
    // Fiziksel UART hatları
    // -------------------------------------------------------------------
    input  logic uart_rxd,  // Seri giriş
    output logic uart_txd,  // Seri çıkış

    // -------------------------------------------------------------------
    // Kesme çıkışı
    // -------------------------------------------------------------------
    output logic uart_irq   // RX alındı veya TX tamamlandı kesmesi
);

    // İçerideki lojikte kullanılacak paket sabitleri (Sentezleyici içi lokal tanımlar)
    localparam logic [7:0] UART_CPB_OFFSET         = 8'h00;
    localparam logic [7:0] UART_STP_OFFSET         = 8'h04;
    localparam logic [7:0] UART_RDR_OFFSET         = 8'h08;
    localparam logic [7:0] UART_TDR_OFFSET         = 8'h0C;
    localparam logic [7:0] UART_CFG_OFFSET         = 8'h10;

    localparam int CFG_TX_EN   = 0;
    localparam int CFG_RX_DONE = 1;
    localparam int CFG_TX_DONE = 2;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // Yazmaç tanımları
    logic [31:0] reg_cpb_r;   // UART_CPB
    logic [31:0] reg_stp_r;   // UART_STP  (yalnızca [1:0] geçerli)
    logic [7:0]  reg_rdr_r;   // UART_RDR  (RO, HW tarafından yazılır)
    logic [7:0]  reg_tdr_r;   // UART_TDR
    logic [2:0]  reg_cfg_r;   // UART_CFG  [TX_EN, RX_DONE, TX_DONE]

    // Varsayılan CPB değeri
    localparam logic [31:0] DEF_CPB = SYS_CLK_HZ / DEFAULT_BAUD;

    // =========================================================================
    // TX ve RX alt modülleri
    // =========================================================================
    logic tx_start_r;
    logic tx_done_w;
    logic tx_busy_w;

    uart_tx u_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_cpb      (reg_cpb_r),
        .i_stp      (reg_stp_r[1:0]),
        .i_data     (reg_tdr_r),
        .i_tx_start (tx_start_r),
        .o_tx       (uart_txd),
        .o_tx_busy  (tx_busy_w),
        .o_tx_done  (tx_done_w)
    );

    logic       rx_done_w;
    logic [7:0] rx_data_w;
    logic       rx_frame_err_w;

    uart_rx u_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_cpb      (reg_cpb_r),
        .i_rx       (uart_rxd),
        .o_data     (rx_data_w),
        .o_rx_done  (rx_done_w),
        .o_rx_busy  (),
        .o_frame_err(rx_frame_err_w)
    );

    // Kesme: RX alındı VEYA TX tamamlandı
    assign uart_irq = reg_cfg_r[CFG_RX_DONE] | reg_cfg_r[CFG_TX_DONE];

    // =========================================================================
    // TX tetikleme lojiği
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_start_r <= 1'b0;
        end else begin
            tx_start_r <= 1'b0; // Varsayılan: 0 (tek saat darbesi)
            if (reg_cfg_r[CFG_TX_EN] && !tx_busy_w) begin
                tx_start_r <= 1'b1;
            end
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - Yazma Kanalı
    // =========================================================================
    logic aw_active_r; 
    logic w_active_r;  
    logic [AXI_ADDR_W-1:0] aw_addr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_active_r    <= 1'b0;
            w_active_r     <= 1'b0;
            aw_addr_r      <= '0;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= AXI_RESP_OKAY;
            // Yazmaç sıfırlama
            reg_cpb_r      <= DEF_CPB;
            reg_stp_r      <= '0;
            reg_tdr_r      <= '0;
            reg_rdr_r      <= '0;
            reg_cfg_r      <= '0;
        end else begin
            if (rx_done_w) begin
                reg_rdr_r              <= rx_data_w;
                reg_cfg_r[CFG_RX_DONE] <= 1'b1;
            end
            if (tx_done_w) begin
                reg_cfg_r[CFG_TX_DONE] <= 1'b1;
                reg_cfg_r[CFG_TX_EN]   <= 1'b0;
            end

            if (s_axil_awvalid && s_axil_awready) begin
                aw_active_r    <= 1'b1;
                aw_addr_r      <= s_axil_awaddr;
                s_axil_awready <= 1'b0;
            end else if (!aw_active_r) begin
                s_axil_awready <= s_axil_awvalid;
            end

            if (s_axil_wvalid && s_axil_wready) begin
                w_active_r    <= 1'b1;
                s_axil_wready <= 1'b0;
            end else if (!w_active_r) begin
                s_axil_wready <= s_axil_wvalid;
            end

            if (aw_active_r && w_active_r && !s_axil_bvalid) begin
                aw_active_r   <= 1'b0;
                w_active_r    <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= AXI_RESP_OKAY;

                unique case (aw_addr_r[7:0])
                    UART_CPB_OFFSET: reg_cpb_r <= s_axil_wdata;
                    UART_STP_OFFSET: reg_stp_r <= s_axil_wdata;
                    UART_TDR_OFFSET: reg_tdr_r <= s_axil_wdata[7:0];
                    UART_CFG_OFFSET: begin
                        if (s_axil_wdata[CFG_TX_EN])
                            reg_cfg_r[CFG_TX_EN] <= 1'b1;
                        if (!s_axil_wdata[CFG_RX_DONE] && !rx_done_w)
                            reg_cfg_r[CFG_RX_DONE] <= 1'b0;
                        if (!s_axil_wdata[CFG_TX_DONE] && !tx_done_w)
                            reg_cfg_r[CFG_TX_DONE] <= 1'b0;
                    end
                    default: s_axil_bresp <= AXI_RESP_SLVERR;
                endcase
            end

            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - Okuma Kanalı (Handshake Kilidi Kırıldı!)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= AXI_RESP_OKAY;
        end else begin
            // s_axil_arready sinyalini sadece tek bir çevrim boyunca kalkık tutan kararlı yapı
            if (s_axil_arvalid && !s_axil_rvalid && !s_axil_arready) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= AXI_RESP_OKAY;

                unique case (s_axil_araddr[7:0])
                    UART_CPB_OFFSET: s_axil_rdata <= reg_cpb_r;
                    UART_STP_OFFSET: s_axil_rdata <= reg_stp_r;
                    UART_RDR_OFFSET: s_axil_rdata <= {24'b0, reg_rdr_r};
                    UART_TDR_OFFSET: s_axil_rdata <= {24'b0, reg_tdr_r};
                    UART_CFG_OFFSET: s_axil_rdata <= {29'b0, reg_cfg_r};
                    default: begin
                        s_axil_rdata <= '0;
                        s_axil_rresp <= AXI_RESP_SLVERR;
                    end
                endcase
            end else begin
                s_axil_arready <= 1'b0; // El sıkışma sağlandığı an sonraki çevrimde hemen inip kilitlenmeyi önler
            end

            if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;
        end
    end

endmodule