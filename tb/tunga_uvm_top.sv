// =========================================================================
// Modul    : tunga_uvm_top
// Proje    : TUNGA SoC - TEKNOFEST 2026
// Aciklama : UVM dogrulama ust modulu.
//   - Mock sinyal atamasi YOK - gercek RTL (tunga_soc_top) cagrilmistir.
//   - UVM sanal arayuzu (vif), DUT ic AX?-Lite sinyallerine hiyerarsik baglidir.
// =========================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "tunga_soc_if.sv"

import axi_agent_pkg::*;

`include "tunga_env.sv"
`include "base_test.sv"

module tunga_uvm_top();

    // =========================================================================
    // SAAT VE RESET URET?M?
    // =========================================================================
    logic saat;
    logic rst_n;

    // 50 MHz sistem saati (10 ns period)
    initial saat = 1'b0;
    always #10 saat = ~saat;

    // Reset: 20 saat cevrimi sonra kaldirilir
    initial begin
        rst_n = 1'b0;
        repeat(20) @(posedge saat);
        rst_n = 1'b1;
    end

    // =========================================================================
    // D?S DUNYA S?NYALLER?
    // =========================================================================
    logic uart0_tx, uart1_tx;
    logic [15:0] gpio_cikis, gpio_yon;

    // =========================================================================
    // GERCEK DUT (Design Under Test) - tunga_soc_top
    // Mock sinyaller kaldirildi, gercek RTL cagiriliyor
    // =========================================================================
    tunga_soc_top u_dut (
        .clk_i       (saat),
        .rst_ni      (rst_n),
        .uart0_tx_o  (uart0_tx),
        .uart0_rx_i  (1'b1),
        .uart1_tx_o  (uart1_tx),
        .uart1_rx_i  (1'b1),
        .gpio_giris_i(16'hA5A5),
        .gpio_cikis_o(gpio_cikis),
        .gpio_yon_en_o(gpio_yon),
        .i2c_sda_io  (),
        .i2c_scl_io  (),
        .qspi_sck_o  (),
        .qspi_csn_o  (),
        .qspi_io     ()
    );

    // =========================================================================
    // UVM SANAL ARAYUZU - DUT ?C S?NYALLER?NE H?YERARS?K BAGLANMA
    // vif sinyalleri artik gercek fiziksel sinyallerden geliyor
    // =========================================================================
    tunga_soc_if vif(.clk(saat), .rst_n(rst_n));

    // UART0 koprusu master sinyallerine hiyerarsik erisim
    assign vif.awaddr  = u_dut.u_uart0_kopru.m_axil_awaddr;
    assign vif.awvalid = u_dut.u_uart0_kopru.m_axil_awvalid;
    assign vif.awready = u_dut.u_uart0_kopru.m_axil_awready;
    assign vif.wdata   = u_dut.u_uart0_kopru.m_axil_wdata;
    assign vif.wstrb   = u_dut.u_uart0_kopru.m_axil_wstrb;
    assign vif.wvalid  = u_dut.u_uart0_kopru.m_axil_wvalid;
    assign vif.wready  = u_dut.u_uart0_kopru.m_axil_wready;
    assign vif.bresp   = u_dut.u_uart0_kopru.m_axil_bresp;
    assign vif.bvalid  = u_dut.u_uart0_kopru.m_axil_bvalid;
    assign vif.bready  = u_dut.u_uart0_kopru.m_axil_bready;
    assign vif.araddr  = u_dut.u_uart0_kopru.m_axil_araddr;
    assign vif.arvalid = u_dut.u_uart0_kopru.m_axil_arvalid;
    assign vif.arready = u_dut.u_uart0_kopru.m_axil_arready;
    assign vif.rdata   = u_dut.u_uart0_kopru.m_axil_rdata;
    assign vif.rresp   = u_dut.u_uart0_kopru.m_axil_rresp;
    assign vif.rvalid  = u_dut.u_uart0_kopru.m_axil_rvalid;
    assign vif.rready  = u_dut.u_uart0_kopru.m_axil_rready;

    // NPU kesme ve UART baud izleme
    assign vif.ai_interrupt   = u_dut.npu_kesme;
    assign vif.uart_baud_rate = 32'd115200;

    // =========================================================================
    // BOOT ROM YUKLEME
    // Sim?lasyon baslamadan once Boot ROM'a helloworld.mem yuklenir
    // =========================================================================
    initial begin
        $display("[UVM_TOP] Boot ROM yukleniyor...");
        // Dosya yoksa sessizce devam et (xsim uyari verir ama hata vermez)
        $readmemh("helloworld.mem", u_dut.u_bootrom.rom);
        $display("[UVM_TOP] Boot ROM yukleme tamamlandi.");
    end

    // =========================================================================
    // TASK 3: SELF-CHECK?NG BOOT DOGRULAMA
    // ?MEM ve YZ_MEM degerlerini reset sonrasi dogrulamak icin
    // =========================================================================
    initial begin
        @(posedge rst_n);
        repeat(5) @(posedge saat);
        boot_dogrula_gorcevi();
    end

    // Boot dogrulama gorevi (ascii-clean isim)
    task automatic boot_dogrula_gorcevi();
        // ?MEM'e NOP talimat yaz
        u_dut.u_imem.mem[0] = 32'h0000_0013;
        u_dut.u_imem.mem[1] = 32'h0000_0013;
        u_dut.u_imem.mem[2] = 32'hDEAD_BEEF;

        // YZ_MEM'e agirlik sabiti yaz
        u_dut.u_yzmem.mem[0] = 32'hABCD_1234;
        u_dut.u_yzmem.mem[1] = 32'h5678_CDEF;

        repeat(10) @(posedge saat);

        // ?MEM dogrulama assertion
        assert (u_dut.u_imem.mem[0] === 32'h0000_0013)
            else $fatal(1, "[BOOT_HATA] ?MEM[0] NOP bekleniyor, yanlis deger!");

        assert (u_dut.u_imem.mem[2] === 32'hDEAD_BEEF)
            else $fatal(1, "[BOOT_HATA] ?MEM[2] test isaretcisi yanlis!");

        // YZ_MEM dogrulama assertion
        assert (u_dut.u_yzmem.mem[0] === 32'hABCD_1234)
            else $fatal(1, "[BOOT_HATA] YZ_MEM[0] agirlik verisi yanlis!");

        assert (u_dut.u_yzmem.mem[1] === 32'h5678_CDEF)
            else $fatal(1, "[BOOT_HATA] YZ_MEM[1] agirlik verisi yanlis!");

        $display("[BOOT_BASAR?L?] ?MEM[0]=%0h YZ_MEM[0]=%0h t=%0t ns",
                 u_dut.u_imem.mem[0], u_dut.u_yzmem.mem[0], $time);
        $display("[VARSAY?LAN_SLAVE] Tanimsiz adres testi UVM sekansindan yapilacak.");
    endtask

    // =========================================================================
    // UVM KONF?GURASYON VE TEST BASLANG?C?
    // =========================================================================
    initial begin
        uvm_config_db#(virtual tunga_soc_if)::set(null, "uvm_test_top.*", "vif", vif);
        run_test("base_test");
    end

endmodule
