`timescale 1ns / 1ps

// UVM Macros (Eğer UVM framework kullanılacaksa)
// `include "uvm_macros.svh"
// import uvm_pkg::*;

module tb_tunga_soc_modified();

    // Sinyal Tanımlamaları
    logic clk_i;
    logic rst_ni;
    logic uart0_tx_o;
    logic uart0_rx_i;

    // AXI VIP için örnek arayüz (Interface) tanımlamaları
    // wire [31:0] axi_awaddr, axi_wdata, axi_araddr, axi_rdata;
    // wire axi_awvalid, axi_awready, axi_wvalid, axi_wready;
    // wire axi_bvalid, axi_bready, axi_arvalid, axi_arready, axi_rvalid, axi_rready;

    // DPI-C Fonksiyon Tanımlaması (Spike ISS Köprüsü)
    import "DPI-C" context function void spike_step(input logic clk, input logic rst_n);

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

    // DPI-C Spike Co-Simulation Çağrısı
    // Her saat vuruşunun pozitif kenarında Spike ISS'i ilerlet
    always @(posedge clk_i) begin
        if (rst_ni) begin
            spike_step(clk_i, rst_ni);
        end
    end

    // Top Modülü Çağırma (DUT - Design Under Test)
    tunga_soc_top dut (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .uart0_tx_o (uart0_tx_o),
        .uart0_rx_i (uart0_rx_i)
        // AXI sinyalleri buraya bağlanmalıdır
    );

    // Açık Kaynak AXI VIP / Protocol Monitor (Şablon)
    /*
    axi_protocol_monitor #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) axi_vip_inst (
        .clk(clk_i),
        .rst_n(rst_ni),
        // AXI bağlantıları
        .awaddr(dut.axi_awaddr),
        .awvalid(dut.axi_awvalid),
        .awready(dut.axi_awready),
        // (Diğer AXI sinyalleri)
        .error_flag()
    );

    // Protokol İhlali Kontrolü
    always @(posedge clk_i) begin
        if (axi_vip_inst.error_flag) begin
            $display("[UVM_ERROR] AXI Protocol Violation detected at time %0t", $time);
            // `uvm_error("AXI_VIP", "Protocol Violation Detected")
        end
    end
    */

endmodule
