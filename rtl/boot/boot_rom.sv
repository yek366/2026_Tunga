`timescale 1ns / 1ps

// AXI4-Lite read-only 1KB senkron boot ROM

module boot_rom(
    input logic clk,
    input logic rst_n,

    // AXI-Lite Read Address Kanalı
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // AXI-Lite Read Data Kanalı
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);

    // 1KB Kapasite
    logic [31:0] mem [0:255];

    // Test kodunu (helloworld.mem) ROM'a yükle
    initial begin
        $readmemh("helloworld.mem", mem);
    end

    // ROM, veri tutmuyorsa veya işlemci bu cycle veriyi alıyorsa yeni adres alabilir
    assign s_axi_arready = !s_axi_rvalid || s_axi_rready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'b0;
            s_axi_rresp  <= 2'b00;
        end else begin
            
            // 1- İŞLEMCİ ADRESİ VERDİ, BİZ DE HAZIRIZ DEDİK (El Sıkışma)
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;                      // Veriyi yollamaya başla
                s_axi_rdata  <= mem[s_axi_araddr[9:2]];    // Adresi kelimeye (word) hizala
                s_axi_rresp  <= 2'b00;                     // OKAY mesajı
            end 
            
            // 2- İŞLEMCİ VERİYİ ALDIĞINI ONAYLADI (İşlem Bitti)
            else if (s_axi_rready) begin
                s_axi_rvalid <= 1'b0;                      // Hattı boşa çıkar, yeni adres bekle
            end

        end
    end

endmodule