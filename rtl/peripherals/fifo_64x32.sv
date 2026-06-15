// =============================================================================
// fifo_64x32.sv
// Wrapper for sync_fifo to match the instantiated port names in QSPI module.
// =============================================================================

module fifo_64x32 (
    input  wire clk,
    input  wire srst, // Active high reset
    input  wire [31:0] din,
    input  wire wr_en,
    input  wire rd_en,
    output wire [31:0] dout,
    output wire full,
    output wire empty
);

    sync_fifo #(
        .DATA_W(32),
        .DEPTH(64)
    ) u_fifo (
        .clk(clk),
        .rst_n(~srst),
        .i_wr_en(wr_en),
        .i_wr_data(din),
        .i_rd_en(rd_en),
        .o_rd_data(dout),
        .o_full(full),
        .o_empty(empty),
        .o_level()
    );

endmodule
