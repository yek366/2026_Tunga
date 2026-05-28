class seq_ai_accelerator extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(seq_ai_accelerator)

    // AXI-Lite VIP Register Adres Haritası (YZ Hızlandırıcı)
    localparam logic [31:0] AI_ACCEL_DATA_IN_ADDR  = 32'h5000_0000;
    localparam logic [31:0] AI_ACCEL_RESULT_ADDR   = 32'h5000_0004;
    
    // Kesme (interrupt) sinyalini beklemek icin virtual interface
    virtual tunga_soc_if vif;

    function new(string name = "seq_ai_accelerator");
        super.new(name);
    endfunction

    virtual task body();
        int fd_stim, fd_min, fd_max;
        int stimulus_data, expected_min, expected_max;
        logic [31:0] hw_result;

        // Eger VIF alinmamissa hata ver
        if (!uvm_config_db#(virtual tunga_soc_if)::get(null, get_full_name(), "vif", vif)) begin
            `uvm_fatal("NO_VIF", "Virtual interface 'vif' bulunamadi!")
        end

        `uvm_info(get_type_name(), "YZ Hizlandirici TFLite Micro Speech Senaryosu Basliyor...", UVM_LOW)

        // 1. Python Tarafindan Uretilen Golden Vector Dosyalarini Ac
        // Simülasyon 'sim' klasöründe koştuğu için yollar direkt alınır
        fd_stim = $fopen("ai_stimulus.hex", "r");
        fd_min  = $fopen("ai_expected_min.hex", "r");
        fd_max  = $fopen("ai_expected_max.hex", "r");

        if (!fd_stim || !fd_min || !fd_max) begin
            `uvm_fatal("FILE_ERR", "Python tarafindan uretilen .hex dosyalari okunamadi! Lutfen once generate_ai_golden.py betigini calistirin.")
        end

        // 2. Stimulus Verisini (Ses Verisi) UART-stream veya AXI uzerinden Donanima Sur
        `uvm_info("AI_TEST", "Stimulus verileri donanima aktariliyor...", UVM_LOW)
        while (!$feof(fd_stim)) begin
            if ($fscanf(fd_stim, "%h\n", stimulus_data) == 1) begin
                axi_write(AI_ACCEL_DATA_IN_ADDR, stimulus_data);
            end
        end

        // 3. Kesme (Interrupt) Bekle
        `uvm_info("AI_TEST", "Donanimin inference islemini bitirmesi (Interrupt) bekleniyor...", UVM_LOW)
        @(posedge vif.ai_interrupt);
        `uvm_info("AI_TEST", "Interrupt alindi, sonuc okunuyor...", UVM_LOW)

        // 4. Donanimin Hesapladigi Sonucu Oku
        axi_read(AI_ACCEL_RESULT_ADDR, hw_result);

        // 5. Tolerans Kontrolu (%10 Hata Payi) - Self-Checking
        void'($fscanf(fd_min, "%h\n", expected_min));
        void'($fscanf(fd_max, "%h\n", expected_max));

        `uvm_info("AI_TEST", $sformatf("Donanim Sonucu: %0d | Tolerans Araligi: [%0d, %0d]", hw_result, expected_min, expected_max), UVM_LOW)

        if (hw_result >= expected_min && hw_result <= expected_max) begin
            `uvm_info("AI_TEST", "BASARILI: Donanim sonucu %10 tolerans araligindadir.", UVM_LOW)
        end else begin
            `uvm_error("AI_TEST", $sformatf("HATA: Donanim sonucu (%0d) tolerans disinda [%0d, %0d]!", hw_result, expected_min, expected_max))
        end

        // Dosyalari kapat
        $fclose(fd_stim);
        $fclose(fd_min);
        $fclose(fd_max);

        `uvm_info(get_type_name(), "YZ Hizlandirici Test Senaryosu Tamamlandi.", UVM_LOW)
    endtask

    // Yardımcı Task: AXI-Lite Write
    virtual task axi_write(input logic [31:0] addr, input logic [31:0] data);
        axi_transaction req = axi_transaction::type_id::create("req");
        start_item(req);
        req.op = AXI_WRITE;
        req.addr = addr;
        req.data = data;
        finish_item(req);
    endtask

    // Yardımcı Task: AXI-Lite Read
    virtual task axi_read(input logic [31:0] addr, output logic [31:0] data);
        axi_transaction req = axi_transaction::type_id::create("req");
        start_item(req);
        req.op = AXI_READ;
        req.addr = addr;
        finish_item(req);
        data = req.data;
    endtask

endclass
