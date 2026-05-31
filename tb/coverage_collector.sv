class coverage_collector extends uvm_subscriber #(tunga_soc_transaction);
    `uvm_component_utils(coverage_collector)

    // Sinyalleri örneklemek için virtual arayüz (Interface)
    virtual tunga_soc_if vif;

    // Covergroup Tanımlamaları (Functional Coverage)
    covergroup cg_functional_coverage;
        option.per_instance = 1;

        // 1. UART Baud Rate Yapılandırması Kapsamı
        cp_uart_baud: coverpoint vif.uart_baud_rate {
            bins baud_9600   = {32'd9600};
            bins baud_115200 = {32'd115200};
            bins baud_others = default;
        }

        // 2. YZ Hızlandırıcı Kesme (Interrupt) Yakalanma Durumu
        cp_ai_interrupt: coverpoint vif.ai_interrupt {
            bins interrupt_asserted = {1'b1};
            bins interrupt_cleared  = {1'b0};
            bins trans_0_to_1 = (0 => 1); // Kesme yükselen kenar (Yakalama durumu)
        }

        // 3. AXI Veri Yolu İşlemleri (Read/Write)
        cp_axi_operation: coverpoint vif.awvalid {
            bins write_transaction = {1'b1};
        }
        cp_axi_read_op: coverpoint vif.arvalid {
            bins read_transaction = {1'b1};
        }
        
        // Çapraz (Cross) Kapsam: AXI write yapılıp AI interrupt alındı mı?
        cross_axi_ai: cross cp_axi_operation, cp_ai_interrupt;
    endgroup

    function new(string name = "coverage_collector", uvm_component parent = null);
        super.new(name, parent);
        cg_functional_coverage = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual tunga_soc_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("COV_COLL", "Virtual interface bulunamadi!")
        end
    endfunction

    // Monitörden veya bus üzerinden analiz verisi geldikçe covergroup sample edilir
    virtual function void write(tunga_soc_transaction t);
        // Sinyaller arayüzden veya transaction (t) objesinden okunarak örneklenir
        cg_functional_coverage.sample();
    endfunction
endclass
