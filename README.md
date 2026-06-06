# TUNGA SoC

TEKNOFEST 2026 Çip Tasarım Yarışması kapsamında geliştirilen açık kaynak RISC-V tabanlı SoC.

## Mimariye Genel Bakış

```
CV32E40P (RV32IMFC)
    │
    ├─ OBI-AXI Bridge ×2 (buyruk / veri)
    │
    └─ AXI Interconnect (5 master, 11 slave)
         ├─ BootROM      (1 KB)
         ├─ IMEM         (8 KB)
         ├─ DMEM         (8 KB)
         ├─ AI_MEM       (30 KB — NPU veri yolu)
         ├─ GPIO, Timer, UART0, UART1, QSPI, I2C
         └─ NPU CSR
```

**NPU:** TFLite Micro "Tiny Conv" INT8 — mikrofon sesini 4 sınıfa ayırır (yes / no / up / silence).  
Veri yolu: `UART1 → AI_MEM (AXI-Stream) → NPU (DepthwiseConv2D + FC + Argmax)`

## Dizin Yapısı

```
rtl/          RTL kaynak dosyaları (SystemVerilog)
  core/       cv32e40p alt modülü
  npu/        NPU bloğu
  peripherals/  Çevre birim IP'leri
tb/           Testbench'ler
scripts/      Makefile ve derleme betikleri
docs/         Doğrulama planı ve teknik dökümanlar
sw/           Gömülü yazılım (başlangıç kodu, BSP)
vivado/       FPGA sentez projesi
openlane/     ASIC akışı
draft/        Geliştirme taslakları
weights/      .mem formatında model ağırlıkları (üretilen)
```

## Simülasyon

Gereksinim: **Verilator ≥ 5.036**

```bash
# NPU birim testleri
make -C scripts sim-npu

# Lint
make -C scripts lint-npu
```

## Hedef Teknoloji

- **FPGA Prototipi:** Xilinx Artix-7 (XC7A100T)  
- **ASIC Hedefi:** 130 nm (OpenLane / SkyWater 130)

## Durum

| Bileşen | Durum |
|---------|-------|
| NPU RTL | Geliştirme aşamasında |
| Çevre birimler (GPIO/Timer/UART/QSPI/I2C) | Taslak |
| OBI-AXI Bridge | Taslak |
| AXI Interconnect | Taslak |
| SoC üst modülü | Entegrasyon bekliyor |
| Boot ROM | Taslak |

## Lisans

MIT
