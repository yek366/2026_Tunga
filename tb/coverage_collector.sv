`ifndef COVERAGE_COLLECTOR_SV
`define COVERAGE_COLLECTOR_SV

// Not: Bu dosya tunga_env.sv tarafindan include edilir.
// tunga_soc_transaction typedef'i ve uvm/axi_agent_pkg import'lari zaten mevcuttur.

class coverage_collector extends uvm_subscriber #(tunga_soc_transaction);
    `uvm_component_utils(coverage_collector)

    // Arayüz sinyallerine erişim için virtual interface
    virtual tunga_soc_if vif;

    // =========================================================================
    // FUNCTIONAL COVERAGE - Covergroup Tanımları
    // =========================================================================
    covergroup cg_functional_coverage;
        option.per_instance = 1;

        // 1. UART Baud Rate Yapılandırması - farklı hızlar test edildi mi?
        cp_uart_baud: coverpoint vif.uart_baud_rate {
            bins baud_9600   = {32'd9600};
            bins baud_115200 = {32'd115200};
            bins baud_others = default;
        }

        // 2. YZ Hızlandırıcı Kesme (Interrupt) durumu - kesme geldi mi?
        cp_ai_interrupt: coverpoint vif.ai_interrupt {
            bins interrupt_asserted = {1'b1};
            bins interrupt_cleared  = {1'b0};
            bins trans_0_to_1 = (0 => 1); // Yükselen kenar (Interrupt geldi)
        }

        // 3. AXI Write işlemi gerçekleşti mi?
        cp_valid: coverpoint vif.awvalid {
            bins write_active = {1'b1};
            bins write_idle   = {1'b0};
        }

        // 4. Hangi bellek bölgelerine yazıldı?
        cp_addr: coverpoint vif.awaddr {
            bins low_mem  = {[32'h0000_0000 : 32'h0000_0FFF]}; // Talimat SRAM
            bins ai_mem   = {[32'h0001_0000 : 32'h0001_FFFF]}; // AI Bellek
            bins csr_regs = {[32'h4000_0000 : 32'h4000_00FF]}; // CSR Yazmaçları
            bins others   = default;
        }

        // 5. Çapraz Kapsam: AXI write - AI kesme ilişkisi
        cross_axi_ai: cross cp_valid, cp_ai_interrupt;

        // 6. Çapraz Kapsam: Tüm adres bölgelerine write yapıldı mı?
        cr_write_regions: cross cp_valid, cp_addr;

    endgroup

    function new(string name = "coverage_collector", uvm_component parent = null);
        super.new(name, parent);
        cg_functional_coverage = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual tunga_soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("COV_COLL", "Virtual interface bulunamadi!")
    endfunction

    // Monitörden gelen her transaction'da coverage sample al
    virtual function void write(tunga_soc_transaction t);
        cg_functional_coverage.sample();
    endfunction

endclass

`endif // COVERAGE_COLLECTOR_SV
