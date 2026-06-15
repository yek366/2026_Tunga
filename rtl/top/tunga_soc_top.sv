// =========================================================================
// Modul    : tunga_soc_top
// Proje    : TUNGA SoC - TEKNOFEST 2026 Cip Tasarim Yarismasi
// Yazar    : Ali Salih Yildirim
// Tarih    : 2026-06-15
//
// Aciklama : Tam entegre SoC ust modulu.
//   - CV32E40P islemeyi OBI protokol uzerinden veri yoluna baglar.
//   - OBI-to-AXI-Lite koprusu veri yolu isteklerini AXI-Lite'a cevirir.
//   - Kati adres cozucusu (Address Decoder) istekleri dogru slave'e yonlendirir.
//   - Tanimsiz adreslere "Varsayilan Slave" (Default Slave) yanit uretir.
//   - Tum cevrebirim kesmelerini irq_vektor altinda islemciye iletir.
//
// Bellek Haritasi (Sabit / Sartname EK-3):
//   0x0000_0000 - 0x0000_03FF  Boot ROM   (1 KB)
//   0x0000_1000 - 0x0000_2FFF  IMEM       (8 KB Komut SRAM)
//   0x0001_0000 - 0x0001_77FF  YZ_MEM     (30 KB NPU Bellegi)
//   0x2000_0000 - 0x2000_1FFF  DMEM       (8 KB Veri SRAM)
//   0x2000_3000                GPIO       (32 pin)
//   0x2000_4000                Timer      (32 bit)
//   0x2000_5000                UART1      (YZ Ses Akisi)
//   0x2000_6000                QSPI       (Master)
//   0x2000_7000                I2C        (Master)
//   0x2000_8000                NPU CSR    (Kontrol/Durum Yazmaclari)
//   0x4002_0000                UART0      (Hata Ayiklama / TEKNOTEST)
//   Diger       - Varsayilan Slave (0xDEAD_BEEF dondurur, kilitlenmeyi onler)
// =========================================================================

`timescale 1ns/1ps

module tunga_soc_top (
    input  logic        clk_i,
    input  logic        rst_ni,          // Aktif-dusuk reset

    // --- Dis Dunyaya Acilan Pinler ---
    // UART0: Hata Ayiklama ve TEKNOTEST kapisi
    output logic        uart0_tx_o,
    input  logic        uart0_rx_i,

    // UART1: YZ ses akisi
    output logic        uart1_tx_o,
    input  logic        uart1_rx_i,

    // GPIO Fiziksel Pinler (16 giris + 16 cikis)
    input  logic [15:0] gpio_giris_i,
    output logic [15:0] gpio_cikis_o,
    output logic [15:0] gpio_yon_en_o,   // Pin yon kontrolu

    // I2C Acik-kolektor hatlari
    inout  wire         i2c_sda_io,
    inout  wire         i2c_scl_io,

    // QSPI Flash baglantisi
    output logic        qspi_sck_o,
    output logic        qspi_csn_o,
    inout  wire  [3:0]  qspi_io
);

    // =========================================================================
    // ADRES HARITASI SABITLERI
    // =========================================================================
    localparam logic [31:0] BOOTROM_TABAN   = 32'h0000_0000;
    localparam logic [31:0] BOOTROM_SINIR   = 32'h0000_03FF;
    localparam logic [31:0] IMEM_TABAN      = 32'h0000_1000;
    localparam logic [31:0] IMEM_SINIR      = 32'h0000_2FFF;
    localparam logic [31:0] YZMEM_TABAN     = 32'h0001_0000;
    localparam logic [31:0] YZMEM_SINIR     = 32'h0001_77FF;
    localparam logic [31:0] DMEM_TABAN      = 32'h2000_0000;
    localparam logic [31:0] DMEM_SINIR      = 32'h2000_1FFF;
    localparam logic [31:0] GPIO_TABAN      = 32'h2000_3000;
    localparam logic [31:0] GPIO_SINIR      = 32'h2000_30FF;
    localparam logic [31:0] TIMER_TABAN     = 32'h2000_4000;
    localparam logic [31:0] TIMER_SINIR     = 32'h2000_40FF;
    localparam logic [31:0] UART1_TABAN     = 32'h2000_5000;
    localparam logic [31:0] UART1_SINIR     = 32'h2000_50FF;
    localparam logic [31:0] QSPI_TABAN      = 32'h2000_6000;
    localparam logic [31:0] QSPI_SINIR      = 32'h2000_60FF;
    localparam logic [31:0] I2C_TABAN       = 32'h2000_7000;
    localparam logic [31:0] I2C_SINIR       = 32'h2000_70FF;
    localparam logic [31:0] NPU_CSR_TABAN   = 32'h2000_8000;
    localparam logic [31:0] NPU_CSR_SINIR   = 32'h2000_80FF;
    localparam logic [31:0] UART0_TABAN     = 32'h4002_0000;
    localparam logic [31:0] UART0_SINIR     = 32'h4002_00FF;

    // =========================================================================
    // SLAVE SECIM SABITLERI
    // =========================================================================
    localparam logic [3:0] SEL_BOOTROM  = 4'd0;
    localparam logic [3:0] SEL_IMEM     = 4'd1;
    localparam logic [3:0] SEL_YZMEM    = 4'd2;
    localparam logic [3:0] SEL_DMEM     = 4'd3;
    localparam logic [3:0] SEL_GPIO     = 4'd4;
    localparam logic [3:0] SEL_TIMER    = 4'd5;
    localparam logic [3:0] SEL_UART1    = 4'd6;
    localparam logic [3:0] SEL_QSPI     = 4'd7;
    localparam logic [3:0] SEL_I2C      = 4'd8;
    localparam logic [3:0] SEL_NPU_CSR  = 4'd9;
    localparam logic [3:0] SEL_UART0    = 4'd10;
    localparam logic [3:0] SEL_VARSAYILAN = 4'd11; // Tanimsiz adres

    // =========================================================================
    // CV32E40P OBI ARAYUZLERI
    // =========================================================================
    // Komut (Instruction) OBI
    logic        komut_istek, komut_onay, komut_gecerli;
    logic [31:0] komut_adres, komut_veri;

    // Veri (Data) OBI
    logic        veri_istek, veri_onay, veri_gecerli, veri_yazma;
    logic [3:0]  veri_bayt_en;
    logic [31:0] veri_adres, veri_yazma_veri, veri_okuma_veri;

    // Kesme Vektoru (tum cevrebirim kesmelerini birlestirir)
    logic [31:0] irq_vektor;
    logic        gpio_kesme, timer_kesme, uart0_kesme, uart1_kesme, npu_kesme, i2c_kesme;

    // =========================================================================
    // CV32E40P ISLEMCI CEKIRDEGI
    // =========================================================================
    cv32e40p_top #(
        .COREV_PULP      (0),
        .COREV_CLUSTER   (0),
        .FPU             (0),
        .ZFINX           (0),
        .NUM_MHPMCOUNTERS(1)
    ) u_islemci (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),

        .pulp_clock_en_i(1'b1),
        .scan_cg_en_i   (1'b0),

        // Boot adresi: 0x0000_0000 (Boot ROM baslangici)
        .boot_addr_i        (32'h0000_0000),
        .mtvec_addr_i       (32'h0000_0100), // Kesme vektoru tablosu
        .dm_halt_addr_i     (32'h1A11_0800), // Debug modul dur adresi
        .hart_id_i          (32'h0000_0000),
        .dm_exception_addr_i(32'h1A11_1000),

        // Komut OBI
        .instr_req_o   (komut_istek),
        .instr_gnt_i   (komut_onay),
        .instr_rvalid_i(komut_gecerli),
        .instr_addr_o  (komut_adres),
        .instr_rdata_i (komut_veri),

        // Veri OBI
        .data_req_o   (veri_istek),
        .data_gnt_i   (veri_onay),
        .data_rvalid_i(veri_gecerli),
        .data_we_o    (veri_yazma),
        .data_be_o    (veri_bayt_en),
        .data_addr_o  (veri_adres),
        .data_wdata_o (veri_yazma_veri),
        .data_rdata_i (veri_okuma_veri),

        // Kesme portlari: tum kesmeler tek vektorde birlestiriliyor
        .irq_i     (irq_vektor),
        .irq_ack_o (),
        .irq_id_o  (),

        // Debug: su an bagli degil (opsiyonel JTAG modulu gerekirse eklenebilir)
        .debug_req_i      (1'b0),
        .debug_havereset_o(),
        .debug_running_o  (),
        .debug_halted_o   (),

        .fetch_enable_i(1'b1),
        .core_sleep_o  ()
    );

    // =========================================================================
    // KESME VEKTORU MONTAJI
    // CV32E40P icsel RISC-V kesme numaralari:
    //   Bit 16: harici kesme 0 -> GPIO
    //   Bit 17: harici kesme 1 -> Timer
    //   Bit 18: harici kesme 2 -> UART0
    //   Bit 19: harici kesme 3 -> UART1 (YZ Ses Akisi)
    //   Bit 20: harici kesme 4 -> NPU
    //   Bit 21: harici kesme 5 -> I2C
    // =========================================================================
    assign irq_vektor = {
        10'b0,                              // [31:22] kullanilmiyor
        i2c_kesme,                          // [21]
        npu_kesme,                          // [20]
        uart1_kesme,                        // [19]
        uart0_kesme,                        // [18]
        timer_kesme,                        // [17]
        gpio_kesme,                         // [16]
        16'b0                               // [15:0]  yazilim kesmesi / timer litesi
    };

    // =========================================================================
    // KOMUT TARAFI: BOOT ROM (OBI - dogrudan, koprusuz)
    // Islemci komut getirir (fetch) -> Boot ROM'dan
    // =========================================================================
    obi_bootrom #(.WORDS(256)) u_bootrom ( // 256 x 32-bit = 1 KB
        .clk   (clk_i),
        .rst_n (rst_ni),
        // Port A: komut getirme
        .a_req   (komut_istek),
        .a_gnt   (komut_onay),
        .a_addr  (komut_adres),
        .a_rdata (komut_veri),
        .a_rvalid(komut_gecerli),
        // Port B: veri tarafi bellek okuma (DMEM yokken bos birak)
        .b_req   (1'b0),
        .b_gnt   (),
        .b_addr  (32'h0),
        .b_we    (1'b0),
        .b_rdata (),
        .b_rvalid()
    );

    // =========================================================================
    // VERI TARAFI ADRES COZUCU (Address Decoder)
    // veri_adres'e gore hangi slave'e gittigini belirler
    // =========================================================================
    logic [3:0] slave_secim;
    always_comb begin
        if      (veri_adres >= IMEM_TABAN    && veri_adres <= IMEM_SINIR)    slave_secim = SEL_IMEM;
        else if (veri_adres >= YZMEM_TABAN   && veri_adres <= YZMEM_SINIR)   slave_secim = SEL_YZMEM;
        else if (veri_adres >= DMEM_TABAN    && veri_adres <= DMEM_SINIR)    slave_secim = SEL_DMEM;
        else if (veri_adres >= GPIO_TABAN    && veri_adres <= GPIO_SINIR)    slave_secim = SEL_GPIO;
        else if (veri_adres >= TIMER_TABAN   && veri_adres <= TIMER_SINIR)   slave_secim = SEL_TIMER;
        else if (veri_adres >= UART1_TABAN   && veri_adres <= UART1_SINIR)   slave_secim = SEL_UART1;
        else if (veri_adres >= QSPI_TABAN    && veri_adres <= QSPI_SINIR)    slave_secim = SEL_QSPI;
        else if (veri_adres >= I2C_TABAN     && veri_adres <= I2C_SINIR)     slave_secim = SEL_I2C;
        else if (veri_adres >= NPU_CSR_TABAN && veri_adres <= NPU_CSR_SINIR) slave_secim = SEL_NPU_CSR;
        else if (veri_adres >= UART0_TABAN   && veri_adres <= UART0_SINIR)   slave_secim = SEL_UART0;
        else                                                                   slave_secim = SEL_VARSAYILAN;
    end

    // =========================================================================
    // OBI VERI YOLU: ONAY (GNT) MANTIGI
    // Her slave'in kendi onay sinyali var; adres cozucuya gore secilir
    // =========================================================================
    logic imem_onay,  yzmem_onay,  dmem_onay;

    // AXI-Lite kopruler her zaman 1 saat gecikmeyle onay verir
    // (kopru hazir oldugunda obi_gnt=1 doner)
    logic gpio_axil_onay, timer_axil_onay, uart0_axil_onay, uart1_axil_onay;
    logic qspi_axil_onay, i2c_axil_onay, npu_axil_onay;

    always_comb begin
        unique case (slave_secim)
            SEL_IMEM:      veri_onay = imem_onay;
            SEL_YZMEM:     veri_onay = yzmem_onay;
            SEL_DMEM:      veri_onay = dmem_onay;
            SEL_GPIO:      veri_onay = gpio_axil_onay;
            SEL_TIMER:     veri_onay = timer_axil_onay;
            SEL_UART0:     veri_onay = uart0_axil_onay;
            SEL_UART1:     veri_onay = uart1_axil_onay;
            SEL_QSPI:      veri_onay = qspi_axil_onay;
            SEL_I2C:       veri_onay = i2c_axil_onay;
            SEL_NPU_CSR:   veri_onay = npu_axil_onay;
            SEL_VARSAYILAN: veri_onay = 1'b1; // Varsayilan slave aninda onay verir
            default:       veri_onay = 1'b0;
        endcase
    end

    // =========================================================================
    // OBI VERI YOLU: OKUMA VERISI VE GECERLILIK (RDATA / RVALID) MANTIGI
    // =========================================================================
    logic imem_gecerli,  yzmem_gecerli,  dmem_gecerli;
    logic [31:0] imem_okuma, yzmem_okuma, dmem_okuma;

    logic gpio_axil_gecerli,  timer_axil_gecerli, uart0_axil_gecerli, uart1_axil_gecerli;
    logic qspi_axil_gecerli,  i2c_axil_gecerli,  npu_axil_gecerli;
    logic [31:0] gpio_axil_okuma, timer_axil_okuma, uart0_axil_okuma, uart1_axil_okuma;
    logic [31:0] qspi_axil_okuma, i2c_axil_okuma,  npu_axil_okuma;

    // Varsayilan slave: 1 saat sonra gecerli sinyal uretir (kilitlenmeyi onler)
    logic varsayilan_bekleyen_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) varsayilan_bekleyen_q <= 1'b0;
        else         varsayilan_bekleyen_q <= (veri_istek && veri_onay && slave_secim == SEL_VARSAYILAN);
    end

    // Slave secimini 1 saat gecikmeli tut (rvalid fazinda kullanmak icin)
    logic [3:0] slave_secim_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) slave_secim_q <= SEL_VARSAYILAN;
        else if (veri_istek && veri_onay) slave_secim_q <= slave_secim;
    end

    always_comb begin
        veri_okuma_veri = 32'h0;
        veri_gecerli    = 1'b0;
        unique case (slave_secim_q)
            SEL_IMEM:      begin veri_okuma_veri = imem_okuma;        veri_gecerli = imem_gecerli;        end
            SEL_YZMEM:     begin veri_okuma_veri = yzmem_okuma;       veri_gecerli = yzmem_gecerli;       end
            SEL_DMEM:      begin veri_okuma_veri = dmem_okuma;        veri_gecerli = dmem_gecerli;        end
            SEL_GPIO:      begin veri_okuma_veri = gpio_axil_okuma;   veri_gecerli = gpio_axil_gecerli;   end
            SEL_TIMER:     begin veri_okuma_veri = timer_axil_okuma;  veri_gecerli = timer_axil_gecerli;  end
            SEL_UART0:     begin veri_okuma_veri = uart0_axil_okuma;  veri_gecerli = uart0_axil_gecerli;  end
            SEL_UART1:     begin veri_okuma_veri = uart1_axil_okuma;  veri_gecerli = uart1_axil_gecerli;  end
            SEL_QSPI:      begin veri_okuma_veri = qspi_axil_okuma;   veri_gecerli = qspi_axil_gecerli;   end
            SEL_I2C:       begin veri_okuma_veri = i2c_axil_okuma;    veri_gecerli = i2c_axil_gecerli;    end
            SEL_NPU_CSR:   begin veri_okuma_veri = npu_axil_okuma;    veri_gecerli = npu_axil_gecerli;    end
            SEL_VARSAYILAN: begin
                // Tanimsiz adres: 0xDEADBEEF dondur, bir sonraki saat gecerli
                veri_okuma_veri = 32'hDEAD_BEEF;
                veri_gecerli    = varsayilan_bekleyen_q;
            end
            default: begin veri_okuma_veri = 32'h0; veri_gecerli = 1'b0; end
        endcase
    end

    // =========================================================================
    // OBI ISTEK YONLENDIRME (sadece dogru slave'e istek gonder)
    // =========================================================================
    wire imem_istek   = veri_istek && (slave_secim == SEL_IMEM);
    wire yzmem_istek  = veri_istek && (slave_secim == SEL_YZMEM);
    wire dmem_istek   = veri_istek && (slave_secim == SEL_DMEM);
    wire gpio_istek   = veri_istek && (slave_secim == SEL_GPIO);
    wire timer_istek  = veri_istek && (slave_secim == SEL_TIMER);
    wire uart0_istek  = veri_istek && (slave_secim == SEL_UART0);
    wire uart1_istek  = veri_istek && (slave_secim == SEL_UART1);
    wire qspi_istek   = veri_istek && (slave_secim == SEL_QSPI);
    wire i2c_istek    = veri_istek && (slave_secim == SEL_I2C);
    wire npu_istek    = veri_istek && (slave_secim == SEL_NPU_CSR);

    // =========================================================================
    // IMEM: 8 KB Komut SRAM (OBI dogrudan)
    // =========================================================================
    obi_sram #(.WORDS(2048)) u_imem (
        .clk       (clk_i),
        .rst_n     (rst_ni),
        .obi_req   (imem_istek),
        .obi_gnt   (imem_onay),
        .obi_addr  (veri_adres),
        .obi_we    (veri_yazma),
        .obi_be    (veri_bayt_en),
        .obi_wdata (veri_yazma_veri),
        .obi_rdata (imem_okuma),
        .obi_rvalid(imem_gecerli)
    );

    // =========================================================================
    // YZ_MEM: 30 KB NPU SRAM (OBI dogrudan)
    // =========================================================================
    obi_sram #(.WORDS(7680)) u_yzmem ( // 7680 x 32-bit = 30 KB
        .clk       (clk_i),
        .rst_n     (rst_ni),
        .obi_req   (yzmem_istek),
        .obi_gnt   (yzmem_onay),
        .obi_addr  (veri_adres),
        .obi_we    (veri_yazma),
        .obi_be    (veri_bayt_en),
        .obi_wdata (veri_yazma_veri),
        .obi_rdata (yzmem_okuma),
        .obi_rvalid(yzmem_gecerli)
    );

    // =========================================================================
    // DMEM: 8 KB Veri SRAM (OBI dogrudan)
    // =========================================================================
    obi_sram #(.WORDS(2048)) u_dmem (
        .clk       (clk_i),
        .rst_n     (rst_ni),
        .obi_req   (dmem_istek),
        .obi_gnt   (dmem_onay),
        .obi_addr  (veri_adres),
        .obi_we    (veri_yazma),
        .obi_be    (veri_bayt_en),
        .obi_wdata (veri_yazma_veri),
        .obi_rdata (dmem_okuma),
        .obi_rvalid(dmem_gecerli)
    );

    // =========================================================================
    // OBI-to-AXI-Lite KOPRU MAKROSU
    // Her cevre birimi icin tekrarlanan kopru + slave baglantisi asagida gelir.
    // Kopru: obi2axil instantiations
    // =========================================================================

    // --- GPIO Koprusu ---
    logic [7:0] gpio_axil_awaddr, gpio_axil_araddr;
    logic        gpio_axil_awvalid, gpio_axil_awready;
    logic [31:0] gpio_axil_wdata;  logic [3:0] gpio_axil_wstrb;
    logic        gpio_axil_wvalid, gpio_axil_wready;
    logic [1:0]  gpio_axil_bresp;  logic gpio_axil_bvalid, gpio_axil_bready;
    logic        gpio_axil_arvalid, gpio_axil_arready;
    logic [31:0] gpio_axil_rdata_wire; logic [1:0] gpio_axil_rresp;
    logic        gpio_axil_rvalid_wire, gpio_axil_rready;

    obi2axil #(.AXIL_ADDR_W(8)) u_gpio_kopru (
        .clk(clk_i), .rst_n(rst_ni),
        .obi_req(gpio_istek), .obi_gnt(gpio_axil_onay),
        .obi_addr(veri_adres), .obi_we(veri_yazma), .obi_be(veri_bayt_en),
        .obi_wdata(veri_yazma_veri), .obi_rdata(gpio_axil_okuma), .obi_rvalid(gpio_axil_gecerli),
        .m_axil_awaddr(gpio_axil_awaddr), .m_axil_awvalid(gpio_axil_awvalid), .m_axil_awready(gpio_axil_awready),
        .m_axil_wdata(gpio_axil_wdata), .m_axil_wstrb(gpio_axil_wstrb),
        .m_axil_wvalid(gpio_axil_wvalid), .m_axil_wready(gpio_axil_wready),
        .m_axil_bresp(gpio_axil_bresp), .m_axil_bvalid(gpio_axil_bvalid), .m_axil_bready(gpio_axil_bready),
        .m_axil_araddr(gpio_axil_araddr), .m_axil_arvalid(gpio_axil_arvalid), .m_axil_arready(gpio_axil_arready),
        .m_axil_rdata(gpio_axil_rdata_wire), .m_axil_rresp(gpio_axil_rresp),
        .m_axil_rvalid(gpio_axil_rvalid_wire), .m_axil_rready(gpio_axil_rready)
    );

    gpio_peripheral #(.AXI_ADDR_W(8), .AXI_DATA_W(32)) u_gpio (
        .clk(clk_i), .rst_n(rst_ni),
        .gpio_i(gpio_giris_i), .gpio_o(gpio_cikis_o),
        .gpio_tx_en_o(gpio_yon_en_o), .global_interrupt_o(gpio_kesme),
        .s_axil_awaddr(gpio_axil_awaddr), .s_axil_awvalid(gpio_axil_awvalid), .s_axil_awready(gpio_axil_awready),
        .s_axil_wdata(gpio_axil_wdata), .s_axil_wstrb(gpio_axil_wstrb),
        .s_axil_wvalid(gpio_axil_wvalid), .s_axil_wready(gpio_axil_wready),
        .s_axil_bresp(gpio_axil_bresp), .s_axil_bvalid(gpio_axil_bvalid), .s_axil_bready(gpio_axil_bready),
        .s_axil_araddr(gpio_axil_araddr), .s_axil_arvalid(gpio_axil_arvalid), .s_axil_arready(gpio_axil_arready),
        .s_axil_rdata(gpio_axil_rdata_wire), .s_axil_rresp(gpio_axil_rresp),
        .s_axil_rvalid(gpio_axil_rvalid_wire), .s_axil_rready(gpio_axil_rready)
    );

    // --- Timer Koprusu ---
    logic [11:0] timer_axil_awaddr, timer_axil_araddr;
    logic        timer_axil_awvalid, timer_axil_awready;
    logic [31:0] timer_axil_wdata;  logic [3:0] timer_axil_wstrb;
    logic        timer_axil_wvalid, timer_axil_wready;
    logic [1:0]  timer_axil_bresp;  logic timer_axil_bvalid, timer_axil_bready;
    logic        timer_axil_arvalid, timer_axil_arready;
    logic [31:0] timer_axil_rdata_wire; logic [1:0] timer_axil_rresp;
    logic        timer_axil_rvalid_wire, timer_axil_rready;

    obi2axil #(.AXIL_ADDR_W(12)) u_timer_kopru (
        .clk(clk_i), .rst_n(rst_ni),
        .obi_req(timer_istek), .obi_gnt(timer_axil_onay),
        .obi_addr(veri_adres), .obi_we(veri_yazma), .obi_be(veri_bayt_en),
        .obi_wdata(veri_yazma_veri), .obi_rdata(timer_axil_okuma), .obi_rvalid(timer_axil_gecerli),
        .m_axil_awaddr(timer_axil_awaddr), .m_axil_awvalid(timer_axil_awvalid), .m_axil_awready(timer_axil_awready),
        .m_axil_wdata(timer_axil_wdata), .m_axil_wstrb(timer_axil_wstrb),
        .m_axil_wvalid(timer_axil_wvalid), .m_axil_wready(timer_axil_wready),
        .m_axil_bresp(timer_axil_bresp), .m_axil_bvalid(timer_axil_bvalid), .m_axil_bready(timer_axil_bready),
        .m_axil_araddr(timer_axil_araddr), .m_axil_arvalid(timer_axil_arvalid), .m_axil_arready(timer_axil_arready),
        .m_axil_rdata(timer_axil_rdata_wire), .m_axil_rresp(timer_axil_rresp),
        .m_axil_rvalid(timer_axil_rvalid_wire), .m_axil_rready(timer_axil_rready)
    );

    timer_peripheral #(.S_AXI_ADDR_WIDTH(12), .S_AXI_DATA_WIDTH(32)) u_timer (
        .s_axi_aclk(clk_i), .s_axi_aresetn(rst_ni),
        .s_axi_awaddr(timer_axil_awaddr), .s_axi_awprot(3'b0),
        .s_axi_awvalid(timer_axil_awvalid), .s_axi_awready(timer_axil_awready),
        .s_axi_wdata(timer_axil_wdata), .s_axi_wstrb(timer_axil_wstrb),
        .s_axi_wvalid(timer_axil_wvalid), .s_axi_wready(timer_axil_wready),
        .s_axi_bresp(timer_axil_bresp), .s_axi_bvalid(timer_axil_bvalid), .s_axi_bready(timer_axil_bready),
        .s_axi_araddr(timer_axil_araddr), .s_axi_arprot(3'b0),
        .s_axi_arvalid(timer_axil_arvalid), .s_axi_arready(timer_axil_arready),
        .s_axi_rdata(timer_axil_rdata_wire), .s_axi_rresp(timer_axil_rresp),
        .s_axi_rvalid(timer_axil_rvalid_wire), .s_axi_rready(timer_axil_rready),
        .timer_irq(timer_kesme)
    );

    // --- UART0 Koprusu (Hata Ayiklama / TEKNOTEST) ---
    logic [7:0] uart0_axil_awaddr, uart0_axil_araddr;
    logic        uart0_axil_awvalid, uart0_axil_awready;
    logic [31:0] uart0_axil_wdata;  logic [3:0] uart0_axil_wstrb;
    logic        uart0_axil_wvalid, uart0_axil_wready;
    logic [1:0]  uart0_axil_bresp;  logic uart0_axil_bvalid, uart0_axil_bready;
    logic        uart0_axil_arvalid, uart0_axil_arready;
    logic [31:0] uart0_axil_rdata_wire; logic [1:0] uart0_axil_rresp;
    logic        uart0_axil_rvalid_wire, uart0_axil_rready;

    obi2axil #(.AXIL_ADDR_W(8)) u_uart0_kopru (
        .clk(clk_i), .rst_n(rst_ni),
        .obi_req(uart0_istek), .obi_gnt(uart0_axil_onay),
        .obi_addr(veri_adres), .obi_we(veri_yazma), .obi_be(veri_bayt_en),
        .obi_wdata(veri_yazma_veri), .obi_rdata(uart0_axil_okuma), .obi_rvalid(uart0_axil_gecerli),
        .m_axil_awaddr(uart0_axil_awaddr), .m_axil_awvalid(uart0_axil_awvalid), .m_axil_awready(uart0_axil_awready),
        .m_axil_wdata(uart0_axil_wdata), .m_axil_wstrb(uart0_axil_wstrb),
        .m_axil_wvalid(uart0_axil_wvalid), .m_axil_wready(uart0_axil_wready),
        .m_axil_bresp(uart0_axil_bresp), .m_axil_bvalid(uart0_axil_bvalid), .m_axil_bready(uart0_axil_bready),
        .m_axil_araddr(uart0_axil_araddr), .m_axil_arvalid(uart0_axil_arvalid), .m_axil_arready(uart0_axil_arready),
        .m_axil_rdata(uart0_axil_rdata_wire), .m_axil_rresp(uart0_axil_rresp),
        .m_axil_rvalid(uart0_axil_rvalid_wire), .m_axil_rready(uart0_axil_rready)
    );

    uart_peripheral #(.SYS_CLK_HZ(50_000_000), .DEFAULT_BAUD(115_200),
                      .AXI_ADDR_W(8), .AXI_DATA_W(32)) u_uart0 (
        .clk(clk_i), .rst_n(rst_ni),
        .s_axil_awaddr(uart0_axil_awaddr), .s_axil_awvalid(uart0_axil_awvalid), .s_axil_awready(uart0_axil_awready),
        .s_axil_wdata(uart0_axil_wdata), .s_axil_wstrb(uart0_axil_wstrb),
        .s_axil_wvalid(uart0_axil_wvalid), .s_axil_wready(uart0_axil_wready),
        .s_axil_bresp(uart0_axil_bresp), .s_axil_bvalid(uart0_axil_bvalid), .s_axil_bready(uart0_axil_bready),
        .s_axil_araddr(uart0_axil_araddr), .s_axil_arvalid(uart0_axil_arvalid), .s_axil_arready(uart0_axil_arready),
        .s_axil_rdata(uart0_axil_rdata_wire), .s_axil_rresp(uart0_axil_rresp),
        .s_axil_rvalid(uart0_axil_rvalid_wire), .s_axil_rready(uart0_axil_rready),
        .uart_rxd(uart0_rx_i), .uart_txd(uart0_tx_o), .uart_irq(uart0_kesme)
    );

    // --- UART1 Koprusu (YZ Ses Akisi) ---
    logic [7:0] uart1_axil_awaddr, uart1_axil_araddr;
    logic        uart1_axil_awvalid, uart1_axil_awready;
    logic [31:0] uart1_axil_wdata;  logic [3:0] uart1_axil_wstrb;
    logic        uart1_axil_wvalid, uart1_axil_wready;
    logic [1:0]  uart1_axil_bresp;  logic uart1_axil_bvalid, uart1_axil_bready;
    logic        uart1_axil_arvalid, uart1_axil_arready;
    logic [31:0] uart1_axil_rdata_wire; logic [1:0] uart1_axil_rresp;
    logic        uart1_axil_rvalid_wire, uart1_axil_rready;

    obi2axil #(.AXIL_ADDR_W(8)) u_uart1_kopru (
        .clk(clk_i), .rst_n(rst_ni),
        .obi_req(uart1_istek), .obi_gnt(uart1_axil_onay),
        .obi_addr(veri_adres), .obi_we(veri_yazma), .obi_be(veri_bayt_en),
        .obi_wdata(veri_yazma_veri), .obi_rdata(uart1_axil_okuma), .obi_rvalid(uart1_axil_gecerli),
        .m_axil_awaddr(uart1_axil_awaddr), .m_axil_awvalid(uart1_axil_awvalid), .m_axil_awready(uart1_axil_awready),
        .m_axil_wdata(uart1_axil_wdata), .m_axil_wstrb(uart1_axil_wstrb),
        .m_axil_wvalid(uart1_axil_wvalid), .m_axil_wready(uart1_axil_wready),
        .m_axil_bresp(uart1_axil_bresp), .m_axil_bvalid(uart1_axil_bvalid), .m_axil_bready(uart1_axil_bready),
        .m_axil_araddr(uart1_axil_araddr), .m_axil_arvalid(uart1_axil_arvalid), .m_axil_arready(uart1_axil_arready),
        .m_axil_rdata(uart1_axil_rdata_wire), .m_axil_rresp(uart1_axil_rresp),
        .m_axil_rvalid(uart1_axil_rvalid_wire), .m_axil_rready(uart1_axil_rready)
    );

    uart_stream_peripheral #(.SYS_CLK_HZ(50_000_000), .DEFAULT_BAUD(115_200),
                              .AXI_ADDR_W(8), .AXI_DATA_W(32)) u_uart1 (
        .clk(clk_i), .rst_n(rst_ni),
        .s_axil_awaddr(uart1_axil_awaddr), .s_axil_awvalid(uart1_axil_awvalid), .s_axil_awready(uart1_axil_awready),
        .s_axil_wdata(uart1_axil_wdata), .s_axil_wstrb(uart1_axil_wstrb),
        .s_axil_wvalid(uart1_axil_wvalid), .s_axil_wready(uart1_axil_wready),
        .s_axil_bresp(uart1_axil_bresp), .s_axil_bvalid(uart1_axil_bvalid), .s_axil_bready(uart1_axil_bready),
        .s_axil_araddr(uart1_axil_araddr), .s_axil_arvalid(uart1_axil_arvalid), .s_axil_arready(uart1_axil_arready),
        .s_axil_rdata(uart1_axil_rdata_wire), .s_axil_rresp(uart1_axil_rresp),
        .s_axil_rvalid(uart1_axil_rvalid_wire), .s_axil_rready(uart1_axil_rready),
        .uart_rxd(uart1_rx_i), .uart_txd(uart1_tx_o),
        .uart_stream_irq(uart1_kesme), .fifo_empty(), .fifo_full()
    );

    // --- I2C Koprusu ---
    logic [7:0] i2c_axil_awaddr, i2c_axil_araddr;
    logic        i2c_axil_awvalid, i2c_axil_awready;
    logic [31:0] i2c_axil_wdata;  logic [3:0] i2c_axil_wstrb;
    logic        i2c_axil_wvalid, i2c_axil_wready;
    logic [1:0]  i2c_axil_bresp;  logic i2c_axil_bvalid, i2c_axil_bready;
    logic        i2c_axil_arvalid, i2c_axil_arready;
    logic [31:0] i2c_axil_rdata_wire; logic [1:0] i2c_axil_rresp;
    logic        i2c_axil_rvalid_wire, i2c_axil_rready;

    obi2axil #(.AXIL_ADDR_W(8)) u_i2c_kopru (
        .clk(clk_i), .rst_n(rst_ni),
        .obi_req(i2c_istek), .obi_gnt(i2c_axil_onay),
        .obi_addr(veri_adres), .obi_we(veri_yazma), .obi_be(veri_bayt_en),
        .obi_wdata(veri_yazma_veri), .obi_rdata(i2c_axil_okuma), .obi_rvalid(i2c_axil_gecerli),
        .m_axil_awaddr(i2c_axil_awaddr), .m_axil_awvalid(i2c_axil_awvalid), .m_axil_awready(i2c_axil_awready),
        .m_axil_wdata(i2c_axil_wdata), .m_axil_wstrb(i2c_axil_wstrb),
        .m_axil_wvalid(i2c_axil_wvalid), .m_axil_wready(i2c_axil_wready),
        .m_axil_bresp(i2c_axil_bresp), .m_axil_bvalid(i2c_axil_bvalid), .m_axil_bready(i2c_axil_bready),
        .m_axil_araddr(i2c_axil_araddr), .m_axil_arvalid(i2c_axil_arvalid), .m_axil_arready(i2c_axil_arready),
        .m_axil_rdata(i2c_axil_rdata_wire), .m_axil_rresp(i2c_axil_rresp),
        .m_axil_rvalid(i2c_axil_rvalid_wire), .m_axil_rready(i2c_axil_rready)
    );

    i2c_peripheral #(.SYS_CLK_FREQ(50_000_000), .I2C_FREQ(400_000)) u_i2c (
        .clk(clk_i), .rst_n(rst_ni),
        .s_axi_awaddr(i2c_axil_awaddr), .s_axi_awprot(3'b0),
        .s_axi_awvalid(i2c_axil_awvalid), .s_axi_awready(i2c_axil_awready),
        .s_axi_wdata(i2c_axil_wdata), .s_axi_wstrb(i2c_axil_wstrb),
        .s_axi_wvalid(i2c_axil_wvalid), .s_axi_wready(i2c_axil_wready),
        .s_axi_bresp(i2c_axil_bresp), .s_axi_bvalid(i2c_axil_bvalid), .s_axi_bready(i2c_axil_bready),
        .s_axi_araddr(i2c_axil_araddr), .s_axi_arprot(3'b0),
        .s_axi_arvalid(i2c_axil_arvalid), .s_axi_arready(i2c_axil_arready),
        .s_axi_rdata(i2c_axil_rdata_wire), .s_axi_rresp(i2c_axil_rresp),
        .s_axi_rvalid(i2c_axil_rvalid_wire), .s_axi_rready(i2c_axil_rready),
        .i2c_irq(i2c_kesme),
        .sda(i2c_sda_io), .scl(i2c_scl_io)
    );

    // --- QSPI Koprusu (Master) ---
    // QSPI modulu farkli arayuze sahip; sinyal isimleri uyarlanmistir
    logic [7:0] qspi_axil_awaddr, qspi_axil_araddr;
    logic        qspi_axil_awvalid, qspi_axil_awready;
    logic [31:0] qspi_axil_wdata;  logic [3:0] qspi_axil_wstrb;
    logic        qspi_axil_wvalid, qspi_axil_wready;
    logic [1:0]  qspi_axil_bresp;  logic qspi_axil_bvalid, qspi_axil_bready;
    logic        qspi_axil_arvalid, qspi_axil_arready;
    logic [31:0] qspi_axil_rdata_wire; logic [1:0] qspi_axil_rresp;
    logic        qspi_axil_rvalid_wire, qspi_axil_rready;

    obi2axil #(.AXIL_ADDR_W(8)) u_qspi_kopru (
        .clk(clk_i), .rst_n(rst_ni),
        .obi_req(qspi_istek), .obi_gnt(qspi_axil_onay),
        .obi_addr(veri_adres), .obi_we(veri_yazma), .obi_be(veri_bayt_en),
        .obi_wdata(veri_yazma_veri), .obi_rdata(qspi_axil_okuma), .obi_rvalid(qspi_axil_gecerli),
        .m_axil_awaddr(qspi_axil_awaddr), .m_axil_awvalid(qspi_axil_awvalid), .m_axil_awready(qspi_axil_awready),
        .m_axil_wdata(qspi_axil_wdata), .m_axil_wstrb(qspi_axil_wstrb),
        .m_axil_wvalid(qspi_axil_wvalid), .m_axil_wready(qspi_axil_wready),
        .m_axil_bresp(qspi_axil_bresp), .m_axil_bvalid(qspi_axil_bvalid), .m_axil_bready(qspi_axil_bready),
        .m_axil_araddr(qspi_axil_araddr), .m_axil_arvalid(qspi_axil_arvalid), .m_axil_arready(qspi_axil_arready),
        .m_axil_rdata(qspi_axil_rdata_wire), .m_axil_rresp(qspi_axil_rresp),
        .m_axil_rvalid(qspi_axil_rvalid_wire), .m_axil_rready(qspi_axil_rready)
    );

    // QSPI AXI-Lite slave baglantisi (Xilinx IP portlarini kullanir)
    axi_qspi_T_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(32), .C_S_AXI_ADDR_WIDTH(8)
    ) u_qspi (
        .S_AXI_ACLK(clk_i), .S_AXI_ARESETN(rst_ni),
        .S_AXI_AWADDR(qspi_axil_awaddr), .S_AXI_AWPROT(3'b0),
        .S_AXI_AWVALID(qspi_axil_awvalid), .S_AXI_AWREADY(qspi_axil_awready),
        .S_AXI_WDATA(qspi_axil_wdata), .S_AXI_WSTRB(qspi_axil_wstrb),
        .S_AXI_WVALID(qspi_axil_wvalid), .S_AXI_WREADY(qspi_axil_wready),
        .S_AXI_BRESP(qspi_axil_bresp), .S_AXI_BVALID(qspi_axil_bvalid), .S_AXI_BREADY(qspi_axil_bready),
        .S_AXI_ARADDR(qspi_axil_araddr), .S_AXI_ARPROT(3'b0),
        .S_AXI_ARVALID(qspi_axil_arvalid), .S_AXI_ARREADY(qspi_axil_arready),
        .S_AXI_RDATA(qspi_axil_rdata_wire), .S_AXI_RRESP(qspi_axil_rresp),
        .S_AXI_RVALID(qspi_axil_rvalid_wire), .S_AXI_RREADY(qspi_axil_rready)
    );

    // --- NPU CSR Koprusu ---
    logic [7:0] npu_axil_awaddr, npu_axil_araddr;
    logic        npu_axil_awvalid, npu_axil_awready;
    logic [31:0] npu_axil_wdata;  logic [3:0] npu_axil_wstrb;
    logic        npu_axil_wvalid, npu_axil_wready;
    logic [1:0]  npu_axil_bresp;  logic npu_axil_bvalid, npu_axil_bready;
    logic        npu_axil_arvalid, npu_axil_arready;
    logic [31:0] npu_axil_rdata_wire; logic [1:0] npu_axil_rresp;
    logic        npu_axil_rvalid_wire, npu_axil_rready;

    obi2axil #(.AXIL_ADDR_W(8)) u_npu_kopru (
        .clk(clk_i), .rst_n(rst_ni),
        .obi_req(npu_istek), .obi_gnt(npu_axil_onay),
        .obi_addr(veri_adres), .obi_we(veri_yazma), .obi_be(veri_bayt_en),
        .obi_wdata(veri_yazma_veri), .obi_rdata(npu_axil_okuma), .obi_rvalid(npu_axil_gecerli),
        .m_axil_awaddr(npu_axil_awaddr), .m_axil_awvalid(npu_axil_awvalid), .m_axil_awready(npu_axil_awready),
        .m_axil_wdata(npu_axil_wdata), .m_axil_wstrb(npu_axil_wstrb),
        .m_axil_wvalid(npu_axil_wvalid), .m_axil_wready(npu_axil_wready),
        .m_axil_bresp(npu_axil_bresp), .m_axil_bvalid(npu_axil_bvalid), .m_axil_bready(npu_axil_bready),
        .m_axil_araddr(npu_axil_araddr), .m_axil_arvalid(npu_axil_arvalid), .m_axil_arready(npu_axil_arready),
        .m_axil_rdata(npu_axil_rdata_wire), .m_axil_rresp(npu_axil_rresp),
        .m_axil_rvalid(npu_axil_rvalid_wire), .m_axil_rready(npu_axil_rready)
    );

    // NPU Top: CSR AXI-Lite slave + AXI4 master (YZ bellegi icin)
    npu_top #(
        .AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32), .AXI_ID_WIDTH(4), .CSR_ADDR_WIDTH(8)
    ) u_npu (
        .clk(clk_i), .rst_n(rst_ni),
        // CSR AXI-Lite Slave portu
        .s_axil_awaddr(npu_axil_awaddr), .s_axil_awvalid(npu_axil_awvalid), .s_axil_awready(npu_axil_awready),
        .s_axil_wdata(npu_axil_wdata), .s_axil_wstrb(npu_axil_wstrb),
        .s_axil_wvalid(npu_axil_wvalid), .s_axil_wready(npu_axil_wready),
        .s_axil_bresp(npu_axil_bresp), .s_axil_bvalid(npu_axil_bvalid), .s_axil_bready(npu_axil_bready),
        .s_axil_araddr(npu_axil_araddr), .s_axil_arvalid(npu_axil_arvalid), .s_axil_arready(npu_axil_arready),
        .s_axil_rdata(npu_axil_rdata_wire), .s_axil_rresp(npu_axil_rresp),
        .s_axil_rvalid(npu_axil_rvalid_wire), .s_axil_rready(npu_axil_rready),
        // AXI4 Master (YZ bellegi) - su an kapatilmis
        .m_axi_awid(), .m_axi_awaddr(), .m_axi_awlen(), .m_axi_awsize(), .m_axi_awburst(),
        .m_axi_awvalid(), .m_axi_awready(1'b1),
        .m_axi_wdata(), .m_axi_wstrb(), .m_axi_wlast(), .m_axi_wvalid(), .m_axi_wready(1'b1),
        .m_axi_bid(4'b0), .m_axi_bresp(2'b0), .m_axi_bvalid(1'b0), .m_axi_bready(),
        .m_axi_arid(), .m_axi_araddr(), .m_axi_arlen(), .m_axi_arsize(), .m_axi_arburst(),
        .m_axi_arvalid(), .m_axi_arready(1'b1),
        .m_axi_rid(4'b0), .m_axi_rdata(32'b0), .m_axi_rresp(2'b0), .m_axi_rlast(1'b0),
        .m_axi_rvalid(1'b0), .m_axi_rready(),
        .npu_irq(npu_kesme)
    );

endmodule
