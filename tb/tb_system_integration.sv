`timescale 1ns / 1ps

module tb_system_integration();

    // Temel Saat ve Reset Sinyalleri
    logic clk_i;
    logic rst_ni;
    
    // UART Sinyalleri
    logic uart0_tx_o;
    logic uart0_rx_i;
    
    // QSPI Arayüz Sinyalleri
    logic qspi_cs_n;
    logic qspi_sclk;
    tri   qspi_io0;
    tri   qspi_io1;
    tri   qspi_io2;
    tri   qspi_io3;

    // Pull-up Dirençleri (Flash Bellek hattının kararlılığı için)
    pullup(qspi_io0);
    pullup(qspi_io1);
    pullup(qspi_io2);
    pullup(qspi_io3);
    pullup(qspi_cs_n);

    // Saat Sinyali (Clock) Üretimi - 50 MHz
    initial begin
        clk_i = 0;
        forever #10 clk_i = ~clk_i; 
    end

    // Reset ve İlk Değer Atamaları
    initial begin
        rst_ni = 0; 
        uart0_rx_i = 1; // UART IDLE durumu
        #100;
        rst_ni = 1; 
    end

    // SoC Top Modülü Çağrımı (DUT)
    tunga_soc_top dut (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .uart0_tx_o (uart0_tx_o),
        .uart0_rx_i (uart0_rx_i)
        
        /* 
        Henüz RTL takımının ana modülünde (tunga_soc_top) QSPI pinleri 
        bulunmadığı için şimdilik bağlantıları yoruma alıyoruz.
        RTL koduna eklendiğinde buradaki yorumlar açılmalıdır.
        // QSPI Portları
        .qspi_cs_n  (qspi_cs_n),
        .qspi_sclk  (qspi_sclk),
        .qspi_io0   (qspi_io0),
        .qspi_io1   (qspi_io1),
        .qspi_io2   (qspi_io2),
        .qspi_io3   (qspi_io3)
        */
    );

    // Resmi Micron QSPI Flash Bellek Modeli Bağlantısı (MT25QL256ABA)
    mt25ql256aba flash_inst (
        .S         (qspi_cs_n),
        .C         (qspi_sclk),
        .HOLD_DQ3  (qspi_io3),
        .DQ0       (qspi_io0),
        .DQ1       (qspi_io1),
        .Vcc       (3300),
        .Vpp_W_DQ2 (qspi_io2)
    );

    // Basit bir UART TX Monitor: Gelen karakterleri ekrana basar
    // Otomasyon scripti "SYSTEM BOOT OK" metnini stdout üzerinden buradan yakalayacak.
    always @(negedge uart0_tx_o) begin
        // Not: Gerçek bir UART RX baud rate üzerinden örnekleme yapmalıdır. 
        // Burada sembolik bir log basımı temsil edilmektedir.
        // $write("%c", character);
    end

endmodule
