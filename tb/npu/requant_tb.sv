// ============================================================
// Module : requant_tb
// Project: TUNGA SoC — TEKNOFEST 2026
// Author : Ali Salih Yıldırım
// Desc   : quant_requant (gemmlowp INT8 requant) birim testbench'i.
//          weights/requant_vectors.txt golden vektörlerini okur,
//          her satırı DUT'a uygular, beklenen INT8 çıkışla karşılaştırır.
//          Tek bir uyuşmazlık → FAIL. Bit-exact golden eşleşmesi şart.
// Üretim : python3 draft/ali_salih/npu_golden.py --requant-vectors
// ============================================================

`timescale 1ns/1ps

module requant_tb;

    logic signed [31:0] acc, mult, shift, out_zp, act_min, act_max;
    logic signed [7:0]  q_out;
    logic signed [31:0] expected;

    quant_requant dut (
        .acc(acc), .mult(mult), .shift(shift),
        .out_zp(out_zp), .act_min(act_min), .act_max(act_max),
        .q_out(q_out)
    );

    integer fd, n, i, rc;
    integer fail = 0;
    integer e_i;

    initial begin
        fd = $fopen("weights/requant_vectors.txt", "r");
        if (fd == 0) begin
            $fatal(1, "[FATAL] weights/requant_vectors.txt acilamadi (repo kokunden calistir)");
        end
        rc = $fscanf(fd, "%d\n", n);
        if (rc != 1) $fatal(1, "[FATAL] vektor sayisi okunamadi");
        $display("[INFO] %0d requant vektoru okunuyor...", n);

        for (i = 0; i < n; i++) begin
            rc = $fscanf(fd, "%d %d %d %d %d %d %d\n",
                         acc, mult, shift, out_zp, act_min, act_max, e_i);
            if (rc != 7) $fatal(1, "[FATAL] satir %0d parse hatasi (rc=%0d)", i, rc);
            expected = e_i;
            #1; // kombinasyonel yerleşim
            if (q_out !== expected[7:0]) begin
                fail++;
                if (fail <= 20)
                    $display("[FAIL] satir %0d: acc=%0d mult=%0d shift=%0d zp=%0d [%0d,%0d] got=%0d exp=%0d",
                             i, acc, mult, shift, out_zp, act_min, act_max, q_out, expected[7:0]);
            end
        end
        $fclose(fd);

        $display("=========================================");
        if (fail == 0)
            $display("[REQUANT-TB] >>> TUM %0d VEKTOR GECTI (bit-exact golden) <<<", n);
        else
            $display("[REQUANT-TB] >>> %0d / %0d VEKTOR BASARISIZ <<<", fail, n);
        $display("=========================================");
        if (fail != 0) $fatal(1, "REQUANT TB FAIL");
        $finish;
    end

endmodule
