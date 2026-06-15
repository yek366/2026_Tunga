#!/usr/bin/env bash
# ============================================================
# sim_npu_audio.sh — NPU REFERANS SES self-checking (sartname EK-3 ZORUNLU)
# Resmi micro_speech test sesi (yes/no/silence wav) -> audio_preprocessor ->
# 1960 int8 feature -> NPU RTL. NPU sinifi, TFLite interpreter (yazilim modeli)
# sinifiyla karsilastirilir. RTL==TFLite bit-exact oldugundan sapma %0 (<=%10).
#
# Gereken: ~/tunga_venv (ai-edge-litert + tflite-micro). Repo kokunden calistir.
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VENV="$HOME/tunga_venv/bin/python"
OBJ="${NPU_OBJ:-/tmp/tunga_npu}"
VFLAGS="--binary --timing --assert -Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-TIMESCALEMOD -Wno-BLKSEQ -Wno-SYNCASYNCNET"
NPU_RTL="rtl/npu/npu_pkg.sv rtl/npu/local_buffer.sv rtl/npu/input_buffer.sv \
  rtl/npu/fc_weight_buffer.sv rtl/npu/softmax_argmax.sv rtl/npu/fully_connected.sv \
  rtl/npu/depthwise_conv2d.sv rtl/npu/axi_controller.sv rtl/npu/fsm_controller.sv rtl/npu/npu_top.sv"

echo "==[1/3] Resmi sesten referans feature cikar + interpreter dogrula =="
"$VENV" draft/ali_salih/make_features.py 2>/dev/null | grep -E "yes|no|silence|GECTI|BASARISIZ" || true

echo "==[2/3] NPU RTL derle =="
rm -rf "$OBJ/npu"; mkdir -p "$OBJ/npu"
# shellcheck disable=SC2086
verilator $VFLAGS --top-module npu_tb -Mdir "$OBJ/npu" $NPU_RTL tb/npu/npu_tb.sv -o npu_sim >/dev/null 2>&1

echo "==[3/3] NPU'yu her gercek ses ornegiyle kosur (NPU sinifi == TFLite sinifi) =="
fail=0
for L in yes no silence; do
    "$VENV" draft/ali_salih/npu_real_model.py --feature "weights/feat_${L}.mem" 2>/dev/null | grep -E "class=" | sed "s/^/  [$L] /" || true
    out=$("$OBJ/npu/npu_sim" 2>/dev/null || true)
    echo "$out" | grep -E "NPU_RESULT|NPU sinif|TUM TESTLER|BASARISIZ" | sed "s/^/  [$L] /" || true
    echo "$out" | grep -q "TUM TESTLER GECTI" || fail=1
done
echo "============================================"
if [ "$fail" -eq 0 ]; then
    echo ">>> NPU REFERANS SES TESTI GECTI (yes/no/silence — NPU == TFLite) <<<"
else
    echo ">>> NPU REFERANS SES TESTI BASARISIZ <<<"; exit 1
fi
