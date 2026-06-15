#!/usr/bin/env bash
# ai_mem birim self-checking testi (range-check + yazma + lane hizalama)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OBJ="${NPU_OBJ:-/tmp/tunga_npu}"
VF="--binary --timing --assert -Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-TIMESCALEMOD -Wno-BLKSEQ -Wno-SYNCASYNCNET"
rm -rf "$OBJ/aimem"; mkdir -p "$OBJ/aimem"
# shellcheck disable=SC2086
verilator $VF --top-module ai_mem_tb -Mdir "$OBJ/aimem" \
    rtl/memory/ai_mem.sv tb/memory/ai_mem_tb.sv -o aimem_sim
"$OBJ/aimem/aimem_sim"
