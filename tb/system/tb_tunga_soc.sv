`timescale 1ns / 1ps

module tb_tunga_soc();

    // Sinyal Tanımlamaları
    logic clk_i;
    logic rst_ni;
    logic uart0_tx_o;
    logic uart0_rx_i;

    // Saat Sinyali (Clock) Üretimi - 50 MHz
    initial begin
        clk_i = 0;
        forever #10 clk_i = ~clk_i; 
    end

    // Reset Sinyali Üretimi
    initial begin
        rst_ni = 0; // Sistemi sıfırla (Active Low)
        #50;        // 50 nanosaniye bekle
        rst_ni = 1; // Sıfırlamayı kaldır, sistem çalışmaya başlasın
        uart0_rx_i = 1; // UART hattını idle (boşta) durumuna çek
    end

    // Top Modülü Çağırma (DUT - Design Under Test)
    tunga_soc_top dut (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .uart0_tx_o (uart0_tx_o),
        .uart0_rx_i (uart0_rx_i)
    );

endmodule