uar// =============================================================================


module uart_rx
    import uart_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

 
    input  logic [31:0] i_cpb,         

    input  logic        i_rx,         

    
    output logic [7:0]  o_data,        
    output logic        o_rx_done,     
    output logic        o_rx_busy,    
    output logic        o_frame_err    
);

  
    typedef enum logic [1:0] {
        ST_IDLE  = 2'd0,
        ST_START = 2'd1,
        ST_DATA  = 2'd2,
        ST_STOP  = 2'd3
    } rx_fsm_t;

    rx_fsm_t state_r;


    logic [31:0] clk_cnt_r;
    logic [2:0]  bit_cnt_r;
    logic [7:0]  shift_r;
    logic [31:0] half_cpb;
    logic [31:0] sample_point;

    assign half_cpb     = (i_cpb >> 1);
    assign sample_point = i_cpb - 1; 


    logic rx_sync1_r, rx_sync2_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1_r <= 1'b1;
            rx_sync2_r <= 1'b1;
        end else begin
            rx_sync1_r <= i_rx;
            rx_sync2_r <= rx_sync1_r;
        end
    end

  
    wire rx_s = rx_sync2_r;

 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r    <= ST_IDLE;
            clk_cnt_r  <= '0;
            bit_cnt_r  <= '0;
            shift_r    <= '0;
            o_data     <= '0;
            o_rx_done  <= 1'b0;
            o_rx_busy  <= 1'b0;
            o_frame_err<= 1'b0;
        end else begin
            o_rx_done   <= 1'b0;
            o_frame_err <= 1'b0;

            unique case (state_r)
               
                ST_IDLE: begin
                    o_rx_busy <= 1'b0;
                    clk_cnt_r <= '0;
                    bit_cnt_r <= '0;

                    if (!rx_s) begin
                        o_rx_busy <= 1'b1;
                        state_r   <= ST_START;
                    end
                end

             
                ST_START: begin
                    if (clk_cnt_r >= half_cpb - 1) begin
                        clk_cnt_r <= '0;
                        if (!rx_s) begin
                            
                            state_r <= ST_DATA;
                        end else begin
                           
                            state_r   <= ST_IDLE;
                            o_rx_busy <= 1'b0;
                        end
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                ST_DATA: begin
                    if (clk_cnt_r >= sample_point) begin
                        clk_cnt_r <= '0;
                     
                        shift_r   <= {rx_s, shift_r[7:1]};

                        if (bit_cnt_r == 3'd7) begin
                            bit_cnt_r <= '0;
                            state_r   <= ST_STOP;
                        end else begin
                            bit_cnt_r <= bit_cnt_r + 1;
                        end
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

            
                ST_STOP: begin
                    if (clk_cnt_r >= sample_point) begin
                        clk_cnt_r <= '0;
                        if (rx_s) begin                  
                            o_data    <= shift_r;
                            o_rx_done <= 1'b1;
                        end else begin                    
                            o_frame_err <= 1'b1;
                        end
                        state_r <= ST_IDLE;
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
