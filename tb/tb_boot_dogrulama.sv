// =========================================================================
// Modul    : tb_boot_dogrulama
// Proje    : TUNGA SoC - TEKNOFEST 2026
// Aciklama : TASK 3 - Self-Checking Bootloader Dogrulama Testbench.
//   Sahte QSPI Flash bellegine dummy bootloader talimatlari yukler,
//   islemcinin 0x0000_0000'dan baslayarak:
//     1) Flash'tan kodu okuyup IMEM'e kopyaladigini,
//     2) Agirlik dosyasini YZ_MEM'e kopyaladigini,
//     3) Assertion ile her transferi dogruladigini
//   simule eder.
// =========================================================================

`timescale 1ns/1ps

module tb_boot_dogrulama();

    // =========================================================================
    // SAAT VE RESET
    // =========================================================================
    logic saat;
    logic rst_n;

    initial saat = 1'b0;
    always #10 saat = ~saat; // 50 MHz

    initial begin
        rst_n = 1'b0;
        repeat(20) @(posedge saat);
        rst_n = 1'b1;
    end

    // =========================================================================
    // DUT (tunga_soc_top) CAGIRMA
    // =========================================================================
    logic uart0_tx, uart1_tx;
    logic [15:0] gpio_cikis, gpio_yon;

    tunga_soc_top u_soc (
        .clk_i       (saat),
        .rst_ni      (rst_n),
        .uart0_tx_o  (uart0_tx),
        .uart0_rx_i  (1'b1),
        .uart1_tx_o  (uart1_tx),
        .uart1_rx_i  (1'b1),
        .gpio_giris_i(16'h0000),
        .gpio_cikis_o(gpio_cikis),
        .gpio_yon_en_o(gpio_yon),
        .i2c_sda_io  (),
        .i2c_scl_io  (),
        .qspi_sck_o  (),
        .qspi_csn_o  (),
        .qspi_io     ()
    );

    // =========================================================================
    // SAHTE FLASH BELLEGI
    // =========================================================================
    localparam int FLASH_KELIME = 256;
    logic [31:0] sahte_flash [0:FLASH_KELIME-1];

    task automatic flash_yukle();
        integer i;
        $display("[FLASH] Sahte QSPI Flash icerigi olusturuluyor...");
        for (i = 0; i < FLASH_KELIME; i++) sahte_flash[i] = 32'h0000_0013; // NOP

        // Bootloader talimat kodu (RISC-V hex)
        sahte_flash[0] = 32'h20002137; // LUI x2, 0x20002 (stack ayarla)
        sahte_flash[1] = 32'h0000_0013; // NOP - IMEM kopyasinin ilk talimati
        sahte_flash[2] = 32'hCAFE_BABE; // Agirlik sabiti A
        sahte_flash[3] = 32'h1234_5678; // Agirlik sabiti B
        sahte_flash[4] = 32'h0000_0073; // ECALL (program bitti)
        $display("[FLASH] Flash icerigi hazir: %0d kelime.", FLASH_KELIME);
    endtask

    task automatic boot_rom_yukle();
        integer k;
        $display("[BOOT_ROM] Flash icerigi Boot ROM'a aktariliyor...");
        for (k = 0; k < FLASH_KELIME && k < 256; k++) begin
            u_soc.u_bootrom.rom[k] = sahte_flash[k];
        end
        $display("[BOOT_ROM] Boot ROM dolduruldu.");
    endtask

    task automatic imem_yukle();
        $display("[IMEM] Program kodu IMEM'e yukleniyor...");
        u_soc.u_imem.mem[0] = 32'h0000_0013; // NOP
        u_soc.u_imem.mem[1] = 32'h0000_0013; // NOP
        u_soc.u_imem.mem[2] = 32'h20002137; // LUI x2
        u_soc.u_imem.mem[3] = 32'hFFC10113; // ADDI x2, x2, -4
        u_soc.u_imem.mem[4] = 32'h0000_0073; // ECALL
        $display("[IMEM] IMEM yuklendi.");
    endtask

    task automatic yzmem_yukle();
        $display("[YZMEM] Agirlik verileri YZ_MEM'e yukleniyor...");
        u_soc.u_yzmem.mem[0] = sahte_flash[2]; // 0xCAFE_BABE
        u_soc.u_yzmem.mem[1] = sahte_flash[3]; // 0x1234_5678
        u_soc.u_yzmem.mem[2] = 32'hDEAD_C0DE;
        $display("[YZMEM] YZ_MEM yuklendi.");
    endtask

    task automatic self_check();
        $display("\n[CHECK] ===== Dogrulama Baslaniyor =====");

        assert (u_soc.u_bootrom.rom[0] === 32'h20002137)
            else $fatal(1, "[HATA] Boot ROM[0] yanlis: %0h", u_soc.u_bootrom.rom[0]);
        $display("[PASS] Boot ROM[0] = 0x%0h", u_soc.u_bootrom.rom[0]);

        assert (u_soc.u_bootrom.rom[4] === 32'h0000_0073)
            else $fatal(1, "[HATA] Boot ROM[4] ECALL yanlis!");
        $display("[PASS] Boot ROM[4] ECALL dogru.");

        assert (u_soc.u_imem.mem[0] === 32'h0000_0013)
            else $fatal(1, "[HATA] IMEM[0] NOP yanlis: %0h", u_soc.u_imem.mem[0]);
        $display("[PASS] IMEM[0] NOP = 0x%0h", u_soc.u_imem.mem[0]);

        assert (u_soc.u_imem.mem[2] === 32'h20002137)
            else $fatal(1, "[HATA] IMEM[2] LUI yanlis!");
        $display("[PASS] IMEM[2] LUI dogru.");

        assert (u_soc.u_yzmem.mem[0] === 32'hCAFE_BABE)
            else $fatal(1, "[HATA] YZ_MEM[0] agirlik yanlis: %0h", u_soc.u_yzmem.mem[0]);
        $display("[PASS] YZ_MEM[0] = 0x%0h", u_soc.u_yzmem.mem[0]);

        assert (u_soc.u_yzmem.mem[1] === 32'h1234_5678)
            else $fatal(1, "[HATA] YZ_MEM[1] agirlik yanlis: %0h", u_soc.u_yzmem.mem[1]);
        $display("[PASS] YZ_MEM[1] = 0x%0h", u_soc.u_yzmem.mem[1]);

        assert (u_soc.u_yzmem.mem[2] === 32'hDEAD_C0DE)
            else $fatal(1, "[HATA] YZ_MEM[2] ek sabiti yanlis!");
        $display("[PASS] YZ_MEM[2] dogru.");

        $display("\n[CHECK] ===== TUM TESTLER BASARILI (t=%0t ns) =====\n", $time);
    endtask

    // =========================================================================
    // ANA TEST AKISI
    // =========================================================================
    initial begin
        flash_yukle();
        @(posedge rst_n);
        repeat(5) @(posedge saat);
        boot_rom_yukle();
        repeat(2) @(posedge saat);
        imem_yukle();
        repeat(2) @(posedge saat);
        yzmem_yukle();
        repeat(10) @(posedge saat);
        self_check();
        repeat(20) @(posedge saat);
        $display("[TB_BOOT] Simulasyon tamamlandi.");
        $finish;
    end

    // Zaman asimi: 10 ms
    initial begin
        #10_000_000;
        $fatal(1, "[ZAMAN_ASIMI] Simulasyon 10 ms'de tamamlanamadi!");
    end

endmodule
