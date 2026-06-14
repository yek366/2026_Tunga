`timescale 1ns / 1ps

module soc_top (
    input  logic clk_i,
    input  logic rst_ni,
    output logic uart0_tx_o,
    input  logic uart0_rx_i
);

    // İşlemci İç Sinyalleri
    logic        instr_req, instr_gnt, instr_rvalid;
    logic [31:0] instr_addr, instr_rdata;
    
    logic        data_req, data_gnt, data_rvalid, data_we;
    logic [3:0]  data_be;
    logic [31:0] data_addr, data_wdata, data_rdata;

    // =========================================================
    // 1. İŞLEMCİ (CV32E40P Çekirdeği)
    // =========================================================
    cv32e40p_core u_core (
        .clk_i(clk_i), .rst_ni(rst_ni), .pulp_clock_en_i(1'b1), .scan_cg_en_i(1'b0),
        .boot_addr_i(32'h0000_0000), 
        .fetch_enable_i(1'b1),
        .mtvec_addr_i(32'h0), .dm_halt_addr_i(32'h0), .dm_exception_addr_i(32'h0), .hart_id_i(32'h0),
        
        .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_rvalid_i(instr_rvalid), .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata),
        .data_req_o(data_req), .data_gnt_i(data_gnt), .data_rvalid_i(data_rvalid), .data_we_o(data_we), .data_be_o(data_be), .data_addr_o(data_addr), .data_wdata_o(data_wdata), .data_rdata_i(data_rdata),
        
        .irq_i(32'b0), .irq_ack_o(), .irq_id_o(), .core_sleep_o()
    );

    // =========================================================
    // 2. BOOT ROM
    // =========================================================
    boot_rom u_boot_rom (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .s_axi_araddr   (instr_addr),
        .s_axi_arvalid  (instr_req),
        .s_axi_arready  (instr_gnt),   
        .s_axi_rdata    (instr_rdata),
        .s_axi_rresp    (),
        .s_axi_rvalid   (instr_rvalid),
        .s_axi_rready   (1'b1)         
    );

    // =========================================================
    // 3. ADRES DEKODER (Trafik Polisi)
    // =========================================================
    typedef enum logic [1:0] {IDLE, WAIT_WRITE, WAIT_READ} state_t;
    state_t state;

    // Strictly decoded base addresses and ranges
    wire is_sram = (data_addr >= 32'h2000_0000) && (data_addr < 32'h2000_2000); // 8KB SRAM
    wire is_uart = (data_addr >= 32'h4002_0000) && (data_addr < 32'h4002_0100); // UART (256 bytes)

    // Busy signal indicating that the OBI-to-AXI bridge is busy with a multi-cycle access
    wire bus_busy = (state != IDLE);

    wire is_unmapped = data_req && !is_sram && !is_uart && !bus_busy;

    // Bus fault handler (Default Slave) dummy rvalid
    logic dummy_rvalid;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) dummy_rvalid <= 1'b0;
        else         dummy_rvalid <= is_unmapped;
    end

    // =========================================================
    // 4. DATA SRAM 
    // =========================================================
    logic sram_gnt, sram_rvalid;
    logic [31:0] sram_rdata;

    tunga_sram u_sram (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .req_i    (data_req && is_sram && !bus_busy), 
        .gnt_o    (sram_gnt),
        .addr_i   (data_addr),
        .we_i     (data_we),
        .be_i     (data_be),
        .wdata_i  (data_wdata),
        .rvalid_o (sram_rvalid),
        .rdata_o  (sram_rdata)
    );

    // =========================================================
    // 5. UART İÇİN OBI -> AXI-LITE KÖPRÜSÜ
    // =========================================================

    typedef enum logic [1:0] {
        DEST_NONE,
        DEST_SRAM,
        DEST_UART,
        DEST_UNMAPPED
    } dest_t;
    dest_t active_dest;

    logic uart_gnt, uart_rvalid;
    logic [31:0] uart_bridge_rdata;

    logic [31:0] awaddr, araddr;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;
    logic awvalid, wvalid, arvalid;

    logic awready_uart, wready_uart, bvalid_uart, arready_uart, rvalid_uart;
    logic [31:0] rdata_uart;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state             <= IDLE;
            uart_gnt          <= 1'b0;
            awvalid           <= 1'b0;
            wvalid            <= 1'b0;
            arvalid           <= 1'b0;
            awaddr            <= '0;
            wdata_reg         <= '0;
            wstrb_reg         <= '0;
            araddr            <= '0;
            uart_bridge_rdata <= '0;
            active_dest       <= DEST_NONE;
        end else begin
            uart_gnt          <= 1'b0;

            // Track active transaction destination for routing responses correctly
            if (data_req && data_gnt) begin
                if (is_sram)      active_dest <= DEST_SRAM;
                else if (is_uart) active_dest <= DEST_UART;
                else              active_dest <= DEST_UNMAPPED;
            end else if (data_rvalid) begin
                active_dest <= DEST_NONE;
            end

            case (state)
                IDLE: begin
                    if (data_req && is_uart) begin
                        uart_gnt <= 1'b1; // CPU'ya onay ver
                        if (data_we) begin
                            awaddr    <= data_addr;
                            wdata_reg <= data_wdata;
                            wstrb_reg <= data_be;
                            awvalid   <= 1'b1;
                            wvalid    <= 1'b1;
                            state     <= WAIT_WRITE;
                        end else begin
                            araddr    <= data_addr;
                            arvalid   <= 1'b1;
                            state     <= WAIT_READ;
                        end
                    end else begin
                        awvalid   <= 1'b0;
                        wvalid    <= 1'b0;
                        arvalid   <= 1'b0;
                    end
                end
                
                WAIT_WRITE: begin
                    if (awready_uart) awvalid <= 1'b0; 
                    if (wready_uart)  wvalid  <= 1'b0;
                    
                    if (bvalid_uart) begin // UART yazmayı bitirdi!
                        awvalid <= 1'b0;
                        wvalid  <= 1'b0;
                        state   <= IDLE;
                    end
                end
                
                WAIT_READ: begin
                    if (arready_uart) arvalid <= 1'b0; 
                    
                    if (rvalid_uart) begin // UART okumayı bitirdi!
                        uart_bridge_rdata <= rdata_uart;
                        arvalid           <= 1'b0;
                        state             <= IDLE;
                    end
                end
            endcase
        end
    end

    // Combinational response signals for the UART bridge
    assign uart_rvalid = (state == WAIT_WRITE && bvalid_uart) || (state == WAIT_READ && rvalid_uart);

    // İşlemci İçin Ana Sinyal Birleştirme (Mux)
    assign data_gnt    = (is_sram) ? sram_gnt    : ((is_uart) ? uart_gnt    : (data_req && !bus_busy)); 
    assign data_rvalid = (active_dest == DEST_SRAM) ? sram_rvalid :
                         (active_dest == DEST_UART) ? uart_rvalid :
                         (active_dest == DEST_UNMAPPED) ? dummy_rvalid : 1'b0;
    assign data_rdata  = (active_dest == DEST_SRAM) ? sram_rdata  :
                         (active_dest == DEST_UART) ? (state == WAIT_READ ? rdata_uart : uart_bridge_rdata) :
                         32'hDEADBEEF;

    // =========================================================
    // 6. ENES'İN UART MODÜLÜ (AXI-Lite Slave)
    // =========================================================
    uart_stream_peripheral u_uart (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        
        .s_axil_awaddr   (awaddr[7:0]),
        .s_axil_awvalid  (awvalid),
        .s_axil_awready  (awready_uart),
        .s_axil_wdata    (wdata_reg),
        .s_axil_wstrb    (wstrb_reg),
        .s_axil_wvalid   (wvalid),
        .s_axil_wready   (wready_uart),
        .s_axil_bresp    (),
        .s_axil_bvalid   (bvalid_uart),
        .s_axil_bready   (1'b1),

        .s_axil_araddr   (araddr[7:0]),
        .s_axil_arvalid  (arvalid),
        .s_axil_arready  (arready_uart),
        .s_axil_rdata    (rdata_uart),
        .s_axil_rresp    (),
        .s_axil_rvalid   (rvalid_uart),
        .s_axil_rready   (1'b1),

        .m_axil_awready  (1'b0),
        .m_axil_wready   (1'b0),
        .m_axil_bvalid   (1'b0),

        .uart_rxd        (uart0_rx_i),
        .uart_txd        (uart0_tx_o),
        .uart_stream_irq (),
        .fifo_empty      (),
        .fifo_full       ()
    );

endmodule