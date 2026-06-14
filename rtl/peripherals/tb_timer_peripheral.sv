`timescale 1ns / 1ps

module tb_timer_peripheral();

    logic        clk;
    logic        rst_n;
    
    // AXI Signalleri
    logic [11:0] s_axil_awaddr;
    logic        s_axil_awvalid;
    logic        s_axil_awready;
    logic [31:0] s_axil_wdata;
    logic [3:0]  s_axil_wstrb;
    logic        s_axil_wvalid;
    logic        s_axil_wready;
    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid;
    logic        s_axil_bready;
    logic [11:0] s_axil_araddr;
    logic        s_axil_arvalid;
    logic        s_axil_arready;
    logic [31:0] s_axil_rdata;
    logic [1:0]  s_axil_rresp;
    logic        s_axil_rvalid;
    logic        s_axil_rready;

    // UUT Çağrısı
    timer_peripheral uut (.*);

    // 100 MHz Saat Üretimi
    initial clk = 0;
    always #5 clk = ~clk;

    // AXI Bus Görevleri (Tasks)
    task axi_write(input logic [7:0] addr, input logic [31:0] data);
        begin
            s_axil_awaddr  = {4'h0, addr};
            s_axil_wdata   = data;
            s_axil_awvalid = 1'b1;
            s_axil_wvalid  = 1'b1;
            s_axil_wstrb   = 4'b1111;
            s_axil_bready  = 1'b1;
            
            wait (s_axil_awready && s_axil_wready);
            @(posedge clk);
            s_axil_awvalid = 1'b0;
            s_axil_wvalid  = 1'b0;
            
            wait (s_axil_bvalid);
            @(posedge clk);
            s_axil_bready  = 1'b0;
            #10;
        end
    endtask

    task axi_read(input logic [7:0] addr, output logic [31:0] data);
        begin
            s_axil_araddr  = {4'h0, addr};
            s_axil_arvalid = 1'b1;
            s_axil_rready  = 1'b1;
            
            wait (s_axil_arready);
            @(posedge clk);
            s_axil_arvalid = 1'b0;
            
            wait (s_axil_rvalid);
            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready  = 1'b0;
            #10;
        end
    endtask

    // --- Ana Test Senaryosu ---
    logic [31:0] read_buffer;
    
    initial begin
        // Sinyal İlklendirmesi
        rst_n          = 1'b0;
        s_axil_awaddr  = '0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata   = '0;
        s_axil_wstrb   = '0;
        s_axil_wvalid  = 1'b0;
        s_axil_bready  = 1'b0;
        s_axil_araddr  = '0;
        s_axil_arvalid = 1'b0;
        s_axil_rready  = 1'b0;
        
        #100;
        rst_n = 1'b1;
        #40;
        
        $display("======= TEKNOFEST 2026 TIMER PROGRAMMABLE TEST BAŞLADI =======");
        
        // 1. Konfigürasyon: Prescaler = 2, Auto-Reload = 5, Mod = Yukarı (1)
        $display("[TB] Konfigürasyon yazmaçları yükleniyor...");
        axi_write(8'h00, 32'd2); // TIM_PRE = 2 (Her 3 clockta bir 1 artacak)
        axi_write(8'h04, 32'd5); // TIM_ARE = 5
        axi_write(8'h10, 32'd1); // TIM_MOD = Yukarı (1)
        
        // 2. Timer'ı Ateşle (TIM_ENA = 1)
        $display("[TB] Timer aktif ediliyor...");
        axi_write(8'h0C, 32'd1);
        
        // Bir süre sayacı koştur
        #300;
        
        // 3. Sayacı oku ve kontrol et (Self-Checking)
        axi_read(8'h14, read_buffer); // TIM_CNT Oku
        $display("[TB] Güncel Sayaç Değeri (TIM_CNT): %d", read_buffer);
        
        if (read_buffer > 0 && read_buffer <= 5) begin
            $display("[PASS] Sayaç normal aralıkta çalışıyor.");
        end else begin
            $display("[FAIL] Sayaç kilitlenmiş veya hatalı: %d", read_buffer);
        end

        // 4. Auto-Reload ve Event Kontrolü için bekle
        #400;
        axi_read(8'h18, read_buffer); // TIM_EVN Oku (Kaç kere taştı?)
        $display("[TB] Tetiklenen Toplam Event Sayısı (TIM_EVN): %d", read_buffer);
        
        if (read_buffer > 0) begin
            $display("[PASS] Auto-Reload ve Event mekanizması başarıyla çalıştı!");
        end else begin
            $display("[FAIL] Event üretilemedi, FSM adres taşmasını algılayamadı.");
        end

        // 5. Temizleme Testi (TIM_CLR = 1)
        $display("[TB] Sayaç sıfırlama (Clear) komutu basılıyor...");
        axi_write(8'h08, 32'd1);
        #10;
        axi_read(8'h14, read_buffer);
        if (read_buffer == 0) begin
            $display("[PASS] TIM_CLR fonksiyonu başarıyla sıfırladı.");
        end else begin
            $display("[FAIL] Sıfırlama komutuna rağmen sayaç sıfırlanmadı: %d", read_buffer);
        end

        $display("======= TIMER DOĞRULAMA TESTİ TAMAMLANDI =======");
        $finish;
    end

endmodule