// teknotest_wrapper — TUNGA SoC gate vehicle
// Instantiates the minimal boot SoC. Only the 4 DDK pins are exposed.
module teknotest_wrapper(
    input  clk_i,      // 50 MHz clock
    input  resetn_i,   // active-low reset
    input  uart_rx_i,  // UART RX (tb->dut)
    output uart_tx_o   // UART TX (dut->tb)
);

    tunga_soc_min u_soc (
        .clk_i      (clk_i),
        .rst_ni     (resetn_i),
        .uart0_tx_o (uart_tx_o),
        .uart0_rx_i (uart_rx_i)
    );

endmodule
