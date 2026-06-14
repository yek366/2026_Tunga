// ============================================================
// Module : fully_connected
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Date   : 2026-05-03
// Desc   : FullyConnected (Dense) katmanı.
//          Giriş: 4000 × INT8 (DepthwiseConv çıkışı, flatten sonrası)
//          Ağırlık: 4×4000 INT8 matris + 4 × INT32 bias
//          Çıkış: 4 × INT32 ham puan (logit) — softmax/argmax için
//          Her nöron için 4000 adet INT8 MAC → INT32 akümülatör
// ============================================================

`timescale 1ns/1ps

module fully_connected #(
    parameter int NUM_OUTPUTS  = 4,
    parameter int NUM_INPUTS   = 4000,
    parameter int DATA_WIDTH   = 8,
    parameter int ACCUM_WIDTH  = 32,
    parameter int BIAS_WIDTH   = 32
) (
    input  logic clk,
    input  logic rst_n,

    // Kontrol
    input  logic start,
    output logic done,

    // Giriş veri okuma (local_buffer'dan)
    output logic [$clog2(NUM_INPUTS)-1:0]            in_rd_addr,
    input  logic signed [DATA_WIDTH-1:0]             in_data,

    // Ağırlık okuma (weight_buffer'dan)
    output logic [$clog2(NUM_OUTPUTS*NUM_INPUTS)-1:0] weight_rd_addr,
    input  logic signed [DATA_WIDTH-1:0]              weight_data,

    // Bias okuma
    output logic [$clog2(NUM_OUTPUTS)-1:0]           bias_rd_addr,
    input  logic signed [BIAS_WIDTH-1:0]             bias_data,

    // Çıkış — 4 × INT32 logit
    output logic signed [ACCUM_WIDTH-1:0]            logits [0:NUM_OUTPUTS-1],
    output logic                                     logits_valid
);

    typedef enum logic [1:0] {FC_IDLE, FC_COMPUTE, FC_BIAS, FC_DONE} fc_state_t;
    fc_state_t state;

    logic [$clog2(NUM_OUTPUTS)-1:0]  neuron_idx;
    logic [$clog2(NUM_INPUTS)-1:0]   input_idx;

    // Her nöron için ayrı akümülatör
    logic signed [ACCUM_WIDTH-1:0]   acc [0:NUM_OUTPUTS-1];

    assign in_rd_addr     = input_idx;
    assign weight_rd_addr = ($clog2(NUM_OUTPUTS*NUM_INPUTS))'(neuron_idx) *
                            ($clog2(NUM_OUTPUTS*NUM_INPUTS))'(NUM_INPUTS) +
                            ($clog2(NUM_OUTPUTS*NUM_INPUTS))'(input_idx);
    assign bias_rd_addr   = neuron_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= FC_IDLE;
            done         <= 1'b0;
            logits_valid <= 1'b0;
            neuron_idx   <= '0;
            input_idx    <= '0;
            for (int i = 0; i < NUM_OUTPUTS; i++) begin
                acc[i]    <= '0;
                logits[i] <= '0;
            end
        end else begin
            done         <= 1'b0;
            logits_valid <= 1'b0;

            case (state)
                FC_IDLE: begin
                    if (start) begin
                        neuron_idx <= '0;
                        input_idx  <= '0;
                        for (int i = 0; i < NUM_OUTPUTS; i++)
                            acc[i] <= '0;
                        state <= FC_COMPUTE;
                    end
                end

                FC_COMPUTE: begin
                    // MAC: acc[neuron] += weight * input
                    acc[neuron_idx] <= acc[neuron_idx] +
                        ($signed(weight_data) * $signed(in_data));

                    if (input_idx == NUM_INPUTS[$clog2(NUM_INPUTS)-1:0] - 1) begin
                        input_idx <= '0;
                        state     <= FC_BIAS;
                    end else begin
                        input_idx <= input_idx + 1'b1;
                    end
                end

                FC_BIAS: begin
                    // Bias ekle
                    logits[neuron_idx] <= acc[neuron_idx] + bias_data;

                    if (neuron_idx == NUM_OUTPUTS[$clog2(NUM_OUTPUTS)-1:0] - 1) begin
                        neuron_idx <= '0;
                        state      <= FC_DONE;
                    end else begin
                        neuron_idx <= neuron_idx + 1'b1;
                        input_idx  <= '0;
                        state      <= FC_COMPUTE;
                    end
                end

                FC_DONE: begin
                    done         <= 1'b1;
                    logits_valid <= 1'b1;
                    state        <= FC_IDLE;
                end
            endcase
        end
    end

endmodule
