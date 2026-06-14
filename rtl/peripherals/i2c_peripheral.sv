//    - AXI4-Lite Slave for CPU register access (8-bit addr, 32-bit data)
//    - I2C Master with open-drain SDA/SCL
//    - Parameterised system clock (default 48 MHz) and I2C frequency (400 kHz)
//    - Hardware race-condition protection (TX/RX mutual exclusion)
//    - Single always_ff for all registers + FSM (no multiple-driver issues)
//    - HW Interrupt generation on TX_DONE or RX_DONE
//
//  Register Map:
//    0x00  I2C_NBY  [RW]  Number of bytes to transfer (1..4, clamped)
//    0x04  I2C_ADR  [RW]  7-bit slave address in [6:0]
//    0x08  I2C_RDR  [RO]  Read data (1-4 bytes, LSB-first packing)
//    0x0C  I2C_TDR  [RW]  Transmit data (1-4 bytes, LSB-first packing)
//    0x10  I2C_CFG  [RW]  [0] TX_EN  [1] TX_DONE  [2] RX_EN  [3] RX_DONE

module i2c_peripheral #(
    parameter int SYS_CLK_FREQ = 48_000_000,   // System clock in Hz
    parameter int I2C_FREQ     = 400_000       // I2C SCL frequency in Hz
) (
    // ----------------------------------------------------------------
    // System
    // ----------------------------------------------------------------
    input  logic        clk,
    input  logic        rst_n,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Write Address Channel
    // ----------------------------------------------------------------
    input  logic [7:0]  s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Write Data Channel
    // ----------------------------------------------------------------
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Write Response Channel
    // ----------------------------------------------------------------
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Read Address Channel
    // ----------------------------------------------------------------
    input  logic [7:0]  s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Read Data Channel
    // ----------------------------------------------------------------
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // ----------------------------------------------------------------
    // Hardware Interrupt
    // ----------------------------------------------------------------
    output logic        i2c_irq, // <--- EKLENEN INTERRUPT PINI

    // ----------------------------------------------------------------
    // I2C Physical Interface (active-low open-drain)
    // ----------------------------------------------------------------
    inout  wire         sda,
    inout  wire         scl
);

    // ================================================================
    //  Local Parameters
    // ================================================================
    localparam int QUARTER = SYS_CLK_FREQ / (4 * I2C_FREQ);  // 30 @ 48 MHz
    localparam int CW      = $clog2(QUARTER) > 0 ? $clog2(QUARTER) : 1;

    // ================================================================
    //  I2C FSM States
    // ================================================================
    typedef enum logic [3:0] {
        ST_IDLE     = 4'd0,
        ST_START    = 4'd1,
        ST_ADDR_BIT = 4'd2,
        ST_ADDR_ACK = 4'd3,
        ST_WR_BIT   = 4'd4,
        ST_WR_ACK   = 4'd5,
        ST_RD_BIT   = 4'd6,
        ST_RD_ACK   = 4'd7,
        ST_STOP     = 4'd8
    } state_t;

    // ================================================================
    //  Internal Signals
    // ================================================================

    // -- Peripheral registers --
    logic [31:0] reg_nby;           // 0x00
    logic [31:0] reg_adr;           // 0x04
    logic [31:0] reg_rdr;           // 0x08
    logic [31:0] reg_tdr;           // 0x0C
    logic [3:0]  reg_cfg;           // 0x10  (only bits [3:0] used)

    // --- INTERRUPT ATAMASI (Kombinatoryal) ---
    // Eğer TX_DONE (bit 1) veya RX_DONE (bit 3) 1 ise, kesme hattını tetikle
    assign i2c_irq = reg_cfg[1] | reg_cfg[3];

    // -- I2C FSM --
    state_t      state;
    logic [2:0]  bit_cnt;           // 0..7  bit position in current byte
    logic [2:0]  byte_cnt;          // 0..3  current byte index
    logic [7:0]  shift_out;         // TX shift register (MSB sent first)
    logic [7:0]  shift_in;          // RX shift register (MSB received first)
    logic        op_rw;             // Latched direction: 0 = write, 1 = read
    logic [2:0]  op_nby;            // Latched byte count (1..4)
    logic [6:0]  op_addr;           // Latched 7-bit slave address
    logic [31:0] op_tdr;            // Latched transmit data
    logic [31:0] rx_data;           // Accumulated received bytes
    logic        sda_sampled;       // SDA captured at sample point

    // -- I2C timing --
    logic [CW-1:0] tick_cnt;        // Counts clk cycles within a quarter
    logic [1:0]    phase;           // SCL quarter-phase (0..3)
    logic          i2c_active;
    logic          bit_done;        // Pulse: end of a full SCL bit period
    logic          sample;          // Pulse: SDA sample point (mid SCL-high)

    // -- I2C bus control --
    logic          sda_oe;          // 1 = drive SDA low, 0 = release
    logic          scl_oe;          // 1 = drive SCL low, 0 = release
    logic          sda_in;          // SDA bus read-back

    // -- AXI internal --
    logic          axi_wr_en;
    logic          axi_rd_en;
    logic [31:0]   rd_mux;

    // ================================================================
    //  Open-Drain Bus Assignments
    // ================================================================
    assign sda    = sda_oe ? 1'b0 : 1'bz;   // Drive low or release
    assign scl    = scl_oe ? 1'b0 : 1'bz;   // Drive low or release
    assign sda_in = sda;                     // Read-back (external pull-up)

    // ================================================================
    //  I2C Timing Generator
    // ================================================================
    assign i2c_active = (state != ST_IDLE);
    assign bit_done   = i2c_active &&
                        (phase    == 2'd3) &&
                        (tick_cnt == CW'(QUARTER - 1));
    assign sample     = i2c_active &&
                        (phase    == 2'd2) &&
                        (tick_cnt == {CW{1'b0}});

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= '0;
            phase    <= 2'd0;
        end else if (!i2c_active) begin
            tick_cnt <= '0;
            phase    <= 2'd0;
        end else begin
            if (tick_cnt == CW'(QUARTER - 1)) begin
                tick_cnt <= '0;
                phase    <= phase + 2'd1;   // wraps 3 -> 0
            end else begin
                tick_cnt <= tick_cnt + CW'(1);
            end
        end
    end

    // ================================================================
    //  SCL / SDA Combinational Output Logic
    // ================================================================
    always_comb begin
        sda_oe = 1'b0;
        scl_oe = 1'b0;

        case (state)
            ST_IDLE: begin
                sda_oe = 1'b0;
                scl_oe = 1'b0;
            end

            ST_START: begin
                case (phase)
                    2'd0: begin sda_oe = 1'b0; scl_oe = 1'b0; end
                    2'd1: begin sda_oe = 1'b1; scl_oe = 1'b0; end
                    2'd2: begin sda_oe = 1'b1; scl_oe = 1'b1; end
                    2'd3: begin sda_oe = 1'b1; scl_oe = 1'b1; end
                endcase
            end

            ST_ADDR_BIT,
            ST_WR_BIT: begin
                sda_oe = ~shift_out[7];       // 1-bit -> oe (inverted for open-drain)
                case (phase)
                    2'd0: scl_oe = 1'b1;
                    2'd1: scl_oe = 1'b0;
                    2'd2: scl_oe = 1'b0;
                    2'd3: scl_oe = 1'b1;
                endcase
            end

            ST_ADDR_ACK,
            ST_WR_ACK: begin
                sda_oe = 1'b0;               // Release for slave
                case (phase)
                    2'd0: scl_oe = 1'b1;
                    2'd1: scl_oe = 1'b0;
                    2'd2: scl_oe = 1'b0;
                    2'd3: scl_oe = 1'b1;
                endcase
            end

            ST_RD_BIT: begin
                sda_oe = 1'b0;
                case (phase)
                    2'd0: scl_oe = 1'b1;
                    2'd1: scl_oe = 1'b0;
                    2'd2: scl_oe = 1'b0;
                    2'd3: scl_oe = 1'b1;
                endcase
            end

            ST_RD_ACK: begin
                sda_oe = ((byte_cnt + 3'd1) < op_nby) ? 1'b1 : 1'b0;
                case (phase)
                    2'd0: scl_oe = 1'b1;
                    2'd1: scl_oe = 1'b0;
                    2'd2: scl_oe = 1'b0;
                    2'd3: scl_oe = 1'b1;
                endcase
            end

            ST_STOP: begin
                case (phase)
                    2'd0: begin sda_oe = 1'b1; scl_oe = 1'b1; end
                    2'd1: begin sda_oe = 1'b1; scl_oe = 1'b0; end
                    2'd2: begin sda_oe = 1'b0; scl_oe = 1'b0; end
                    2'd3: begin sda_oe = 1'b0; scl_oe = 1'b0; end
                endcase
            end

            default: begin
                sda_oe = 1'b0;
                scl_oe = 1'b0;
            end
        endcase
    end

    // ================================================================
    //  AXI4-Lite Slave - Write Channel
    // ================================================================
    assign axi_wr_en     = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    assign s_axi_awready = axi_wr_en;
    assign s_axi_wready  = axi_wr_en;
    assign s_axi_bresp   = 2'b00;                    // OKAY

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            s_axi_bvalid <= 1'b0;
        else if (axi_wr_en)
            s_axi_bvalid <= 1'b1;
        else if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;
    end

    // ================================================================
    //  AXI4-Lite Slave - Read Channel
    // ================================================================
    assign axi_rd_en     = s_axi_arvalid && !s_axi_rvalid;
    assign s_axi_arready = axi_rd_en;
    assign s_axi_rresp   = 2'b00;                    // OKAY

    always_comb begin
        case (s_axi_araddr[4:2])
            3'd0:    rd_mux = reg_nby;
            3'd1:    rd_mux = reg_adr;
            3'd2:    rd_mux = reg_rdr;
            3'd3:    rd_mux = reg_tdr;
            3'd4:    rd_mux = {28'd0, reg_cfg};
            default: rd_mux = 32'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
        end else if (axi_rd_en) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rdata  <= rd_mux;
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end

    // ================================================================
    //  Register File + I2C Master FSM   (single always_ff)
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_nby     <= 32'd1;
            reg_adr     <= 32'd0;
            reg_rdr     <= 32'd0;
            reg_tdr     <= 32'd0;
            reg_cfg     <= 4'd0;
            state       <= ST_IDLE;
            bit_cnt     <= 3'd0;
            byte_cnt    <= 3'd0;
            shift_out   <= 8'd0;
            shift_in    <= 8'd0;
            op_rw       <= 1'b0;
            op_nby      <= 3'd1;
            op_addr     <= 7'd0;
            op_tdr      <= 32'd0;
            rx_data     <= 32'd0;
            sda_sampled <= 1'b1;
        end else begin

            // (A) Software Register Writes via AXI4-Lite
            if (axi_wr_en) begin
                case (s_axi_awaddr[4:2])
                    3'd0: begin
                        if (s_axi_wdata == 32'd0)      reg_nby <= 32'd1;
                        else if (s_axi_wdata > 32'd4)  reg_nby <= 32'd4;
                        else                           reg_nby <= s_axi_wdata;
                    end
                    3'd1: reg_adr <= {25'd0, s_axi_wdata[6:0]};
                    3'd2: ; // read-only
                    3'd3: reg_tdr <= s_axi_wdata;
                    3'd4: begin
                        if (s_axi_wdata[0] && s_axi_wdata[2]) begin
                            reg_cfg[0] <= 1'b1;
                            reg_cfg[2] <= 1'b0;
                        end else begin
                            reg_cfg[0] <= s_axi_wdata[0];
                            reg_cfg[2] <= s_axi_wdata[2];
                        end
                        if (!s_axi_wdata[1]) reg_cfg[1] <= 1'b0; // Interrupt clearing for TX
                        if (!s_axi_wdata[3]) reg_cfg[3] <= 1'b0; // Interrupt clearing for RX
                    end
                    default: ;
                endcase
            end

            // (B) SDA Sampling
            if (sample) begin
                sda_sampled <= sda_in;
            end

            // (C) I2C Master FSM
            case (state)
                ST_IDLE: begin
                    if (reg_cfg[0]) begin
                        op_rw     <= 1'b0;
                        op_addr   <= reg_adr[6:0];
                        op_nby    <= (reg_nby[2:0] == 3'd0) ? 3'd1 : (reg_nby > 32'd4) ? 3'd4 : reg_nby[2:0];
                        op_tdr    <= reg_tdr;
                        byte_cnt  <= 3'd0;
                        state     <= ST_START;
                    end else if (reg_cfg[2]) begin
                        op_rw     <= 1'b1;
                        op_addr   <= reg_adr[6:0];
                        op_nby    <= (reg_nby[2:0] == 3'd0) ? 3'd1 : (reg_nby > 32'd4) ? 3'd4 : reg_nby[2:0];
                        byte_cnt  <= 3'd0;
                        rx_data   <= 32'd0;
                        state     <= ST_START;
                    end
                end

                ST_START: begin
                    if (bit_done) begin
                        shift_out <= {op_addr, op_rw};
                        bit_cnt   <= 3'd0;
                        state     <= ST_ADDR_BIT;
                    end
                end

                ST_ADDR_BIT: begin
                    if (bit_done) begin
                        if (bit_cnt == 3'd7) begin
                            state <= ST_ADDR_ACK;
                        end else begin
                            shift_out <= {shift_out[6:0], 1'b0};
                            bit_cnt   <= bit_cnt + 3'd1;
                        end
                    end
                end

                ST_ADDR_ACK: begin
                    if (bit_done) begin
                        if (sda_sampled) begin
                            state <= ST_STOP; // NACK
                        end else begin
                            bit_cnt <= 3'd0;
                            if (!op_rw) begin
                                case (byte_cnt[1:0])
                                    2'd0: shift_out <= op_tdr[7:0];
                                    2'd1: shift_out <= op_tdr[15:8];
                                    2'd2: shift_out <= op_tdr[23:16];
                                    2'd3: shift_out <= op_tdr[31:24];
                                endcase
                                state <= ST_WR_BIT;
                            end else begin
                                shift_in <= 8'd0;
                                state    <= ST_RD_BIT;
                            end
                        end
                    end
                end

                ST_WR_BIT: begin
                    if (bit_done) begin
                        if (bit_cnt == 3'd7) begin
                            state <= ST_WR_ACK;
                        end else begin
                            shift_out <= {shift_out[6:0], 1'b0};
                            bit_cnt   <= bit_cnt + 3'd1;
                        end
                    end
                end

                ST_WR_ACK: begin
                    if (bit_done) begin
                        if (sda_sampled) begin
                            state <= ST_STOP;
                        end else if ((byte_cnt + 3'd1) < op_nby) begin
                            byte_cnt <= byte_cnt + 3'd1;
                            bit_cnt  <= 3'd0;
                            case (byte_cnt[1:0] + 2'd1)
                                2'd1: shift_out <= op_tdr[15:8];
                                2'd2: shift_out <= op_tdr[23:16];
                                2'd3: shift_out <= op_tdr[31:24];
                                default: shift_out <= 8'd0;
                            endcase
                            state <= ST_WR_BIT;
                        end else begin
                            state <= ST_STOP;
                        end
                    end
                end

                ST_RD_BIT: begin
                    if (sample) begin
                        shift_in <= {shift_in[6:0], sda_in};
                    end
                    if (bit_done) begin
                        if (bit_cnt == 3'd7) begin
                            case (byte_cnt[1:0])
                                2'd0: rx_data[7:0]   <= shift_in;
                                2'd1: rx_data[15:8]  <= shift_in;
                                2'd2: rx_data[23:16] <= shift_in;
                                2'd3: rx_data[31:24] <= shift_in;
                            endcase
                            state <= ST_RD_ACK;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end
                end

                ST_RD_ACK: begin
                    if (bit_done) begin
                        if ((byte_cnt + 3'd1) < op_nby) begin
                            byte_cnt <= byte_cnt + 3'd1;
                            shift_in <= 8'd0;
                            bit_cnt  <= 3'd0;
                            state    <= ST_RD_BIT;
                        end else begin
                            state <= ST_STOP;
                        end
                    end
                end

                ST_STOP: begin
                    if (bit_done) begin
                        if (!op_rw) begin
                            reg_cfg[0] <= 1'b0;       // Clear TX enable
                            reg_cfg[1] <= 1'b1;       // Set TX done (TETİKLER i2c_irq)
                        end else begin
                            reg_cfg[2] <= 1'b0;       // Clear RX enable
                            reg_cfg[3] <= 1'b1;       // Set RX done (TETİKLER i2c_irq)
                            reg_rdr    <= rx_data;
                        end
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule