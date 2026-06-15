#!/usr/bin/env bash
# ============================================================
# sim_npu_subsystem.sh — NPU ALT-SİSTEM sistem-seviye doğrulama
#   npu_subsystem = npu_top + ai_mem (gerçek AXI4 bellek modülü).
#   CPU davranışı: CSR yaz → START → IRQ → RESULT oku → golden self-check.
#   Adımlar:
#     1) Golden referans vektörleri (npu_golden.py --emit)
#     2) Alt-sistem self-checking testi (NPU master GERÇEK ai_mem'i okur)
#
# Build çıktısı /tmp altına (boşluklu /mnt/c yolu Verilator'ı bozar).
# Kullanım: bash scripts/sim_npu_subsystem.sh
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OBJ="${NPU_OBJ:-/tmp/tunga_npu}"
VFLAGS="--binary --timing --assert -Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-TIMESCALEMOD -Wno-BLKSEQ -Wno-SYNCASYNCNET"
RTL="rtl/npu/npu_pkg.sv \
  rtl/npu/local_buffer.sv rtl/npu/input_buffer.sv rtl/npu/fc_weight_buffer.sv \
  rtl/npu/softmax_argmax.sv rtl/npu/fully_connected.sv rtl/npu/depthwise_conv2d.sv \
  rtl/npu/axi_controller.sv rtl/npu/fsm_controller.sv rtl/npu/npu_top.sv \
  rtl/memory/ai_mem.sv rtl/top/npu_subsystem.sv"

echo "==[1/2] Golden referans vektorleri =="
python3 draft/ali_salih/npu_golden.py --emit

echo "==[2/2] Alt-sistem self-checking testi =="
rm -rf "$OBJ/subsys"; mkdir -p "$OBJ/subsys"
# shellcheck disable=SC2086
verilator $VFLAGS --top-module npu_subsystem_tb -Mdir "$OBJ/subsys" \
    $RTL tb/system/npu_subsystem_tb.sv -o subsys_sim
"$OBJ/subsys/subsys_sim"

echo "== NPU alt-sistem dogrulama akisi tamam =="
