module tunga_soc_top (
    input  logic clk_i,
    input  logic rst_ni,
    
    // Dış Dünyaya Çıkacak Pinler (UART vs. Enes'ten gelecek)
    output logic uart0_tx_o,
    input  logic uart0_rx_i
);

    // CV32E40P Çekirdeğini Çağırma (Instantiation)
    cv32e40p_core u_core (
        .clk_i         (clk_i),
        .rst_ni        (rst_ni),
        .pulp_clock_en_i(1'b1), // Çekirdek sürekli aktif
        .scan_cg_en_i  (1'b0),
        
        // Boot Adresi (Yağmur'un Bootloader'ı buraya yönlendirecek)
        .boot_addr_i   (32'h1A000000), 
        
        // Kesmeler (Ali Salih'in YZ modülünden gelecek irq_i)
        .irq_i         (32'b0), // Şimdilik 0'a bağlıyoruz
        .irq_ack_o     (),
        .irq_id_o      (),
        
        // OBI (Open Bus Interface) Bağlantıları (Sevda'nın Köprüsü İçin)
        .instr_req_o   (),
        .instr_gnt_i   (1'b1), // Simülasyon için şimdilik sürekli onay veriyoruz
        .instr_rvalid_i(1'b0),
        .instr_addr_o  (),
        .instr_rdata_i (32'b0),
        
        .data_req_o    (),
        .data_gnt_i    (1'b1),
        .data_rvalid_i (1'b0),
        .data_we_o     (),
        .data_be_o     (),
        .data_addr_o   (),
        .data_wdata_o  (),
        .data_rdata_i  (32'b0)
    );

endmodule