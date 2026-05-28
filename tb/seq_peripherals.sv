class seq_peripherals extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(seq_peripherals)

    // AXI-Lite VIP Register Adres Haritası (Örnek)
    localparam logic [31:0] UART_REG_ADDR  = 32'h4000_0000;
    localparam logic [31:0] TIMER_REG_ADDR = 32'h4001_0000;
    localparam logic [31:0] GPIO_REG_ADDR  = 32'h4002_0000;

    function new(string name = "seq_peripherals");
        super.new(name);
    endfunction

    virtual task body();
        logic [31:0] read_data;
        logic [31:0] write_data;

        `uvm_info(get_type_name(), "Cevre Birimleri Temel Test Senaryosu Basliyor...", UVM_LOW)

        // ----------------------------------------------------
        // 1. UART Modülü Testi
        // ----------------------------------------------------
        write_data = 32'hA5A5_0001;
        axi_write(UART_REG_ADDR, write_data);
        axi_read(UART_REG_ADDR, read_data);
        
        // Self-Checking (Kendi Kendini Kontrol)
        if (read_data !== write_data) begin
            `uvm_error("UART_TEST", $sformatf("HATA: Yazilan 0x%0h, Okunan 0x%0h", write_data, read_data))
        end else begin
            `uvm_info("UART_TEST", "BASARILI: Yazilan ve okunan veriler eslesiyor.", UVM_LOW)
        end

        // ----------------------------------------------------
        // 2. Timer Modülü Testi
        // ----------------------------------------------------
        write_data = 32'h0000_FFFF;
        axi_write(TIMER_REG_ADDR, write_data);
        axi_read(TIMER_REG_ADDR, read_data);
        
        // Self-Checking
        if (read_data !== write_data) begin
            `uvm_error("TIMER_TEST", $sformatf("HATA: Yazilan 0x%0h, Okunan 0x%0h", write_data, read_data))
        end else begin
            `uvm_info("TIMER_TEST", "BASARILI: Yazilan ve okunan veriler eslesiyor.", UVM_LOW)
        end

        // ----------------------------------------------------
        // 3. GPIO Modülü Testi
        // ----------------------------------------------------
        write_data = 32'hDEAD_BEEF;
        axi_write(GPIO_REG_ADDR, write_data);
        axi_read(GPIO_REG_ADDR, read_data);
        
        // Self-Checking
        if (read_data !== write_data) begin
            `uvm_error("GPIO_TEST", $sformatf("HATA: Yazilan 0x%0h, Okunan 0x%0h", write_data, read_data))
        end else begin
            `uvm_info("GPIO_TEST", "BASARILI: Yazilan ve okunan veriler eslesiyor.", UVM_LOW)
        end

        `uvm_info(get_type_name(), "Cevre Birimleri Temel Test Senaryosu Tamamlandi.", UVM_LOW)
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
