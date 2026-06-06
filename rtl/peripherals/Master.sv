// Master.v dosyasının tamamını bununla değiştir
`timescale 1ns / 1ps

module Master (
    input  wire clk, rst_n, start,
    input  wire [1:0] mode,
    input  wire tx_en,
    input  wire [7:0] tx_byte,
    output reg  [7:0] rx_byte,
    output reg  busy, done_tick, sclk,
    output wire [3:0] dq_o,
    input  wire [3:0] dq_i,
    output wire [3:0] dq_oe
);

    localparam IDLE = 0, LATCH_DATA = 1, SCLK_LOW = 2, SCLK_HIGH = 3, DONE = 4;
    reg [2:0] state = 0;
    reg [2:0] pulse_cnt = 0; 
    reg [7:0] tx_shift = 0;
    reg [3:0] dq_out_reg = 0;
    reg [3:0] dq_oe_reg = 0; 

    assign dq_o  = dq_out_reg;
    assign dq_oe = dq_oe_reg; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; busy <= 0; done_tick <= 0; sclk <= 0;
            dq_out_reg <= 0; dq_oe_reg <= 0; rx_byte <= 0;
        end else begin
            done_tick <= 0;
            case (state)
                IDLE: begin
                    sclk <= 0; dq_oe_reg <= 0; busy <= 0;
                    if (start) begin busy <= 1; state <= LATCH_DATA; end
                end
                LATCH_DATA: begin
                    tx_shift <= tx_byte; // Veriyi buradan alıyoruz
                    if (mode == 2'b10) pulse_cnt <= 1; 
                    else if (mode == 2'b01) pulse_cnt <= 3; 
                    else pulse_cnt <= 7; 
                    state <= SCLK_LOW;
                end
                SCLK_LOW: begin
                    sclk <= 0;
                    if (tx_en) begin
                        if (mode == 2'b10) dq_out_reg <= tx_shift[7:4];
                        else if (mode == 2'b01) dq_out_reg[1:0] <= tx_shift[7:6];
                        else dq_out_reg[0] <= tx_shift[7];
                        
                        if (mode == 2'b10) dq_oe_reg <= 4'b1111;
                        else if (mode == 2'b01) dq_oe_reg <= 4'b0011;
                        else dq_oe_reg <= 4'b0001;
                    end
                    state <= SCLK_HIGH;
                end
                SCLK_HIGH: begin
                    sclk <= 1;
                    if (mode == 2'b10) begin
                        rx_byte <= {rx_byte[3:0], dq_i[3:0]};
                        tx_shift <= {tx_shift[3:0], 4'b0000};
                    end else if (mode == 2'b01) begin
                        rx_byte <= {rx_byte[5:0], dq_i[1:0]};
                        tx_shift <= {tx_shift[5:0], 2'b00};
                    end else begin
                        rx_byte <= {rx_byte[6:0], dq_i[1]}; 
                        tx_shift <= {tx_shift[6:0], 1'b0};
                    end
                    if (pulse_cnt == 0) state <= DONE;
                    else begin pulse_cnt <= pulse_cnt - 1; state <= SCLK_LOW; end
                end
                DONE: begin
                    sclk <= 0; dq_oe_reg <= 0; dq_out_reg <= 0;
                    done_tick <= 1; busy <= 0; state <= IDLE;
                end
            endcase
        end
    end
endmodule