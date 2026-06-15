# TUNGA SoC

TEKNOFEST 2026 Çip Tasarım Yarışması kapsamında geliştirilen açık kaynak RISC-V tabanlı SoC.

## Mimariye Genel Bakış

```
CV32E40P (RV32IMFC)
    │
    ├─ OBI → AXI köprü (buyruk / veri)
    │
    └─ AXI-Lite Interconnect
         ├─ Boot ROM
         ├─ DATA SRAM
         ├─ GPIO, Timer, UART0, UART1, QSPI, I2C
         ├─ Interrupt Controller
         └─ NPU (CSR slave + AI_MEM master)
```

**NPU:** TFLite Micro "Tiny Conv" INT8 — ses öznitelik vektörünü 4 sınıfa ayırır
(silence / unknown / yes / no). Veri yolu: `AI_MEM → NPU (DepthwiseConv2D + FullyConnected + Argmax) → IRQ`.
Quant aritmetiği gemmlowp referansıyla bit-exact.

## Dizin Yapısı

```
rtl/          RTL kaynak dosyaları (SystemVerilog)
  core/       cv32e40p alt modülü (submodule)
  npu/        NPU bloğu
  bus/        OBI→AXI köprü + AXI-Lite interconnect
  memory/     SRAM, AI_MEM
  peripherals/  Çevre birim IP'leri (UART/GPIO/Timer/I2C/QSPI)
  boot/       Boot ROM
  top/        SoC üst modülü (soc_top)
tb/           Testbench'ler (birim + sistem, self-checking)
teknotest/    DDK eleme harness'i (gate)
scripts/      Makefile + simülasyon betikleri
docs/         Doğrulama planı ve teknik dökümanlar
sw/           Gömülü yazılım
vivado/       FPGA constraint + handoff
openlane/     ASIC akışı
draft/        Geliştirme taslakları + model üretim araçları
weights/      .mem formatında model ağırlıkları (üretilen)
```

## Simülasyon

Gereksinim: **Verilator ≥ 5.036**

```bash
# NPU tam doğrulama (golden + requant + self-checking TB)
bash scripts/sim_npu.sh

# NPU alt-sistem (npu_top + ai_mem, sistem bağlamı)
bash scripts/sim_npu_subsystem.sh

# Referans ses (yes/no/silence — TFLite ile birebir)
bash scripts/sim_npu_subsystem_audio.sh

# Lint
make -C scripts lint-npu
```

## Hedef Teknoloji

- **FPGA Prototipi:** Xilinx Artix-7 (Nexys 4)
- **ASIC Hedefi:** OpenLane akışı

## Durum

| Bileşen | Durum |
|---------|-------|
| DDK teknotest gate (eleme) | ✅ Geçti |
| NPU RTL | ✅ Doğrulandı (TFLite ile bit-exact, self-checking TB) |
| CV32E40P çekirdek | ✅ Entegre |
| OBI→AXI köprü + Interconnect | ✅ Çalışıyor |
| Çevre birimler (UART/GPIO/Timer/QSPI/I2C) | 🟡 RTL hazır |
| Boot ROM + SRAM | ✅ Hazır |
| SoC üst modülü (soc_top) | 🟡 Entegre (tam-sistem doğrulama sürüyor) |
| FPGA bitstream / sentez raporu | 🔴 Devam ediyor |
| ASIC (OpenLane GDSII) | 🔴 Devam ediyor |

## Lisans

MIT
