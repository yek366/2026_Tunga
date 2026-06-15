#!/usr/bin/env bash
# Ajan-2 banner temizligi sonrasi takim RTL'i syntax/lint dogrulama (comment-only degisiklik bozmadi mi)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
L="verilator --lint-only -sv -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-TIMESCALEMOD"
ok=0; bad=0
chk() { # $1=name, rest=files (top module = last basename without ext heuristics not needed for lint-only)
  local name="$1"; shift
  if $L "$@" 2>/tmp/lint_$name.log; then echo "[LINT OK] $name"; ok=$((ok+1));
  else echo "[LINT FAIL] $name"; grep -iE 'error|syntax' /tmp/lint_$name.log | head -5; bad=$((bad+1)); fi
}
chk bus_pkgs    rtl/bus/axi_pkg.sv rtl/bus/obi_pkg.sv rtl/bus/memory_map_pkg.sv rtl/bus/cf_math_pkg.sv
chk memory      rtl/memory/tunga_sram.sv
chk sram_module rtl/memory/sram_module.sv
chk boot_rom    rtl/boot/boot_rom.sv
chk uart_stack  rtl/peripherals/uart_pkg.sv rtl/peripherals/uart_rx.sv rtl/peripherals/uart_tx.sv rtl/peripherals/sync_fifo.sv rtl/peripherals/uart_stream_peripheral.sv
chk uart_periph rtl/peripherals/uart_pkg.sv rtl/peripherals/uart_rx.sv rtl/peripherals/uart_tx.sv rtl/peripherals/uart_peripheral.sv
chk gpio        rtl/peripherals/gpio_peripheral.sv
chk i2c         rtl/peripherals/i2c_peripheral.sv
chk timer       rtl/peripherals/timer_peripheral.sv
echo "================ LINT OK=$ok FAIL=$bad ================"
