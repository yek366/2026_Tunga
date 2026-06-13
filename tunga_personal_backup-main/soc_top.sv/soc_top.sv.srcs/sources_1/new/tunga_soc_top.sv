module tunga_soc_top (
    input  logic clk_i,
    input  logic rst_ni,
    
    // Dış Dünyaya Çıkacak Pinler
    output logic uart0_tx_o,
    input  logic uart0_rx_i
);

    // --- SAHTE BELLEK (DUMMY MEMORY) SİNYALLERİ ---
    logic core_instr_req;
    logic core_instr_valid;

    // İşlemci komut istediğinde (req=1), bir saat vuruşu sonra "Valid" (Geçerli) sinyali üret
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            core_instr_valid <= 1'b0;
        end else begin
            core_instr_valid <= core_instr_req;
        end
    end
    // ----------------------------------------------

    // CV32E40P Çekirdeğini Çağırma
    cv32e40p_core u_core (
        .clk_i               (clk_i),
        .rst_ni              (rst_ni),
        .pulp_clock_en_i     (1'b1), // Çekirdek sürekli aktif
        .scan_cg_en_i        (1'b0),
        
        // Boot Adresi ve Uyanış Sinyalleri
        .boot_addr_i         (32'h1A000000), 
        .fetch_enable_i      (1'b1),         // Çekirdeğe komut okumaya başla emri
        .mtvec_addr_i        (32'h00000000),
        .dm_halt_addr_i      (32'h00000000),
        .dm_exception_addr_i (32'h00000000),
        .hart_id_i           (32'h00000000),
        
        // Kesmeler
        .irq_i               (32'b0),
        .irq_ack_o           (),
        .irq_id_o            (),
        
        // OBI (Open Bus Interface) Komut Arayüzü (Burası Değişti!)
        .instr_req_o         (core_instr_req),
        .instr_gnt_i         (1'b1), 
        .instr_rvalid_i      (core_instr_valid),
        .instr_addr_o        (),
        .instr_rdata_i       (32'h00000013), // RISC-V NOP (Boş geç) komutunu bas!
        
        // OBI Veri İstek Arayüzü
        .data_req_o          (),
        .data_gnt_i          (1'b1),
        .data_rvalid_i       (1'b0),
        .data_we_o           (),
        .data_be_o           (),
        .data_addr_o         (),
        .data_wdata_o        (),
        .data_rdata_i        (32'b0)
    );

endmodule