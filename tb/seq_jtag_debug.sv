class seq_jtag_debug extends uvm_sequence #(jtag_transaction);
    `uvm_object_utils(seq_jtag_debug)

    function new(string name = "seq_jtag_debug");
        super.new(name);
    endfunction

    virtual task body();
        jtag_transaction req;
        logic [31:0] read_data;

        `uvm_info(get_type_name(), "JTAG Debug Dogrulama Senaryosu Basliyor...", UVM_LOW)

        // 1. İşlemciyi Durdurma (Halt Core) Komutu
        `uvm_info("JTAG_TEST", "CV32E40P Çekirdegine HALT komutu gonderiliyor...", UVM_LOW)
        req = jtag_transaction::type_id::create("req");
        start_item(req);
        req.op = JTAG_IR_WRITE;
        req.ir_value = 5'h10; // DTM (Debug Transport Module) register seçimi (Sembolik)
        finish_item(req);

        req = jtag_transaction::type_id::create("req");
        start_item(req);
        req.op = JTAG_DR_WRITE;
        req.dr_value = 32'h00000001; // Halt request
        finish_item(req);

        // 2. Bir Yazmacı (Register) Okuma Komutu
        `uvm_info("JTAG_TEST", "Çekirdegin GPR (General Purpose Register) durumu okunuyor...", UVM_LOW)
        req = jtag_transaction::type_id::create("req");
        start_item(req);
        req.op = JTAG_DR_READ;
        finish_item(req);
        read_data = req.dr_value;

        `uvm_info("JTAG_TEST", $sformatf("JTAG uzerinden okunan Register Verisi: 0x%08X", read_data), UVM_LOW)

        `uvm_info(get_type_name(), "JTAG Debug Dogrulama Senaryosu Tamamlandi.", UVM_LOW)
    endtask
endclass
