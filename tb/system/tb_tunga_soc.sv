`timescale 1ns / 1ps

module tb_tunga_soc;

    // --- 1. Sinyal Tanımlamaları ---
    logic clk_i;
    logic rst_ni;
    
    // UART Sinyalleri
    logic uart0_tx_o;
    // UART RX hatları boşta (idle) durumunda '1' seviyesinde kalmalıdır.
    logic uart0_rx_i = 1'b1; 
    logic uart1_rx_i = 1'b1; 

    // GPIO Sinyalleri (Dummy)
    logic [15:0] gpio_in_i = 16'b0; // Giriş pinlerini 0'a çekiyoruz
    logic [15:0] gpio_out_o;
    logic [15:0] gpio_tx_en_o;

    // I2C Sinyalleri (Dummy)
    wire i2c_scl_io;
    wire i2c_sda_io;

    // QSPI Sinyalleri (Dummy)
    logic       qspi_sck_o;
    logic       qspi_csn_o;
    wire  [3:0] qspi_io;

    // --- 2. Clock (Saat) Sinyali Üretimi (50 MHz) ---
    initial begin
        clk_i = 1'b0;
        // 50 MHz frekans = 20 ns periyot. Her 10 ns'de bir dalga yön değiştirir.
        forever #10 clk_i = ~clk_i; 
    end

    // --- 3. Reset Sinyali Üretimi ---
    initial begin
        rst_ni = 1'b0;      // Başlangıçta sistemi resetle (Aktif Düşük)
        #40;                // 40 nanosaniye bekle (2 saat vuruşu garanti olsun)
        rst_ni = 1'b1;      // Reseti kaldır, işlemci Boot ROM'dan komut okumaya başlasın!
    end

    // --- 4. YENİ SOC_TOP MODÜLÜNÜ ÇAĞIRMA (INSTANTIATION) ---
    soc_top u_soc (
        .clk_i        ( clk_i ),
        .rst_ni       ( rst_ni ),

        // UART Portları
        .uart0_tx_o   ( uart0_tx_o ),
        .uart0_rx_i   ( uart0_rx_i ),
        .uart1_rx_i   ( uart1_rx_i ),

        // GPIO Portları
        .gpio_in_i    ( gpio_in_i ),
        .gpio_out_o   ( gpio_out_o ),
        .gpio_tx_en_o ( gpio_tx_en_o ),

        // I2C Portları
        .i2c_scl_io   ( i2c_scl_io ),
        .i2c_sda_io   ( i2c_sda_io ),

        // QSPI Portları
        .qspi_sck_o   ( qspi_sck_o ),
        .qspi_csn_o   ( qspi_csn_o ),
        .qspi_io      ( qspi_io )
    );

endmodule
