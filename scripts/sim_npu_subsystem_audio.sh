#!/usr/bin/env bash
# ============================================================
# sim_npu_subsystem_audio.sh — NPU ALT-SİSTEM + GERÇEK SES (şartname EK-3)
#   npu_subsystem (npu_top + gerçek ai_mem) GERÇEK micro_speech sesiyle:
#   yes/no/silence wav -> audio_preprocessor -> 1960 int8 -> AI_MEM -> NPU.
#   NPU sınıfı, TFLite interpreter sınıfıyla karşılaştırılır (sistem bağlamı,
#   gerçek AXI4 master↔ai_mem). RTL==interpreter bit-exact → sapma %0 (<=%10).
#
#   Gereken: ~/tunga_venv (ai-edge-litert + tflite-micro). Repo kökünden.
#   Kullanım: bash scripts/sim_npu_subsystem_audio.sh
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VENV="$HOME/tunga_venv/bin/python"
OBJ="${NPU_OBJ:-/tmp/tunga_npu}"
VFLAGS="--binary --timing --assert -Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-TIMESCALEMOD -Wno-BLKSEQ -Wno-SYNCASYNCNET"
RTL="rtl/npu/npu_pkg.sv \
  rtl/npu/local_buffer.sv rtl/npu/input_buffer.sv rtl/npu/fc_weight_buffer.sv \
  rtl/npu/softmax_argmax.sv rtl/npu/fully_connected.sv rtl/npu/depthwise_conv2d.sv \
  rtl/npu/axi_controller.sv rtl/npu/fsm_controller.sv rtl/npu/npu_top.sv \
  rtl/memory/ai_mem.sv rtl/top/npu_subsystem.sv"

echo "==[1/3] Resmi sesten referans feature cikar + interpreter dogrula =="
"$VENV" draft/ali_salih/make_features.py 2>/dev/null | grep -E "yes|no|silence|GECTI|BASARISIZ" || true

echo "==[2/3] Alt-sistem RTL derle (gercek ai_mem) =="
rm -rf "$OBJ/subsys"; mkdir -p "$OBJ/subsys"
# shellcheck disable=SC2086
verilator $VFLAGS --top-module npu_subsystem_tb -Mdir "$OBJ/subsys" \
    $RTL tb/system/npu_subsystem_tb.sv -o subsys_sim >/dev/null 2>&1

echo "==[3/3] Her gercek ses ornegini ALT-SISTEM'de kosur (NPU sinif == TFLite) =="
fail=0
for L in yes no silence; do
    # Gercek feature -> gercek model blob + giris + golden (interpreter-dogrulamali)
    "$VENV" draft/ali_salih/npu_real_model.py --feature "weights/feat_${L}.mem" 2>/dev/null \
        | grep -E "class=" | sed "s/^/  [$L] beklenen: /" || true
    out=$("$OBJ/subsys/subsys_sim" 2>/dev/null || true)
    echo "$out" | grep -E "NPU_RESULT|TUM TESTLER|BASARISIZ" | sed "s/^/  [$L] /" || true
    echo "$out" | grep -q "TUM TESTLER GECTI" || fail=1
done
echo "============================================"
if [ "$fail" -eq 0 ]; then
    echo ">>> NPU ALT-SISTEM GERCEK SES TESTI GECTI (yes/no/silence, sistem baglami) <<<"
else
    echo ">>> NPU ALT-SISTEM GERCEK SES TESTI BASARISIZ <<<"; exit 1
fi
