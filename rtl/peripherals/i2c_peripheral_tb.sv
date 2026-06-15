// Testbench for the I2C master peripheral

`timescale 1ns / 1ps

module i2c_peripheral_tb;

    // ================================================================
    //  Parameters
    // ================================================================
    localparam int SYS_CLK_FREQ = 48_000_000;
    localparam int I2C_FREQ     = 400_000;
    localparam real CLK_PERIOD  = 1_000_000_000.0 / SYS_CLK_FREQ;  // ~20.833 ns
    localparam real HALF_CLK    = CLK_PERIOD / 2.0;

    // Register addresses (byte-addressed, [4:2] selects register)
    localparam logic [7:0] ADDR_NBY = 8'h00;
    localparam logic [7:0] ADDR_ADR = 8'h04;
    localparam logic [7:0] ADDR_RDR = 8'h08;
    localparam logic [7:0] ADDR_TDR = 8'h0C;
    localparam logic [7:0] ADDR_CFG = 8'h10;

    // Slave address used by the behavioural model
    localparam logic [6:0] SLAVE_ADDR = 7'h50;

    // ================================================================
    //  Signals
    // ================================================================
    logic        clk;
    logic        rst_n;

    // AXI4-Lite
    logic [7:0]  awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;

    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;

    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    logic [7:0]  araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;

    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    // I2C
    wire         sda;
    wire         scl;

    // ================================================================
    //  Clock & Reset
    // ================================================================
    initial clk = 1'b0;
    always #(HALF_CLK) clk = ~clk;

    // ================================================================
    //  Pull-up Resistors  (weak-1 on open-drain lines)
    // ================================================================
    pullup pu_sda (sda);
    pullup pu_scl (scl);

    // ================================================================
    //  DUT Instantiation
    // ================================================================
    i2c_peripheral #(
        .SYS_CLK_FREQ (SYS_CLK_FREQ),
        .I2C_FREQ      (I2C_FREQ)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        // Write Address
        .s_axi_awaddr   (awaddr),
        .s_axi_awprot   (awprot),
        .s_axi_awvalid  (awvalid),
        .s_axi_awready  (awready),
        // Write Data
        .s_axi_wdata    (wdata),
        .s_axi_wstrb    (wstrb),
        .s_axi_wvalid   (wvalid),
        .s_axi_wready   (wready),
        // Write Response
        .s_axi_bresp    (bresp),
        .s_axi_bvalid   (bvalid),
        .s_axi_bready   (bready),
        // Read Address
        .s_axi_araddr   (araddr),
        .s_axi_arprot   (arprot),
        .s_axi_arvalid  (arvalid),
        .s_axi_arready  (arready),
        // Read Data
        .s_axi_rdata    (rdata),
        .s_axi_rresp    (rresp),
        .s_axi_rvalid   (rvalid),
        .s_axi_rready   (rready),
        // I2C
        .sda            (sda),
        .scl            (scl)
    );

    // ================================================================
    //  I2C Slave Behavioural Driver
    // ================================================================
    //  Open-drain driver shared with the DUT on the same SDA wire.
    //  The slave drives SDA low when sda_slave_oe = 1, else releases.
    logic sda_slave_oe;
    assign sda = sda_slave_oe ? 1'b0 : 1'bz;

    // ================================================================
    //  Counters / Scoreboards
    // ================================================================
    int tests_passed;
    int tests_failed;

    // ================================================================
    //  AXI4-Lite Master Utility Tasks
    // ================================================================

    //  Initialise all AXI master outputs to idle
    task automatic axi_idle();
        awaddr  = '0;   awprot = '0;  awvalid = 1'b0;
        wdata   = '0;   wstrb  = '0;  wvalid  = 1'b0;
        bready  = 1'b1;
        araddr  = '0;   arprot = '0;  arvalid = 1'b0;
        rready  = 1'b1;
    endtask

    //  AXI4-Lite write: drives AW+W simultaneously, waits for BRESP.
    task automatic axi_write(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        awaddr  <= addr;
        awvalid <= 1'b1;
        awprot  <= 3'd0;
        wdata   <= data;
        wstrb   <= 4'hF;
        wvalid  <= 1'b1;
        // Wait for handshake (both ready asserted in the same cycle)
        do @(posedge clk); while (!(awready && wready));
        awvalid <= 1'b0;
        wvalid  <= 1'b0;
        // Wait for write-response
        if (!bvalid) @(posedge clk iff bvalid);
        bready <= 1'b1;
        @(posedge clk);
        bready <= 1'b0;
        @(posedge clk);
        bready <= 1'b1;
    endtask

    //  AXI4-Lite read: drives AR, waits for RDATA.
    task automatic axi_read(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        araddr  <= addr;
        arvalid <= 1'b1;
        arprot  <= 3'd0;
        // Wait for arready
        do @(posedge clk); while (!arready);
        arvalid <= 1'b0;
        // Wait for rvalid
        if (!rvalid) @(posedge clk iff rvalid);
        data = rdata;
        rready <= 1'b1;
        @(posedge clk);
        rready <= 1'b0;
        @(posedge clk);
        rready <= 1'b1;
    endtask

    // ================================================================
    //  I2C Slave Primitive Tasks
    // ================================================================

    //  Wait for a START condition (SDA falls while SCL = 1).
    task automatic slv_wait_start();
        sda_slave_oe = 1'b0;          // make sure line is released
        forever begin
            @(negedge sda);
            if (scl === 1'b1) return;
        end
    endtask

    //  Receive one byte from the master (MSB first, 8 posedge-SCL samples).
    task automatic slv_receive_byte(output logic [7:0] data);
        data = 8'd0;
        for (int i = 7; i >= 0; i--) begin
            @(posedge scl);
            #1;                        // small hold for stable sampling
            data[i] = sda;
        end
    endtask

    //  Drive ACK (SDA = 0) for one SCL cycle.
    task automatic slv_send_ack();
        @(negedge scl);
        sda_slave_oe = 1'b1;          // drive low = ACK
        @(posedge scl);               // master clocks the ACK bit
        @(negedge scl);
        sda_slave_oe = 1'b0;          // release
    endtask

    //  Drive NACK (SDA released = 1) for one SCL cycle.
    task automatic slv_send_nack();
        @(negedge scl);
        sda_slave_oe = 1'b0;          // release = NACK (pulled high)
        @(posedge scl);
        @(negedge scl);
    endtask

    //  Send one byte to the master (MSB first).
    //  After all 8 bits, release SDA so the master can ACK/NACK.
    //  Returns 1 if master ACKed, 0 if NACKed.
    task automatic slv_send_byte(input logic [7:0] data, output logic master_acked);
        // Drive 8 data bits, each set up on negedge SCL
        for (int i = 7; i >= 0; i--) begin
            // SDA is set while SCL is low (we're already at negedge from
            // the previous iteration, or from the ACK that preceded this call)
            sda_slave_oe = ~data[i];   // 1 → release (high), 0 → drive low
            @(posedge scl);            // master samples
            @(negedge scl);            // SCL falls → ready for next bit
        end
        // Release SDA for master ACK / NACK
        sda_slave_oe = 1'b0;
        @(posedge scl);
        #1;
        master_acked = (sda === 1'b0); // ACK = low, NACK = high
        @(negedge scl);
    endtask

    // ================================================================
    //  High-Level Slave Transaction Tasks
    // ================================================================

    /// Respond to a WRITE transaction.
    /// Waits for START, verifies address, receives `num_bytes` data bytes
    /// into `rx_bytes`, sends ACK for each.
    /// If address does not match, sends NACK and returns with addr_match=0.
    task automatic slv_handle_write(
        input  logic [6:0]  exp_addr,
        input  int          num_bytes,
        output logic [7:0]  rx_bytes [0:3],
        output logic        addr_match
    );
        logic [7:0] addr_byte;

        slv_wait_start();

        // Receive address + R/W
        slv_receive_byte(addr_byte);
        addr_match = (addr_byte[7:1] == exp_addr) && (addr_byte[0] == 1'b0);

        if (!addr_match) begin
            slv_send_nack();
            return;
        end

        slv_send_ack();

        // Receive data bytes
        for (int b = 0; b < num_bytes; b++) begin
            slv_receive_byte(rx_bytes[b]);
            $display("  [SLAVE-WR] byte[%0d] = 0x%02h", b, rx_bytes[b]);
            slv_send_ack();
        end
        // Master will now issue STOP; slave just returns.
    endtask

    /// Respond to a READ transaction.
    /// Waits for START, verifies address, sends `num_bytes` data bytes
    /// from `tx_bytes`.  Expects master to ACK all but the last (NACK).
    task automatic slv_handle_read(
        input  logic [6:0]  exp_addr,
        input  int          num_bytes,
        input  logic [7:0]  tx_bytes [0:3],
        output logic        addr_match
    );
        logic [7:0] addr_byte;
        logic        acked;

        slv_wait_start();

        // Receive address + R/W
        slv_receive_byte(addr_byte);
        addr_match = (addr_byte[7:1] == exp_addr) && (addr_byte[0] == 1'b1);

        if (!addr_match) begin
            slv_send_nack();
            return;
        end

        slv_send_ack();

        // Send data bytes
        for (int b = 0; b < num_bytes; b++) begin
            $display("  [SLAVE-RD] sending byte[%0d] = 0x%02h", b, tx_bytes[b]);
            slv_send_byte(tx_bytes[b], acked);
            if (b < num_bytes - 1) begin
                if (!acked) begin
                    $display("  [SLAVE-RD] WARNING: unexpected NACK after byte %0d", b);
                    return;
                end
            end else begin
                // Last byte – expect NACK
                if (acked)
                    $display("  [SLAVE-RD] WARNING: expected NACK on last byte, got ACK");
            end
        end
        // Master will now issue STOP; slave just returns.
    endtask

    /// Respond with NACK to an address that does NOT match.
    task automatic slv_handle_nack();
        logic [7:0] addr_byte;
        slv_wait_start();
        slv_receive_byte(addr_byte);
        slv_send_nack();
        $display("  [SLAVE] NACKed address 0x%02h", addr_byte[7:1]);
    endtask

    // ================================================================
    //  Wait-for-Done Helpers
    // ================================================================

    task automatic wait_tx_done(int timeout_us = 500);
        int cyc = 0;
        int limit = int'(timeout_us * 1000.0 / CLK_PERIOD);
        while (dut.reg_cfg[1] !== 1'b1) begin
            @(posedge clk);
            cyc++;
            if (cyc > limit) begin
                $error("TIMEOUT waiting for TX_DONE");
                tests_failed++;
                return;
            end
        end
    endtask

    task automatic wait_rx_done(int timeout_us = 500);
        int cyc = 0;
        int limit = int'(timeout_us * 1000.0 / CLK_PERIOD);
        while (dut.reg_cfg[3] !== 1'b1) begin
            @(posedge clk);
            cyc++;
            if (cyc > limit) begin
                $error("TIMEOUT waiting for RX_DONE");
                tests_failed++;
                return;
            end
        end
    endtask

    // ================================================================
    //  Check helper
    // ================================================================
    task automatic check(input string label, input logic [31:0] actual,
                         input logic [31:0] expected);
        if (actual === expected) begin
            $display("  [PASS] %s : 0x%08h", label, actual);
            tests_passed++;
        end else begin
            $display("  [FAIL] %s : got 0x%08h, expected 0x%08h",
                     label, actual, expected);
            tests_failed++;
        end
    endtask

    // ================================================================
    //  Main Test Sequence
    // ================================================================
    initial begin
        logic [31:0] rd_val;
        logic [7:0]  slv_rx [0:3];
        logic        slv_match;

        tests_passed = 0;
        tests_failed = 0;
        sda_slave_oe = 1'b0;

        // ---- Reset ----
        axi_idle();
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ============================================================
        //  TEST 1 : Register read / write & readback
        // ============================================================
        $display("\n===== TEST 1: Register Read/Write =====");

        axi_write(ADDR_NBY, 32'd3);
        axi_read(ADDR_NBY, rd_val);
        check("NBY write 3", rd_val, 32'd3);

        axi_write(ADDR_ADR, 32'h0000_00FF);   // only [6:0] stored
        axi_read(ADDR_ADR, rd_val);
        check("ADR masked", rd_val, 32'h0000_007F);

        axi_write(ADDR_TDR, 32'hDEAD_BEEF);
        axi_read(ADDR_TDR, rd_val);
        check("TDR readback", rd_val, 32'hDEAD_BEEF);

        // RDR is read-only; write should be ignored
        axi_write(ADDR_RDR, 32'h1234_5678);
        axi_read(ADDR_RDR, rd_val);
        check("RDR read-only", rd_val, 32'd0);    // still reset value

        // CFG readback (nothing enabled)
        axi_read(ADDR_CFG, rd_val);
        check("CFG initial", rd_val, 32'd0);

        // ============================================================
        //  TEST 2 : NBY clamping
        // ============================================================
        $display("\n===== TEST 2: NBY Clamping =====");

        axi_write(ADDR_NBY, 32'd0);
        axi_read(ADDR_NBY, rd_val);
        check("NBY clamp 0->1", rd_val, 32'd1);

        axi_write(ADDR_NBY, 32'd99);
        axi_read(ADDR_NBY, rd_val);
        check("NBY clamp 99->4", rd_val, 32'd4);

        axi_write(ADDR_NBY, 32'd2);
        axi_read(ADDR_NBY, rd_val);
        check("NBY normal 2", rd_val, 32'd2);

        // ============================================================
        //  TEST 3 : Single-byte TX
        // ============================================================
        $display("\n===== TEST 3: Single-Byte TX =====");

        axi_write(ADDR_ADR, {25'd0, SLAVE_ADDR});
        axi_write(ADDR_NBY, 32'd1);
        axi_write(ADDR_TDR, 32'h000000AB);

        fork
            // Slave side: expect 1 write byte
            slv_handle_write(SLAVE_ADDR, 1, slv_rx, slv_match);
            // Master side: trigger TX
            begin
                axi_write(ADDR_CFG, 32'h0000_0001);   // TX_EN
                wait_tx_done();
            end
        join

        check("T3 addr match", {31'd0, slv_match}, 32'd1);
        check("T3 byte[0]", {24'd0, slv_rx[0]}, 32'h0000_00AB);

        // Read CFG: TX_DONE=1, TX_EN=0
        axi_read(ADDR_CFG, rd_val);
        check("T3 CFG", rd_val, 32'h0000_0002);   // bit[1] set

        // Clear TX_DONE
        axi_write(ADDR_CFG, 32'h0000_0000);
        axi_read(ADDR_CFG, rd_val);
        check("T3 CFG cleared", rd_val, 32'd0);

        // ============================================================
        //  TEST 4 : Multi-byte TX  (3 bytes)
        // ============================================================
        $display("\n===== TEST 4: Multi-Byte TX (3 bytes) =====");

        axi_write(ADDR_NBY, 32'd3);
        axi_write(ADDR_TDR, 32'h00_33_22_11);   // byte0=0x11, byte1=0x22, byte2=0x33

        fork
            slv_handle_write(SLAVE_ADDR, 3, slv_rx, slv_match);
            begin
                axi_write(ADDR_CFG, 32'h0000_0001);
                wait_tx_done();
            end
        join

        check("T4 addr match", {31'd0, slv_match}, 32'd1);
        check("T4 byte[0]", {24'd0, slv_rx[0]}, 32'h11);
        check("T4 byte[1]", {24'd0, slv_rx[1]}, 32'h22);
        check("T4 byte[2]", {24'd0, slv_rx[2]}, 32'h33);

        // Clear done
        axi_write(ADDR_CFG, 32'd0);

        // ============================================================
        //  TEST 5 : Single-byte RX
        // ============================================================
        $display("\n===== TEST 5: Single-Byte RX =====");

        begin
            logic [7:0] tx_pattern [0:3];
            tx_pattern[0] = 8'hCA;
            tx_pattern[1] = 8'h00;
            tx_pattern[2] = 8'h00;
            tx_pattern[3] = 8'h00;

            axi_write(ADDR_NBY, 32'd1);

            fork
                slv_handle_read(SLAVE_ADDR, 1, tx_pattern, slv_match);
                begin
                    axi_write(ADDR_CFG, 32'h0000_0004);   // RX_EN
                    wait_rx_done();
                end
            join

            check("T5 addr match", {31'd0, slv_match}, 32'd1);
            axi_read(ADDR_RDR, rd_val);
            check("T5 RDR", rd_val, 32'h0000_00CA);

            axi_read(ADDR_CFG, rd_val);
            check("T5 CFG", rd_val, 32'h0000_0008);   // RX_DONE bit[3]
        end

        // Clear done
        axi_write(ADDR_CFG, 32'd0);

        // ============================================================
        //  TEST 6 : Multi-byte RX  (4 bytes)
        // ============================================================
        $display("\n===== TEST 6: Multi-Byte RX (4 bytes) =====");

        begin
            logic [7:0] tx_pattern [0:3];
            tx_pattern[0] = 8'hDE;
            tx_pattern[1] = 8'hAD;
            tx_pattern[2] = 8'hBE;
            tx_pattern[3] = 8'hEF;

            axi_write(ADDR_NBY, 32'd4);

            fork
                slv_handle_read(SLAVE_ADDR, 4, tx_pattern, slv_match);
                begin
                    axi_write(ADDR_CFG, 32'h0000_0004);   // RX_EN
                    wait_rx_done();
                end
            join

            check("T6 addr match", {31'd0, slv_match}, 32'd1);
            axi_read(ADDR_RDR, rd_val);
            // byte0→[7:0]=0xDE, byte1→[15:8]=0xAD, byte2→[23:16]=0xBE, byte3→[31:24]=0xEF
            check("T6 RDR", rd_val, 32'hEFBE_ADDE);
        end

        // Clear done
        axi_write(ADDR_CFG, 32'd0);

        // ============================================================
        //  TEST 7 : NACK on address (slave doesn't respond)
        // ============================================================
        $display("\n===== TEST 7: NACK on Address =====");

        axi_write(ADDR_ADR, {25'd0, 7'h3F});  // wrong address
        axi_write(ADDR_NBY, 32'd1);
        axi_write(ADDR_TDR, 32'hFF);

        fork
            slv_handle_nack();                 // slave NACKs any address
            begin
                axi_write(ADDR_CFG, 32'h0000_0001);
                wait_tx_done();
            end
        join

        // TX_DONE should still be set (operation completed, albeit with NACK)
        axi_read(ADDR_CFG, rd_val);
        check("T7 TX_DONE after NACK", rd_val[1], 1'b1);

        // Clear done
        axi_write(ADDR_CFG, 32'd0);

        // ============================================================
        //  TEST 8 : Race-condition guard (TX+RX → TX wins)
        // ============================================================
        $display("\n===== TEST 8: Race Condition Guard =====");

        axi_write(ADDR_ADR, {25'd0, SLAVE_ADDR});
        axi_write(ADDR_NBY, 32'd1);
        axi_write(ADDR_TDR, 32'h77);

        // Set both TX_EN and RX_EN simultaneously → TX should win
        fork
            // Slave expects a WRITE (because TX is prioritised)
            slv_handle_write(SLAVE_ADDR, 1, slv_rx, slv_match);
            begin
                axi_write(ADDR_CFG, 32'h0000_0005);   // bits [0]+[2]
                wait_tx_done();
            end
        join

        check("T8 addr match (TX)", {31'd0, slv_match}, 32'd1);
        check("T8 byte[0]", {24'd0, slv_rx[0]}, 32'h77);

        axi_read(ADDR_CFG, rd_val);
        check("T8 CFG TX_DONE", rd_val[1], 1'b1);
        check("T8 CFG RX_EN cleared", rd_val[2], 1'b0);   // should not have been set

        // Clear done
        axi_write(ADDR_CFG, 32'd0);

        // ============================================================
        //  Summary
        // ============================================================
        $display("\n======================================");
        $display("  PASSED: %0d", tests_passed);
        $display("  FAILED: %0d", tests_failed);
        $display("======================================");
        if (tests_failed == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $display("======================================\n");

        #1000;
        $finish;
    end

    // ================================================================
    //  Timeout Watchdog
    // ================================================================
    initial begin
        #10_000_000;    // 10 ms absolute timeout
        $display("\n[WATCHDOG] Simulation timed out after 10 ms!");
        $finish;
    end

    // ================================================================
    //  Optional: VCD Dump
    // ================================================================
    initial begin
        $dumpfile("i2c_peripheral_tb.vcd");
        $dumpvars(0, i2c_peripheral_tb);
    end

endmodule
