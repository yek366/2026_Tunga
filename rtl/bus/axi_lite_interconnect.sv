`timescale 1ns / 1ps
// 2-Master, 8-Slave AXI-Lite interconnect

import axi_pkg::*;
import memory_map_pkg::*;

module axi_lite_interconnect #(
    parameter type req_t = axi_pkg::axi_req_t,
    parameter type rsp_t = axi_pkg::axi_rsp_t
) (
    input logic clk_i,
    input logic rst_ni,

    // Master Ports (from cores/bridges)
    input  req_t [1:0] master_req_i,
    output rsp_t [1:0] master_rsp_o,

    // Slave Ports (to memories/peripherals)
    output req_t [7:0] slave_req_o,
    input  rsp_t [7:0] slave_rsp_i
);

  // Address Decoder Function
  function automatic int decode_address(logic [31:0] addr);
    if (addr >= memory_map_pkg::ROM_BASE_ADDR && addr <= memory_map_pkg::ROM_HIGH_ADDR)
      return 0; // ROM
    else if (addr >= memory_map_pkg::SRAM_BASE_ADDR && addr <= memory_map_pkg::SRAM_HIGH_ADDR)
      return 1; // SRAM
    else if (addr >= memory_map_pkg::UART_BASE_ADDR && addr <= memory_map_pkg::UART_HIGH_ADDR)
      return 2; // UART
    else if (addr >= memory_map_pkg::GPIO_BASE_ADDR && addr <= memory_map_pkg::GPIO_HIGH_ADDR)
      return 3; // GPIO
    else if (addr >= memory_map_pkg::TIMER_BASE_ADDR && addr <= memory_map_pkg::TIMER_HIGH_ADDR)
      return 4; // TIMER
    else if (addr >= memory_map_pkg::I2C_BASE_ADDR && addr <= memory_map_pkg::I2C_HIGH_ADDR)
      return 5; // I2C
    else if (addr >= memory_map_pkg::QSPI_BASE_ADDR && addr <= memory_map_pkg::QSPI_HIGH_ADDR)
      return 6; // QSPI
    else if (addr >= memory_map_pkg::NPU_BASE_ADDR && addr <= memory_map_pkg::NPU_HIGH_ADDR)
      return 7; // NPU
    else
      return -1; // Decode error / Unmapped
  endfunction

  // ---------------------------------------------------------------------------
  // WRITE CHANNEL ROUTING (Master 1 only)
  // ---------------------------------------------------------------------------
  int m1_aw_sel;
  always_comb begin
    m1_aw_sel = decode_address(master_req_i[1].aw.addr);
  end

  // Write channel routing will be handled in the unified always_comb block at the bottom

  always_comb begin
    master_rsp_o[1].aw_ready = 1'b0;
    master_rsp_o[1].w_ready  = 1'b0;
    master_rsp_o[1].b        = '0;
    master_rsp_o[1].b_valid  = 1'b0;

    if (m1_aw_sel >= 0 && m1_aw_sel < 8) begin
      master_rsp_o[1].aw_ready = slave_rsp_i[m1_aw_sel].aw_ready;
      master_rsp_o[1].w_ready  = slave_rsp_i[m1_aw_sel].w_ready;
      master_rsp_o[1].b        = slave_rsp_i[m1_aw_sel].b;
      master_rsp_o[1].b_valid  = slave_rsp_i[m1_aw_sel].b_valid;
    end
  end

  // Master 0 (Instruction Master) write channels are unused
  assign master_rsp_o[0].aw_ready = 1'b0;
  assign master_rsp_o[0].w_ready  = 1'b0;
  assign master_rsp_o[0].b        = '0;
  assign master_rsp_o[0].b_valid  = 1'b0;

  // ---------------------------------------------------------------------------
  // READ CHANNEL ROUTING AND ARBITRATION (Masters 0 & 1)
  // ---------------------------------------------------------------------------
  int m0_ar_sel, m1_ar_sel;
  always_comb begin
    m0_ar_sel = decode_address(master_req_i[0].ar.addr);
    m1_ar_sel = decode_address(master_req_i[1].ar.addr);
  end

  // Read request arbiter signals per slave
  logic [7:0] m0_read_req;
  logic [7:0] m1_read_req;
  logic [7:0] ar_granted_master; // 0 = Master 0, 1 = Master 1

  always_comb begin
    for (int i = 0; i < 8; i++) begin
      m0_read_req[i] = master_req_i[0].ar_valid && (m0_ar_sel == i);
      m1_read_req[i] = master_req_i[1].ar_valid && (m1_ar_sel == i);

      // Shared memory slaves (ROM and SRAM) perform arbitration
      if (i == 0 || i == 1) begin
        // Prioritize Data read (Master 1) over Instruction read (Master 0)
        if (m1_read_req[i]) begin
          ar_granted_master[i] = 1'b1;
        end else begin
          ar_granted_master[i] = 1'b0;
        end
      end else begin
        // Non-shared peripherals can only be accessed by Master 1
        ar_granted_master[i] = 1'b1;
      end
    end
  end

  // Read address channel routing will be handled in the unified always_comb block at the bottom

  // Route ar_ready back to Master 0 and Master 1
  always_comb begin
    master_rsp_o[0].ar_ready = 1'b0;
    if (m0_ar_sel == 0 || m0_ar_sel == 1) begin
      if (ar_granted_master[m0_ar_sel] == 1'b0) begin
        master_rsp_o[0].ar_ready = slave_rsp_i[m0_ar_sel].ar_ready;
      end
    end

    master_rsp_o[1].ar_ready = 1'b0;
    if (m1_ar_sel >= 0 && m1_ar_sel < 8) begin
      if (m1_ar_sel == 0 || m1_ar_sel == 1) begin
        if (ar_granted_master[m1_ar_sel] == 1'b1) begin
          master_rsp_o[1].ar_ready = slave_rsp_i[m1_ar_sel].ar_ready;
        end
      end else begin
        master_rsp_o[1].ar_ready = slave_rsp_i[m1_ar_sel].ar_ready;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // READ RESPONSE TRACKING AND ROUTING
  // ---------------------------------------------------------------------------
  // For each slave, track the Master ID of outstanding read requests
  logic [1:0] read_tracker_wptr  [8];
  logic [1:0] read_tracker_rptr  [8];
  logic [3:0] read_tracker_empty [8];
  logic       read_tracker_val   [8][4];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < 8; i++) begin
        read_tracker_wptr[i]  <= '0;
        read_tracker_rptr[i]  <= '0;
        read_tracker_empty[i] <= 4'b1111;
        for (int j = 0; j < 4; j++) begin
          read_tracker_val[i][j] <= '0;
        end
      end
    end else begin
      for (int i = 0; i < 8; i++) begin
        // Push granted master ID to tracker
        if (slave_req_o[i].ar_valid && slave_rsp_i[i].ar_ready) begin
          read_tracker_val[i][read_tracker_wptr[i]]  <= ar_granted_master[i];
          read_tracker_wptr[i]                       <= read_tracker_wptr[i] + 1;
          read_tracker_empty[i][read_tracker_wptr[i]] <= 1'b0;
        end
        // Pop from tracker when response is accepted by the master
        if (slave_rsp_i[i].r_valid && slave_req_o[i].r_ready) begin
          read_tracker_rptr[i]                       <= read_tracker_rptr[i] + 1;
          read_tracker_empty[i][read_tracker_rptr[i]] <= 1'b1;
        end
      end
    end
  end

  // Identify active valid read responses per slave
  logic [7:0] active_master;
  logic [7:0] r_valid_active;

  always_comb begin
    for (int i = 0; i < 8; i++) begin
      active_master[i]  = read_tracker_val[i][read_tracker_rptr[i]];
      r_valid_active[i] = slave_rsp_i[i].r_valid && !read_tracker_empty[i][read_tracker_rptr[i]];
    end
  end

  // Route Read Responses back to Master 0
  logic m0_r_valid_s0, m0_r_valid_s1;
  assign m0_r_valid_s0 = r_valid_active[0] && (active_master[0] == 1'b0);
  assign m0_r_valid_s1 = r_valid_active[1] && (active_master[1] == 1'b0);

  // Master 0 read response routing
  always_comb begin
    master_rsp_o[0].r       = '0;
    master_rsp_o[0].r_valid = 1'b0;

    if (m0_r_valid_s0) begin
      master_rsp_o[0].r       = slave_rsp_i[0].r;
      master_rsp_o[0].r_valid = 1'b1;
    end else if (m0_r_valid_s1) begin
      master_rsp_o[0].r       = slave_rsp_i[1].r;
      master_rsp_o[0].r_valid = 1'b1;
    end
  end

  // Route Read Responses back to Master 1
  logic [7:0] m1_r_valids;
  always_comb begin
    for (int i = 0; i < 8; i++) begin
      m1_r_valids[i] = r_valid_active[i] && (active_master[i] == 1'b1);
    end
  end

  // Master 1 read response routing
  always_comb begin
    master_rsp_o[1].r       = '0;
    master_rsp_o[1].r_valid = 1'b0;

    // Priority response routing: SRAM has highest priority, then ROM, then peripherals
    if (m1_r_valids[1]) begin
      master_rsp_o[1].r       = slave_rsp_i[1].r;
      master_rsp_o[1].r_valid = 1'b1;
    end else if (m1_r_valids[0]) begin
      master_rsp_o[1].r       = slave_rsp_i[0].r;
      master_rsp_o[1].r_valid = 1'b1;
    end else begin
      logic routed;
      routed = 1'b0;
      for (int i = 2; i < 8; i++) begin
        if (m1_r_valids[i] && !routed) begin
          master_rsp_o[1].r       = slave_rsp_i[i].r;
          master_rsp_o[1].r_valid = 1'b1;
          routed                  = 1'b1;
        end
      end
    end
  end

  // Unified Request & Ready routing for all Slaves to avoid procedural multiple drivers
  always_comb begin
    // 1. Set default values for all slaves
    for (int i = 0; i < 8; i++) begin
      // Write Channel Defaults (Master 1 only)
      slave_req_o[i].aw       = master_req_i[1].aw;
      slave_req_o[i].aw_valid = 1'b0;
      slave_req_o[i].w        = master_req_i[1].w;
      slave_req_o[i].w_valid  = 1'b0;
      slave_req_o[i].b_ready  = 1'b0;

      // Read Address Channel Routing and Arbitration (Master 0 & Master 1)
      if (i == 0 || i == 1) begin
        slave_req_o[i].ar       = ar_granted_master[i] ? master_req_i[1].ar : master_req_i[0].ar;
        slave_req_o[i].ar_valid = ar_granted_master[i] ? m1_read_req[i] : m0_read_req[i];
      end else begin
        slave_req_o[i].ar       = master_req_i[1].ar;
        slave_req_o[i].ar_valid = m1_read_req[i];
      end

      // Read Response Channel Ready Default
      slave_req_o[i].r_ready  = 1'b0;
    end

    // 2. Enable write channels to the decoded slave
    if (m1_aw_sel >= 0 && m1_aw_sel < 8) begin
      slave_req_o[m1_aw_sel].aw_valid = master_req_i[1].aw_valid;
      slave_req_o[m1_aw_sel].w_valid  = master_req_i[1].w_valid;
      slave_req_o[m1_aw_sel].b_ready  = master_req_i[1].b_ready;
    end

    // 3. Route Read Response Ready (r_ready) back to Slaves
    // Master 0 read ready routing (SRAM/ROM only)
    if (m0_r_valid_s0) begin
      slave_req_o[0].r_ready = master_req_i[0].r_ready;
    end
    if (m0_r_valid_s1) begin
      slave_req_o[1].r_ready = master_req_i[0].r_ready;
    end

    // Master 1 read ready routing (with priority)
    if (m1_r_valids[1]) begin
      slave_req_o[1].r_ready = master_req_i[1].r_ready;
    end else if (m1_r_valids[0]) begin
      slave_req_o[0].r_ready = master_req_i[1].r_ready;
    end else begin
      logic routed;
      routed = 1'b0;
      for (int i = 2; i < 8; i++) begin
        if (m1_r_valids[i] && !routed) begin
          slave_req_o[i].r_ready = master_req_i[1].r_ready;
          routed                  = 1'b1;
        end
      end
    end
  end

endmodule
