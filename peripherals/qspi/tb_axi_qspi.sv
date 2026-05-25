`timescale 1ns / 1ps

module tb_axi_qspi();

    // --- Parametreler ---
    parameter integer C_S00_AXI_DATA_WIDTH = 32;
    parameter integer C_S00_AXI_ADDR_WIDTH = 4; // 4 bit = 16 byte adres alanı (0x0, 0x4, 0x8, 0xC)

    // --- Saat ve Reset Sinyalleri ---
    reg s00_axi_aclk = 0;
    reg s00_axi_aresetn = 0;

    // --- AXI-Lite Master (Testbench) Sinyalleri ---
    reg [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr = 0;
    reg [2 : 0] s00_axi_awprot = 0;
    reg  s00_axi_awvalid = 0;
    wire s00_axi_awready;
    reg [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata = 0;
    reg [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb = 4'b1111;
    reg  s00_axi_wvalid = 0;
    wire s00_axi_wready;
    wire [1 : 0] s00_axi_bresp;
    wire s00_axi_bvalid;
    reg  s00_axi_bready = 1; // Her zaman yanıt almaya hazırız
    
    reg [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr = 0;
    reg [2 : 0] s00_axi_arprot = 0;
    reg  s00_axi_arvalid = 0;
    wire s00_axi_arready;
    wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata;
    wire [1 : 0] s00_axi_rresp;
    wire s00_axi_rvalid;
    reg  s00_axi_rready = 1;

    // --- QSPI Dış Dünya Sinyalleri ---
    wire SCLK_pad;
    wire CS_pad;
//    wire IO0_pad, IO1_pad, IO2_pad, IO3_pad;
wire [3:0] dq_pad;

    // --- Saat Üretimi (100 MHz) ---
    always #5 s00_axi_aclk = ~s00_axi_aclk;

    // --- UUT: Kendi AXI IP'n ---
    axi_qspi_T_v1_0 # ( 
        .C_S00_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) uut (
        // QSPI Portları
        .SCLK_pad(SCLK_pad),
        .CS_pad(CS_pad),
//        .IO0_pad(IO0_pad),
//        .IO1_pad(IO1_pad),
//        .IO2_pad(IO2_pad),
//        .IO3_pad(IO3_pad),
        .dq_pad(dq_pad),
        // AXI Portları
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .s00_axi_awaddr(s00_axi_awaddr),
        .s00_axi_awprot(s00_axi_awprot),
        .s00_axi_awvalid(s00_axi_awvalid),
        .s00_axi_awready(s00_axi_awready),
        .s00_axi_wdata(s00_axi_wdata),
        .s00_axi_wstrb(s00_axi_wstrb),
        .s00_axi_wvalid(s00_axi_wvalid),
        .s00_axi_wready(s00_axi_wready),
        .s00_axi_bresp(s00_axi_bresp),
        .s00_axi_bvalid(s00_axi_bvalid),
        .s00_axi_bready(s00_axi_bready),
        .s00_axi_araddr(s00_axi_araddr),
        .s00_axi_arprot(s00_axi_arprot),
        .s00_axi_arvalid(s00_axi_arvalid),
        .s00_axi_arready(s00_axi_arready),
        .s00_axi_rdata(s00_axi_rdata),
        .s00_axi_rresp(s00_axi_rresp),
        .s00_axi_rvalid(s00_axi_rvalid),
        .s00_axi_rready(s00_axi_rready)
    );

    // --- Akıllı Kukla (Ajan) Flash Modeli ---
 smart_dummy_flash flash_memory (
        .S          (CS_pad),
        .C_         (SCLK_pad),
        .DQ0        (dq_pad[0]),
        .DQ1        (dq_pad[1]),
        .DQ2        (dq_pad[2]),
        .DQ3        (dq_pad[3])
    );

    // =========================================================
    // AXI WRITE TASK (Bunu bir işlemci gibi kullanacağız)
    // =========================================================
    task axi_write;
        input [C_S00_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S00_AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge s00_axi_aclk);
            s00_axi_awaddr <= addr;
            s00_axi_awvalid <= 1;
            s00_axi_wdata <= data;
            s00_axi_wvalid <= 1;
            
            // Adres kabul edilene kadar bekle
            wait(s00_axi_awready == 1);
            @(posedge s00_axi_aclk);
            s00_axi_awvalid <= 0;
            
            // Data kabul edilene kadar bekle
            wait(s00_axi_wready == 1);
            @(posedge s00_axi_aclk);
            s00_axi_wvalid <= 0;
            
            // Response gelene kadar bekle
            wait(s00_axi_bvalid == 1);
            @(posedge s00_axi_aclk);
        end
    endtask

    // =========================================================
    // TEST SENARYOSU
    // =========================================================
    initial begin
        $display("====================================================");
        $display("[%0t] AXI-Lite IP Testi Basliyor...", $time);
        $display("====================================================");
        
        // Reset periyodu
        s00_axi_aresetn = 0;
        #100;
        s00_axi_aresetn = 1;
        #50;

        // VARSAYILAN REGISTER HARİTASI (Kendi tasarımına göre adresleri uyarla)
        // Offset 0x00 (slv_reg0) : Kontrol Register (Örn: Bit 0 = Start, Bit 2:1 = Mode, Bit 3 = TX_EN)
        // Offset 0x04 (slv_reg1) : TX FIFO Data Register
        
        // ---------------------------------------------------------
        // TEST 1: 1x Modunda (0x03) Komut Gönderimi
        // ---------------------------------------------------------
        $display("\n[%0t] TEST 1: TX FIFO'ya Veri Yaziliyor (0x03)...", $time);
        axi_write(4'h8, 32'h00000003); // slv_reg1'e (FIFO) 0x03 verisini yaz
        
        $display("[%0t] TEST 1: Motor Tetikleniyor (1x Modu, TX_EN=1, Start=1)...", $time);
        // slv_reg0: Mode=00, TX_EN=1, Start=1 -> Binary: 0000_1001 = 0x9
        axi_write(4'h0, 32'h00000009); 
        
        $display("[%0t] TEST 1: Motor Tetiklendi. Start Sinyali Indiriliyor...", $time);
        // slv_reg0: Start bitini sıfırla (0x8)
        axi_write(4'h0, 32'h00000008); 
        
        #500; // İşlemin bitmesi için bekle

        // ---------------------------------------------------------
        // TEST 2: 4x Modunda (0x6B) Komut Gönderimi
        // ---------------------------------------------------------
        $display("\n[%0t] TEST 2: TX FIFO'ya Veri Yaziliyor (0x6B)...", $time);
        axi_write(4'h8, 32'h0000006B); 
        
        $display("[%0t] TEST 2: Motor Tetikleniyor (4x Modu, TX_EN=1, Start=1)...", $time);
        // slv_reg0: Mode=10 (4x), TX_EN=1, Start=1 -> Binary: 0000_1101 = 0xD
        axi_write(4'h0, 32'h0000000D); 
        
        axi_write(4'h0, 32'h0000000C); // Start indir
        
        #500;
        
        $display("\n====================================================");
        $display("[%0t] AXI Simulasyonu Tamamlandi.", $time);
        $display("====================================================");
        $finish;
    end
endmodule

// --- KUKLA FLASH MODELİ (Burada kalacak) ---
module smart_dummy_flash (
    input S,          
    input C_,         
    inout DQ0,        
    inout DQ1,        
    inout DQ2,        
    inout DQ3         
);
    reg [7:0] shift_reg;
    integer bit_count = 0;
    integer state = 0; 
    reg [3:0] dq_out;
    reg [3:0] dq_oe; 

    assign DQ0 = dq_oe[0] ? dq_out[0] : 1'bz;
    assign DQ1 = dq_oe[1] ? dq_out[1] : 1'bz;
    assign DQ2 = dq_oe[2] ? dq_out[2] : 1'bz;
    assign DQ3 = dq_oe[3] ? dq_out[3] : 1'bz;

    initial begin
        dq_oe = 4'b0000;
        dq_out = 4'b0000;
    end

    always @(posedge C_ or posedge S) begin
       if (S == 1) begin
        bit_count <= 0;
        state <= 0;
        dq_oe <= 4'b0000; // CS yüksekken (boştayken) hatları kesinlikle serbest bırak (Z)
        dq_out <= 4'b0000;
    end else begin
            if (state == 0) begin
                shift_reg <= {shift_reg[6:0], DQ0};
                bit_count <= bit_count + 1;
                
                if (bit_count == 7) begin
                    state <= 1;
                    bit_count <= 0;
                    
                    case ({shift_reg[6:0], DQ0})
                        8'h03: $display(">>> [%0t] [FLASH AJANI] 1x Modu Kesfedildi: Normal Read (0x03) <<<", $time);
                        8'h3B: $display(">>> [%0t] [FLASH AJANI] 2x Modu Kesfedildi: Dual Output Read (0x3B) <<<", $time);
                        8'h6B: $display(">>> [%0t] [FLASH AJANI] 4x Modu Kesfedildi: Quad Output Read (0x6B) <<<", $time);
                        8'hEB: $display(">>> [%0t] [FLASH AJANI] 4x Modu Kesfedildi: Quad I/O Read (0xEB) <<<", $time);
                        default: $display(">>> [%0t] [FLASH AJANI] Diger Komut: %h <<<", $time, {shift_reg[6:0], DQ0});
                    endcase
                end
            end else if (state == 1) begin
                if (shift_reg == 8'h6B || shift_reg == 8'hEB) begin
                    dq_oe <= 4'b1111;
                    dq_out <= dq_out + 1; 
                end else if (shift_reg == 8'h3B) begin
                    dq_oe <= 4'b0011;
                    dq_out[1:0] <= dq_out[1:0] + 1;
                end else begin
                    dq_oe <= 4'b0010; 
                    dq_out[1] <= ~dq_out[1];
                end
            end
        end
    end
endmodule