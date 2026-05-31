`timescale 1ns / 1ps

// =============================================================================
// 1. MODÜL: TESTBENCH (tb_gpio_peripheral)
// =============================================================================
module tb_gpio_peripheral;

    // Parametreler
    localparam int AXI_ADDR_W = 8;
    localparam int AXI_DATA_W = 32;
    localparam real CLK_PERIOD = 10.0; // 100 MHz

    // Yazmaç Adresleri
    localparam logic [7:0] ADDR_GPIO_IDR             = 8'h00;
    localparam logic [7:0] ADDR_GPIO_ODR             = 8'h04;
    localparam logic [7:0] ADDR_GPIO_MODE            = 8'h08;
    localparam logic [7:0] ADDR_GPIO_SET             = 8'h0C;
    localparam logic [7:0] ADDR_GPIO_CLEAR           = 8'h10;
    localparam logic [7:0] ADDR_GPIO_TOGGLE          = 8'h14;
    localparam logic [7:0] ADDR_INTRPT_RISE_EN       = 8'h18;
    localparam logic [7:0] ADDR_INTRPT_STATUS        = 8'h28;

    // Sinyaller
    logic                    clk;
    logic                    rst_n;
    logic [15:0]             gpio_i;
    logic [15:0]             gpio_o;
    logic [15:0]             gpio_tx_en_o;
    logic                    global_interrupt_o;

    // AXI4-Lite Sinyalleri
    logic [AXI_ADDR_W-1:0]   s_axil_awaddr;
    logic                    s_axil_awvalid;
    logic                    s_axil_awready;
    logic [AXI_DATA_W-1:0]   s_axil_wdata;
    logic [3:0]              s_axil_wstrb;
    logic                    s_axil_wvalid;
    logic                    s_axil_wready;
    logic [1:0]              s_axil_bresp;
    logic                    s_axil_bvalid;
    logic                    s_axil_bready;
    logic [AXI_ADDR_W-1:0]   s_axil_araddr;
    logic                    s_axil_arvalid;
    logic                    s_axil_arready;
    logic [AXI_DATA_W-1:0]   s_axil_rdata;
    logic [1:0]              s_axil_rresp;
    logic                    s_axil_rvalid;
    logic                    s_axil_rready;

    // --- UUT Örnekleme (Açık ve Net Port Bağlantıları) ---
    gpio_peripheral #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_DATA_W(AXI_DATA_W)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .gpio_i(gpio_i),
        .gpio_o(gpio_o),
        .gpio_tx_en_o(gpio_tx_en_o),
        .global_interrupt_o(global_interrupt_o),
        .s_axil_awaddr(s_axil_awaddr),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata),
        .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid),
        .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid),
        .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata),
        .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready)
    );

    // Clock Üreteci
    always #(CLK_PERIOD/2.0) clk = ~clk;

    // AXI Yazma Fonksiyonu
    task automatic axi_write(input logic [7:0] addr, input logic [31:0] data);
    begin
        @(posedge clk);
        s_axil_awaddr  = addr;
        s_axil_wdata   = data;
        s_axil_awvalid = 1'b1;
        s_axil_wvalid  = 1'b1;
        s_axil_wstrb   = 4'b1111;
        s_axil_bready  = 1'b1;
        @(posedge clk);
        while (!(s_axil_awready && s_axil_wready)) @(posedge clk);
        s_axil_awvalid = 1'b0;
        s_axil_wvalid  = 1'b0;
        while (!s_axil_bvalid) @(posedge clk);
        s_axil_bready  = 1'b0;
        $display("[AXI WRITE] Adres: 0x%02h, Veri: 0x%08h", addr, data);
        repeat(2) @(posedge clk);
    end
    endtask

    // AXI Okuma Fonksiyonu
    task automatic axi_read(input logic [7:0] addr, output logic [31:0] rdata);
    begin
        @(posedge clk);
        s_axil_araddr  = addr;
        s_axil_arvalid = 1'b1;
        s_axil_rready  = 1'b1;
        @(posedge clk);
        while (!s_axil_arready) @(posedge clk);
        s_axil_arvalid = 1'b0;
        while (!s_axil_rvalid) @(posedge clk);
        rdata = s_axil_rdata;
        s_axil_rready  = 1'b0;
        $display("[AXI READ]  Adres: 0x%02h, Veri: 0x%08h", addr, rdata);
        repeat(2) @(posedge clk);
    end
    endtask

    // Test Akışı
    initial begin
        logic [31:0] read_buffer;

        // Sinyal Sıfırlama
        clk            = 1'b0;
        rst_n          = 1'b0;
        gpio_i         = 16'h0000;
        s_axil_awaddr  = '0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata   = '0;
        s_axil_wstrb   = '0;
        s_axil_wvalid  = 1'b0;
        s_axil_bready  = 1'b0;
        s_axil_araddr  = '0;
        s_axil_arvalid = 1'b0;
        s_axil_rready  = 1'b0;

        // Reset Süreci
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);
        $display("--- GpiO Test Akisi Basladi ---");

        // TEST 1: Çıkış Modu ve ODR Yazma
        axi_write(ADDR_GPIO_MODE, 32'h5555_5555); // Tüm pinler output aktif
        axi_write(ADDR_GPIO_ODR, 32'hA5A5);
        
        // TEST 2: Maskeli Set/Clear/Toggle
        axi_write(ADDR_GPIO_SET, 32'hF000); 
        axi_write(ADDR_GPIO_CLEAR, 32'h000F);
        axi_write(ADDR_GPIO_TOGGLE, 32'h0FF0);
        axi_read(ADDR_GPIO_ODR, read_buffer);

        // TEST 3: Giriş Modu ve Okuma (IDR)
        axi_write(ADDR_GPIO_MODE, 32'h5555_5500); // Pin 0-3 giriş modunda
        gpio_i = 16'h5A5A;
        #(CLK_PERIOD * 5); // Örnekleme gecikmesi
        axi_read(ADDR_GPIO_IDR, read_buffer);

        // TEST 4: Kesme Tetikleme ve Temizleme
        axi_write(ADDR_INTRPT_RISE_EN, 32'h0001); // Pin 0 için yükselen kenar kesmesi
        gpio_i[0] = 1'b0;
        #(CLK_PERIOD * 2);
        gpio_i[0] = 1'b1; // Kenar oluşturuldu
        #(CLK_PERIOD * 5);

        if (global_interrupt_o) $display("[SUCCESS] Global Kesme Alindi!");
        
        axi_read(ADDR_INTRPT_STATUS, read_buffer);
        axi_write(ADDR_INTRPT_STATUS, read_buffer); // W1C ile temizle
        #(CLK_PERIOD * 2);

        $display("--- Tum Senaryolar Basariyla Yonetildi ---");
        $finish;
    end

endmodule


// =============================================================================
// 2. MODÜL: TASARIM ÇEKİRDEĞİ (gpio_peripheral) - Vivado Bulabilsin Diye Altına Eklendi
// =============================================================================
module gpio_peripheral #(
    parameter int AXI_ADDR_W = 8,
    parameter int AXI_DATA_W = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [15:0]             gpio_i,
    output logic [15:0]             gpio_o,
    output logic [15:0]             gpio_tx_en_o,
    output logic                    global_interrupt_o,
    input  logic [AXI_ADDR_W-1:0]   s_axil_awaddr,
    input  logic                    s_axil_awvalid,
    output logic                    s_axil_awready,
    input  logic [AXI_DATA_W-1:0]   s_axil_wdata,
    input  logic [3:0]              s_axil_wstrb,
    input  logic                    s_axil_wvalid,
    output logic                    s_axil_wready,
    output logic [1:0]              s_axil_bresp,
    output logic                    s_axil_bvalid,
    input  logic                    s_axil_bready,
    input  logic [AXI_ADDR_W-1:0]   s_axil_araddr,
    input  logic                    s_axil_arvalid,
    output logic                    s_axil_arready,
    output logic [AXI_DATA_W-1:0]   s_axil_rdata,
    output logic [1:0]              s_axil_rresp,
    output logic                    s_axil_rvalid,
    input  logic                    s_axil_rready
);

    localparam logic [7:0] ADDR_GPIO_IDR             = 8'h00;
    localparam logic [7:0] ADDR_GPIO_ODR             = 8'h04;
    localparam logic [7:0] ADDR_GPIO_MODE            = 8'h08;
    localparam logic [7:0] ADDR_GPIO_SET             = 8'h0C;
    localparam logic [7:0] ADDR_GPIO_CLEAR           = 8'h10;
    localparam logic [7:0] ADDR_GPIO_TOGGLE          = 8'h14;
    localparam logic [7:0] ADDR_INTRPT_RISE_EN       = 8'h18;
    localparam logic [7:0] ADDR_INTRPT_FALL_EN       = 8'h1C;
    localparam logic [7:0] ADDR_INTRPT_LVL_HIGH_EN   = 8'h20;
    localparam logic [7:0] ADDR_INTRPT_LVL_LOW_EN    = 8'h24;
    localparam logic [7:0] ADDR_INTRPT_STATUS        = 8'h28;

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    logic [15:0] reg_odr;
    logic [31:0] reg_mode_expanded; 
    logic [15:0] reg_intrpt_rise_en;
    logic [15:0] reg_intrpt_fall_en;
    logic [15:0] reg_intrpt_lvl_high_en;
    logic [15:0] reg_intrpt_lvl_low_en;
    
    logic [15:0] status_rise;
    logic [15:0] status_fall;
    logic [15:0] status_lvl_high;
    logic [15:0] status_lvl_low;

    logic [15:0] gpio_in_q1, gpio_in_q2, gpio_in_q3;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_in_q1 <= '0;
            gpio_in_q2 <= '0;
            gpio_in_q3 <= '0;
        end else begin
            gpio_in_q1 <= gpio_i;
            gpio_in_q2 <= gpio_in_q1;
            gpio_in_q3 <= gpio_in_q2;
        end
    end

    logic [15:0] s_gpio_rise_edge, s_gpio_fall_edge;
    assign s_gpio_rise_edge = gpio_in_q2 & ~gpio_in_q3;
    assign s_gpio_fall_edge = ~gpio_in_q2 & gpio_in_q3;

    logic [15:0] s_gpio_rise_intrpt, s_gpio_fall_intrpt, s_gpio_high_intrpt, s_gpio_low_intrpt;
    assign s_gpio_rise_intrpt = s_gpio_rise_edge & reg_intrpt_rise_en;
    assign s_gpio_fall_intrpt = s_gpio_fall_edge & reg_intrpt_fall_en;
    assign s_gpio_high_intrpt = gpio_in_q2        & reg_intrpt_lvl_high_en;
    assign s_gpio_low_intrpt  = ~gpio_in_q2       & reg_intrpt_lvl_low_en;

    logic [15:0] interrupts_pending;
    assign interrupts_pending = status_rise | status_fall | status_lvl_high | status_lvl_low;
    assign global_interrupt_o = |interrupts_pending;

    logic [AXI_ADDR_W-1:0] write_addr;

    assign s_axil_awready = ~s_axil_bvalid && s_axil_awvalid && s_axil_wvalid;
    assign s_axil_wready  = ~s_axil_bvalid && s_axil_awvalid && s_axil_wvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_bvalid          <= 1'b0;
            s_axil_bresp           <= RESP_OKAY;
            reg_odr                <= '0;
            reg_mode_expanded      <= '0;
            reg_intrpt_rise_en     <= '0;
            reg_intrpt_fall_en     <= '0;
            reg_intrpt_lvl_high_en <= '0;
            reg_intrpt_lvl_low_en  <= '0;
            status_rise            <= '0;
            status_fall            <= '0;
            status_lvl_high        <= '0;
            status_lvl_low         <= '0;
        end else begin
            status_rise     <= status_rise     | s_gpio_rise_intrpt;
            status_fall     <= status_fall     | s_gpio_fall_intrpt;
            status_lvl_high <= status_lvl_high | s_gpio_high_intrpt;
            status_lvl_low  <= status_lvl_low  | s_gpio_low_intrpt;

            if (s_axil_awvalid && s_axil_wvalid && !s_axil_bvalid) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= RESP_OKAY;
                write_addr    = s_axil_awaddr;

                unique case (write_addr[7:0])
                    ADDR_GPIO_ODR:           reg_odr                <= s_axil_wdata[15:0];
                    ADDR_GPIO_MODE:          reg_mode_expanded      <= s_axil_wdata;
                    ADDR_GPIO_SET:           reg_odr                <= reg_odr | s_axil_wdata[15:0];
                    ADDR_GPIO_CLEAR:         reg_odr                <= reg_odr & ~s_axil_wdata[15:0];
                    ADDR_GPIO_TOGGLE:        reg_odr                <= reg_odr ^ s_axil_wdata[15:0];
                    ADDR_INTRPT_RISE_EN:     reg_intrpt_rise_en     <= s_axil_wdata[15:0];
                    ADDR_INTRPT_FALL_EN:     reg_intrpt_fall_en     <= s_axil_wdata[15:0];
                    ADDR_INTRPT_LVL_HIGH_EN: reg_intrpt_lvl_high_en <= s_axil_wdata[15:0];
                    ADDR_INTRPT_LVL_LOW_EN:  reg_intrpt_lvl_low_en  <= s_axil_wdata[15:0];
                    ADDR_INTRPT_STATUS: begin
                        status_rise     <= (status_rise     | s_gpio_rise_intrpt)     & ~s_axil_wdata[15:0];
                        status_fall     <= (status_fall     | s_gpio_fall_intrpt)     & ~s_axil_wdata[15:0];
                        status_lvl_high <= (status_lvl_high | s_gpio_high_intrpt)     & ~s_axil_wdata[15:0];
                        status_lvl_low  <= (status_lvl_low  | s_gpio_low_intrpt)      & ~s_axil_wdata[15:0];
                    end
                    default: s_axil_bresp <= RESP_SLVERR;
                endcase
            end

            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    assign gpio_o = reg_odr;

    generate
        for (genvar i = 0; i < 16; i++) begin : gen_mode_control
            always_comb begin
                logic [1:0] pin_mode;
                pin_mode = reg_mode_expanded[(2*i)+1 : 2*i];
                case (pin_mode)
                    2'b00:   gpio_tx_en_o[i] = 1'b0;
                    2'b01:   gpio_tx_en_o[i] = 1'b1;
                    2'b10:   gpio_tx_en_o[i] = reg_odr[i];
                    2'b11:   gpio_tx_en_o[i] = ~reg_odr[i];
                    default: gpio_tx_en_o[i] = 1'b0;
                endcase
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= RESP_OKAY;
        end else begin
            if (s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= RESP_OKAY;

                unique case (s_axil_araddr[7:0])
                    ADDR_GPIO_IDR:           s_axil_rdata <= {16'h0000, gpio_in_q2};
                    ADDR_GPIO_ODR:           s_axil_rdata <= {16'h0000, reg_odr};
                    ADDR_GPIO_MODE:          s_axil_rdata <= reg_mode_expanded;
                    ADDR_INTRPT_RISE_EN:     s_axil_rdata <= {16'h0000, reg_intrpt_rise_en};
                    ADDR_INTRPT_FALL_EN:     s_axil_rdata <= {16'h0000, reg_intrpt_fall_en};
                    ADDR_INTRPT_LVL_HIGH_EN: s_axil_rdata <= {16'h0000, reg_intrpt_lvl_high_en};
                    ADDR_INTRPT_LVL_LOW_EN:  s_axil_rdata <= {16'h0000, reg_intrpt_lvl_low_en};
                    ADDR_INTRPT_STATUS:      s_axil_rdata <= {16'h0000, interrupts_pending};
                    default: begin
                        s_axil_rdata <= '0;
                        s_axil_rresp <= RESP_SLVERR;
                    end
                endcase
            end else begin
                s_axil_arready <= 1'b0;
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

endmodule