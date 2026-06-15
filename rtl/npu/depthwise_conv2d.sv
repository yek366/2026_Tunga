`timescale 1ns/1ps

module depthwise_conv2d
    import npu_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    input  logic start,
    output logic done,

    // ---- Quant parametreleri (per-channel) ----
    input  logic signed [31:0] input_zp,
    input  logic signed [31:0] out_zp,
    input  logic signed [31:0] act_min,
    input  logic signed [31:0] act_max,
    input  logic signed [31:0] dw_mult  [0:NUM_FILTERS-1],
    input  logic signed [31:0] dw_shift [0:NUM_FILTERS-1],
    input  logic signed [31:0] dw_bias  [0:NUM_FILTERS-1],

    // ---- Giriş pikseli okuma (input_buffer, KAYITLI: 1 çevrim gecikme) ----
    output logic [$clog2(INPUT_SIZE)-1:0]      in_rd_addr,
    input  logic signed [7:0]                  in_rd_data,

    // ---- DW ağırlık okuma (input_buffer, KAYITLI) ----
    output logic [$clog2(DW_WEIGHT_BYTES)-1:0] dw_w_rd_addr,
    input  logic signed [7:0]                  dw_w_rd_data,

    // ---- Çıkış yazma (local_buffer) ----
    output logic                   out_wr_en,
    output logic [$clog2(FC_FLAT)-1:0] out_wr_addr,
    output logic signed [7:0]      out_wr_data
);

    localparam int WIN = KER_H * KER_W;   // 80 (pencere eleman sayısı)

    typedef enum logic [1:0] {DW_IDLE, DW_RUN, DW_WRITE, DW_DONE} dw_state_t;
    dw_state_t state;

    // Çıkış elemanı sayaçları
    logic [$clog2(OUT_H)-1:0]       oh;
    logic [$clog2(OUT_W)-1:0]       ow;
    logic [$clog2(NUM_FILTERS)-1:0] c;
    // Pencere MAC pozisyonu (0..WIN): adres fazı önde
    logic [$clog2(WIN+1)-1:0]       wcnt;

    logic signed [31:0] acc;
    logic               vld_q;     // bir önceki tap'in padding-geçerliliği (veriyle hizalı)

    // ---- Adres üretimi (wcnt'ten; MAC'ten 1 çevrim önde) ----
    logic [$clog2(KER_H)-1:0] kh;
    logic [$clog2(KER_W)-1:0] kw;
    assign kh = wcnt[$clog2(KER_W) +: $clog2(KER_H)];  // wcnt / KER_W
    assign kw = wcnt[0 +: $clog2(KER_W)];              // wcnt % KER_W

    logic addr_ph;                 // geçerli adres fazı (son tap'te dolum biter)
    assign addr_ph = (wcnt < WIN[$clog2(WIN+1)-1:0]);

    int   ih_i, iw_i;
    logic in_valid;
    always_comb begin
        ih_i     = int'(oh) * STRIDE_H + int'(kh) - PAD_TOP;
        iw_i     = int'(ow) * STRIDE_W + int'(kw) - PAD_LEFT;
        in_valid = addr_ph && (ih_i >= 0) && (ih_i < IN_H) && (iw_i >= 0) && (iw_i < IN_W);
    end

    assign in_rd_addr   = ($clog2(INPUT_SIZE))'(in_valid ? (ih_i * IN_W + iw_i) : 0);
    assign dw_w_rd_addr = ($clog2(DW_WEIGHT_BYTES))'(addr_ph ? (int'(c) * WIN + int'(wcnt)) : 0);

    // ---- MAC çarpımı (KAYITLI tampon çıkışları + hizalı vld_q) ----
    int pix, prod;
    always_comb begin
        pix  = vld_q ? (int'(in_rd_data) - input_zp) : 0;
        prod = int'(dw_w_rd_data) * pix;
    end

    // ---- Çıkış (DW_WRITE'ta kombinasyonel) ----
    logic signed [31:0] acc_biased;
    assign acc_biased = acc + dw_bias[c];
    assign out_wr_en   = (state == DW_WRITE);
    assign out_wr_addr = ($clog2(FC_FLAT))'(
                             int'(oh) * (OUT_W * OUT_C) + int'(ow) * OUT_C + int'(c));
    assign out_wr_data = requant_relu(acc_biased, dw_mult[c], dw_shift[c],
                                      out_zp, act_min, act_max);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= DW_IDLE;
            done  <= 1'b0;
            acc   <= '0;
            vld_q <= 1'b0;
            oh <= '0; ow <= '0; c <= '0; wcnt <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                DW_IDLE: begin
                    if (start) begin
                        oh <= '0; ow <= '0; c <= '0; wcnt <= '0;
                        acc <= '0; vld_q <= 1'b0;
                        state <= DW_RUN;
                    end
                end

                DW_RUN: begin
                    vld_q <= in_valid;                 // sonraki çevrim için hizala
                    if (wcnt != '0) acc <= acc + prod; // bir önceki tap'in çarpımı
                    if (wcnt == WIN[$clog2(WIN+1)-1:0]) begin
                        wcnt  <= '0;
                        vld_q <= 1'b0;
                        state <= DW_WRITE;             // pencere tamam (80 birikim)
                    end else begin
                        wcnt <= wcnt + 1'b1;
                    end
                end

                DW_WRITE: begin
                    // out_* kombinasyonel; local_buffer bu kenarda yakalar
                    acc <= '0;
                    if (c == 3'(OUT_C-1)) begin
                        c <= '0;
                        if (ow == 5'(OUT_W-1)) begin
                            ow <= '0;
                            if (oh == 5'(OUT_H-1)) begin
                                state <= DW_DONE;
                            end else begin
                                oh <= oh + 1'b1;
                                state <= DW_RUN;
                            end
                        end else begin
                            ow <= ow + 1'b1;
                            state <= DW_RUN;
                        end
                    end else begin
                        c <= c + 1'b1;
                        state <= DW_RUN;
                    end
                end

                DW_DONE: begin
                    done  <= 1'b1;
                    state <= DW_IDLE;
                end
                default: state <= DW_IDLE;
            endcase
        end
    end

endmodule
