`ifndef TUNGA_ENV_SV
`define TUNGA_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_agent_pkg::*;

// Coverage collector iin tip uyumunu (typedef) saglayalim:
typedef axi_transaction tunga_soc_transaction;
`include "coverage_collector.sv"

class tunga_env extends uvm_env;
    `uvm_component_utils(tunga_env)
    
    axi_agent          agent;
    coverage_collector cov;
    axi_scoreboard     scb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = axi_agent::type_id::create("agent", this);
        cov   = coverage_collector::type_id::create("cov", this);
        scb   = axi_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Monitor'un okudugu (yakaladigi) AXI islemlerini Coverage'a aktariyoruz
        agent.monitor.ap.connect(cov.analysis_export);
        // Ayni zamanda Scoreboard'a da bagliyoruz
        agent.monitor.ap.connect(scb.item_fifo.analysis_export);
    endfunction
endclass

`endif
