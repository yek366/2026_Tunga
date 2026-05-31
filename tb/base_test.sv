`ifndef BASE_TEST_SV
`define BASE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_agent_pkg::*;

`include "seq_peripherals.sv"
`include "seq_ai_accelerator.sv"

class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    tunga_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = tunga_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        seq_peripherals    seq_periph;
        seq_ai_accelerator seq_ai;
        
        phase.raise_objection(this);
        
        `uvm_info("TEST", "UVM Test Senaryolari Basliyor...", UVM_LOW)
        
        // 1. Cevre Birimleri Test Senaryosu
        seq_periph = seq_peripherals::type_id::create("seq_periph");
        seq_periph.start(env.agent.sequencer);
        
        // 2. YZ Hizlandirici Test Senaryosu
        seq_ai = seq_ai_accelerator::type_id::create("seq_ai");
        seq_ai.start(env.agent.sequencer);

        #500ns;
        
        `uvm_info("TEST", "Tum UVM Test Senaryolari Tamamlandi.", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

`endif
