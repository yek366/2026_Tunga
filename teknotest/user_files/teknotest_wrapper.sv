// teknotest_wrapper — TUNGA SoC (Yuşa'nın soc_top entegrasyonu)
// Sadece 4 DDK pini dışarı açılır; SoC içeride bağlanır.
`timescale 1ns / 1ps
module teknotest_wrapper (
    input  logic clk_i,
    input  logic resetn_i,
    input  logic uart_rx_i,
    output logic uart_tx_o
);

    soc_top u_tunga_soc (
        .clk_i      (clk_i),
        .rst_ni     (resetn_i),
        .uart0_rx_i (uart_rx_i),
        .uart0_tx_o (uart_tx_o)
    );

endmodule
