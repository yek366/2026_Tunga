// =============================================================================
// uart_stream_peripheral.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - UART Stream Çevre Birimi (Gömülü DMA Sürümü)
//
// Çift Arayüz: 
//   - AXI4-Lite Slave  : CPU konfigürasyonu ve yazmaç erişimi
//   - AXI4-Lite Master : Gelen verileri doğrudan YZ Belleğine (SRAM) yazma
// =============================================================================

module uart_stream_peripheral #(
    parameter int SYS_CLK_HZ    = 50_000_000,
    parameter int DEFAULT_BAUD  = 115_200,
    parameter int AXI_ADDR_W    = 8,   // Slave Adres Genişliği
    parameter int AXI_DATA_W    = 32,  // Slave/Master Veri Genişliği
    parameter int M_AXI_ADDR_W  = 32,  // Master Adres Genişliği (SRAM/YZ erişimi için)
    parameter int FIFO_DEPTH    = 256,
    parameter int FIFO_PTR_W    = 8
)(
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------
    // AXI4-Lite Slave Arayüzü (CPU Erişim Portu)
    // -------------------------------------------------------------------
    input  logic [AXI_ADDR_W-1:0] s_axil_awaddr,
    input  logic                  s_axil_awvalid,
    output logic                  s_axil_awready,

    input  logic [AXI_DATA_W-1:0] s_axil_wdata,
    input  logic [3:0]            s_axil_wstrb,
    input  logic                  s_axil_wvalid,
    output logic                  s_axil_wready,

    output logic [1:0]            s_axil_bresp,
    output logic                  s_axil_bvalid,
    input  logic                  s_axil_bready,

    input  logic [AXI_ADDR_W-1:0] s_axil_araddr,
    input  logic                  s_axil_arvalid,
    output logic                  s_axil_arready,

    output logic [AXI_DATA_W-1:0] s_axil_rdata,
    output logic [1:0]            s_axil_rresp,
    output logic                  s_axil_rvalid,
    input  logic                  s_axil_rready,

    // -------------------------------------------------------------------
    // AXI4-Lite Master Arayüzü (YZ Belleği / SRAM Yazma Portu)
    // -------------------------------------------------------------------
    output logic [M_AXI_ADDR_W-1:0] m_axil_awaddr,
    output logic                    m_axil_awvalid,
    input  logic                    m_axil_awready,

    output logic [AXI_DATA_W-1:0]   m_axil_wdata,
    output logic [3:0]              m_axil_wstrb,
    output logic                    m_axil_wvalid,
    input  logic                    m_axil_wready,

    input  logic [1:0]              m_axil_bresp,
    input  logic                    m_axil_bvalid,
    output logic                    m_axil_bready,

    // -------------------------------------------------------------------
    // Fiziksel UART hatları
    // -------------------------------------------------------------------
    input  logic uart_rxd,
    output logic uart_txd,

    // -------------------------------------------------------------------
    // Durum ve kesme çıkışları
    // -------------------------------------------------------------------
    output logic uart_stream_irq,   
    output logic fifo_empty,        
    output logic fifo_full          
);

    // Yazmaç Offsetleri
    localparam logic [7:0] UART_CPB_OFFSET         = 8'h00;
    localparam logic [7:0] UART_STP_OFFSET         = 8'h04;
    localparam logic [7:0] UART_RDR_OFFSET         = 8'h08;
    localparam logic [7:0] UART_TDR_OFFSET         = 8'h0C;
    localparam logic [7:0] UART_CFG_OFFSET         = 8'h10;
    localparam logic [7:0] UARTS_FIFO_LEVEL_OFFSET = 8'h14;
    localparam logic [7:0] UARTS_FIFO_CLR_OFFSET   = 8'h18;
    localparam logic [7:0] UARTS_IRQ_EN_OFFSET     = 8'h1C;
    localparam logic [7:0] UARTS_TARGET_OFFSET     = 8'h20; // YZ Hedef Adres Yazmacı (Yeni!)

    localparam int CFG_TX_EN   = 0;
    localparam int CFG_RX_DONE = 1;
    localparam int CFG_TX_DONE = 2;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // Yazmaçlar
    logic [31:0]          reg_cpb_r;
    logic [31:0]          reg_stp_r;
    logic [7:0]           reg_tdr_r;
    logic [2:0]           reg_cfg_r;
    logic [31:0]          reg_irq_en_r;
    logic [M_AXI_ADDR_W-1:0] reg_target_addr_r; // Gömülü DMA için hedef adres yazmacı

    localparam logic [31:0] DEF_CPB = SYS_CLK_HZ / DEFAULT_BAUD;

    localparam int IRQ_RX_DONE    = 0;
    localparam int IRQ_FIFO_HALF  = 1;
    localparam int IRQ_FIFO_FULL  = 2;
    localparam int IRQ_TX_DONE    = 3;
    localparam int IRQ_FRAME_ERR  = 4;

    // Alt modül bağlantıları
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

    // RX FIFO Sistemi
    logic              fifo_wr_en;
    logic              fifo_rd_en;
    logic [7:0]        fifo_rd_data;
    logic [FIFO_PTR_W:0] fifo_level;
    logic              fifo_empty_w;
    logic              fifo_full_w;
    logic              fifo_clr_r;

    assign fifo_wr_en = rx_done_w && !fifo_full_w;

    sync_fifo #(
        .DATA_W (8),
        .DEPTH  (FIFO_DEPTH)
    ) u_rx_fifo (
        .clk      (clk),
        .rst_n    (rst_n & ~fifo_clr_r), 
        .i_wr_en  (fifo_wr_en),
        .i_wr_data(rx_data_w),
        .i_rd_en  (fifo_rd_en),
        .o_rd_data(fifo_rd_data),
        .o_full   (fifo_full_w),
        .o_empty  (fifo_empty_w),
        .o_level  (fifo_level)
    );

    assign fifo_empty = fifo_empty_w;
    assign fifo_full  = fifo_full_w;

    // -------------------------------------------------------------------
    // GÖMÜLÜ DMA MANTIĞI: AXI4-Lite Master Durum Makinesi
    // -------------------------------------------------------------------
    typedef enum logic [1:0] {
        M_IDLE   = 2'b00,
        M_WRITE  = 2'b01,
        M_RESP   = 2'b10
    } m_state_t;

    m_state_t m_state;
    logic [M_AXI_ADDR_W-1:0] m_addr_counter_r; // Her yazmada otomatik artan adres sayacı

    // FIFO'dan veri okuma tetiklemesi: Master IDLE durumunda ve FIFO boş değilse
    assign fifo_rd_en = (m_state == M_IDLE) && !fifo_empty_w;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_state          <= M_IDLE;
            m_axil_awaddr    <= '0;
            m_axil_awvalid   <= 1'b0;
            m_axil_wdata     <= '0;
            m_axil_wvalid    <= 1'b0;
            m_axil_wstrb     <= 4'hF;
            m_axil_bready    <= 1'b0;
            m_addr_counter_r <= '0;
        end else begin
            case (m_state)
                M_IDLE: begin
                    m_axil_bready <= 1'b0;
                    
                    // İşlemci yeni adres kurduğunda sayacı güncelle
                    if (s_axil_awvalid && s_axil_awready && (s_axil_awaddr[7:0] == UARTS_TARGET_OFFSET)) begin
                        m_addr_counter_r <= s_axil_wdata;
                    end

                    // FIFO'dan veri okundu, aktarımı başlat
                    if (fifo_rd_en) begin
                        m_axil_awaddr  <= m_addr_counter_r;
                        m_axil_awvalid <= 1'b1;
                        m_axil_wdata   <= {24'b0, fifo_rd_data}; // Bayt verisini 32-bite genişlet
                        m_axil_wvalid  <= 1'b1;
                        m_state        <= M_WRITE;
                    end
                end

                M_WRITE: begin
                    // Adres ve Veri kanallarının el sıkışmalarını takip et
                    if (m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wready)  m_axil_wvalid  <= 1'b0;

                    if ((m_axil_awready || !m_axil_awvalid) && (m_axil_wready || !m_axil_wvalid)) begin
                        m_axil_bready <= 1'b1;
                        m_state       <= M_RESP;
                    end
                end

                M_RESP: begin
                    if (m_axil_bvalid) begin
                        m_axil_bready    <= 1'b0;
                        m_addr_counter_r <= m_addr_counter_r + 4; // Bir sonraki 32-bit kelime adresine geç
                        m_state          <= M_IDLE;
                    end
                end
                default: m_state <= M_IDLE;
            endcase
        end
    end


    // Kesme üretimi
    logic irq_rx_done_s;
    logic irq_fifo_half_s;
    logic irq_fifo_full_s;
    logic irq_tx_done_s;
    logic irq_frame_err_s;

    assign irq_rx_done_s   = reg_irq_en_r[IRQ_RX_DONE]   & rx_done_w;
    assign irq_fifo_half_s = reg_irq_en_r[IRQ_FIFO_HALF]  & (fifo_level >= (FIFO_DEPTH / 2));
    assign irq_fifo_full_s = reg_irq_en_r[IRQ_FIFO_FULL]  & fifo_full_w;
    assign irq_tx_done_s   = reg_irq_en_r[IRQ_TX_DONE]    & tx_done_w;
    assign irq_frame_err_s = reg_irq_en_r[IRQ_FRAME_ERR]  & rx_frame_err_w;

    assign uart_stream_irq = irq_rx_done_s  | irq_fifo_half_s |
                             irq_fifo_full_s| irq_tx_done_s   |
                             irq_frame_err_s;

    // TX tetikleme
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_start_r <= 1'b0;
        else begin
            tx_start_r <= 1'b0;
            if (reg_cfg_r[CFG_TX_EN] && !tx_busy_w)
                tx_start_r <= 1'b1;
        end
    end

    // AXI4-Lite Slave - Yazma Kanalı
    logic aw_active_r;
    logic w_active_r;
    logic [AXI_ADDR_W-1:0] aw_addr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_active_r        <= 1'b0;
            w_active_r         <= 1'b0;
            aw_addr_r          <= '0;
            s_axil_awready     <= 1'b0;
            s_axil_wready      <= 1'b0;
            s_axil_bvalid      <= 1'b0;
            s_axil_bresp       <= AXI_RESP_OKAY;
            reg_cpb_r          <= DEF_CPB;
            reg_stp_r          <= '0;
            reg_tdr_r          <= '0;
            reg_cfg_r          <= '0;
            reg_irq_en_r       <= '0;
            reg_target_addr_r  <= '0;
            fifo_clr_r         <= 1'b0;
        end else begin
            fifo_clr_r <= 1'b0;

            if (rx_done_w)
                reg_cfg_r[CFG_RX_DONE] <= 1'b1;
            if (tx_done_w) begin
                reg_cfg_r[CFG_TX_DONE] <= 1'b1;
                reg_cfg_r[CFG_TX_EN]   <= 1'b0;
            end

            if (s_axil_awvalid && s_axil_awready) begin
                aw_active_r    <= 1'b1;
                aw_addr_r      <= s_axil_awaddr;
                s_axil_awready <= 1'b0;
            end else if (!aw_active_r)
                s_axil_awready <= s_axil_awvalid;

            if (s_axil_wvalid && s_axil_wready) begin
                w_active_r    <= 1'b1;
                s_axil_wready <= 1'b0;
            end else if (!w_active_r)
                s_axil_wready <= s_axil_wvalid;

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
                            reg_cfg_r[CFG_TX_EN]  <= 1'b1;
                        if (!s_axil_wdata[CFG_RX_DONE] && !rx_done_w)
                            reg_cfg_r[CFG_RX_DONE] <= 1'b0;
                        if (!s_axil_wdata[CFG_TX_DONE] && !tx_done_w)
                            reg_cfg_r[CFG_TX_DONE] <= 1'b0;
                    end
                    UARTS_FIFO_CLR_OFFSET: begin
                        if (s_axil_wdata[0]) fifo_clr_r <= 1'b1;
                    end
                    UARTS_IRQ_EN_OFFSET: reg_irq_en_r <= s_axil_wdata;
                    UARTS_TARGET_OFFSET: reg_target_addr_r <= s_axil_wdata; // CPU hedef adresi buraya set eder
                    default: s_axil_bresp <= AXI_RESP_SLVERR;
                endcase
            end

            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;
        end
    end

    // AXI4-Lite Slave - Okuma Kanalı
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= AXI_RESP_OKAY;
        end else begin
            if (s_axil_arvalid && !s_axil_rvalid && !s_axil_arready) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= AXI_RESP_OKAY;

                unique case (s_axil_araddr[7:0])
                    UART_CPB_OFFSET:         s_axil_rdata <= reg_cpb_r;
                    UART_STP_OFFSET:         s_axil_rdata <= reg_stp_r;
                    UART_RDR_OFFSET:         s_axil_rdata <= {24'b0, fifo_rd_data};
                    UART_TDR_OFFSET:         s_axil_rdata <= {24'b0, reg_tdr_r};
                    UART_CFG_OFFSET:         s_axil_rdata <= {29'b0, reg_cfg_r};
                    UARTS_FIFO_LEVEL_OFFSET: s_axil_rdata <= {{(32-FIFO_PTR_W-1){1'b0}}, fifo_level};
                    UARTS_IRQ_EN_OFFSET:     s_axil_rdata <= reg_irq_en_r;
                    UARTS_TARGET_OFFSET:     s_axil_rdata <= reg_target_addr_r;
                    default: begin
                        s_axil_rdata <= '0;
                        s_axil_rresp <= AXI_RESP_SLVERR;
                    end
                endcase
            end else begin
                s_axil_arready <= 1'b0; 
            end

            if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;
        end
    end

endmodule