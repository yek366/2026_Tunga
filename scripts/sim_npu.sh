#!/usr/bin/env bash
# ============================================================
# sim_npu.sh — TUNGA NPU tam doğrulama akışı (WSL/Linux + Verilator 5.x)
# Adımlar:
#   1) Golden referans vektörlerini üret (npu_golden.py)
#   2) Requant birim testi (gemmlowp INT8, bit-exact golden)
#   3) NPU self-checking testi (golden sınıf + DW çıkışı bit-exact)
#
# NOT: Verilator build çıktısı /tmp altına yazılır; repo /mnt/c üzerinde
#      boşluklu yolda ise Verilator dosya yazımı bozuluyor. NPU_OBJ ile değişir.
#
# Kullanım:  bash scripts/sim_npu.sh
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OBJ="${NPU_OBJ:-/tmp/tunga_npu}"
PKG="rtl/npu/npu_pkg.sv"
NPU_RTL="$PKG \
  rtl/npu/local_buffer.sv rtl/npu/input_buffer.sv rtl/npu/fc_weight_buffer.sv \
  rtl/npu/softmax_argmax.sv rtl/npu/fully_connected.sv rtl/npu/depthwise_conv2d.sv \
  rtl/npu/axi_controller.sv rtl/npu/fsm_controller.sv rtl/npu/npu_top.sv"
VFLAGS="--binary --timing --assert -Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-TIMESCALEMOD -Wno-BLKSEQ -Wno-SYNCASYNCNET"

echo "==[1/3] Golden referans vektörleri =="
python3 draft/ali_salih/npu_golden.py --emit
python3 draft/ali_salih/npu_golden.py --requant-vectors

echo "==[2/3] Requant birim testi =="
rm -rf "$OBJ/requant"; mkdir -p "$OBJ/requant"
# shellcheck disable=SC2086
verilator $VFLAGS --top-module requant_tb -Mdir "$OBJ/requant" \
    $PKG rtl/npu/quant_requant.sv tb/npu/requant_tb.sv -o requant_sim
"$OBJ/requant/requant_sim"

echo "==[3/3] NPU self-checking testi =="
rm -rf "$OBJ/npu"; mkdir -p "$OBJ/npu"
# shellcheck disable=SC2086
verilator $VFLAGS --top-module npu_tb -Mdir "$OBJ/npu" \
    $NPU_RTL tb/npu/npu_tb.sv -o npu_sim
"$OBJ/npu/npu_sim"

echo "== NPU doğrulama akışı tamam =="
