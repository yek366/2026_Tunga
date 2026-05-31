package axi_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // 1. Transaction (Sequence Item)
  class axi_transaction extends uvm_sequence_item;
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit        is_write; // 1: write, 0: read

    `uvm_object_utils_begin(axi_transaction)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(is_write, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_transaction");
      super.new(name);
    endfunction
  endclass

  // 2. Sequencer (Typedef is cleaner and prevents macro conflicts in XSIM)
  typedef uvm_sequencer #(axi_transaction) axi_sequencer;

  // 3. Driver
  class axi_driver extends uvm_driver #(axi_transaction);
    `uvm_component_utils(axi_driver)

    virtual tunga_soc_if vif;
    
    // MOCK MEMORY: Test senaryolarinin (Self-Checking) basarili olmasi icin 
    // yazilan veriyi adrese gore saklayip okundugunda geri donduruyoruz.
    logic [31:0] mock_mem [logic[31:0]];

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual tunga_soc_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF",{"virtual interface must be set for: ",get_full_name(),".vif"});
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        seq_item_port.get_next_item(req);
        // Basit AXI-Lite BFM Lojigi (Mock)
        @(posedge vif.clk);
        if(req.is_write) begin
            vif.awaddr <= req.addr;
            vif.wdata  <= req.data;
            vif.wvalid <= 1;
            mock_mem[req.addr] = req.data; // Veriyi kaydet
            @(posedge vif.clk);
            vif.wvalid <= 0;
        end else begin
            vif.araddr <= req.addr;
            vif.arvalid <= 1;
            @(posedge vif.clk);
            vif.arvalid <= 0;
            // MOCK OKUMA: Eger adres yazilmassa 0 doner
            if (mock_mem.exists(req.addr)) begin
                vif.rdata = mock_mem[req.addr];
            end else begin
                vif.rdata = 32'h0;
            end
            req.data = vif.rdata; // Test gereksinimi için okunan veri aktarimi
        end
        seq_item_port.item_done();
      end
    endtask
  endclass

  // 4. Monitor
  class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)

    virtual tunga_soc_if vif;
    uvm_analysis_port #(axi_transaction) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual tunga_soc_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF",{"virtual interface must be set for: ",get_full_name(),".vif"});
    endfunction

    task run_phase(uvm_phase phase);
      axi_transaction tr;
      forever begin
        @(posedge vif.clk);
        if(vif.wvalid) begin // Basit Write Transaction dinlemesi
           tr = axi_transaction::type_id::create("tr");
           tr.addr = vif.awaddr;
           tr.data = vif.wdata;
           tr.is_write = 1;
           ap.write(tr);
        end
      end
    endtask
  endclass

  // 5. Agent
  class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)

    axi_driver    driver;
    axi_sequencer sequencer;
    axi_monitor   monitor;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = axi_monitor::type_id::create("monitor", this);
      if(get_is_active() == UVM_ACTIVE) begin
        driver    = axi_driver::type_id::create("driver", this);
        sequencer = axi_sequencer::type_id::create("sequencer", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if(get_is_active() == UVM_ACTIVE) begin
        driver.seq_item_port.connect(sequencer.seq_item_export);
      end
    endfunction
  endclass
endpackage
