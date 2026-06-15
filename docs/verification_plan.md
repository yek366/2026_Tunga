# TUNGA SoC — Doğrulama Planı
**Proje:** TUNGA SoC — TEKNOFEST 2026 Çip Tasarım Yarışması  
**DTR Teslim:** 15 Haziran 2026  
**Şartname referansı:** Ek-3 Doğrulama Gereksinimleri

## 1. Öncelik Seviyeleri

Şartname üç öncelik seviyesi tanımlamaktadır:

| Seviye | Açıklama | Puan Etkisi |
| **ZORUNLU** | Olmadan ödül alınamaz | Minimum başarı kriteri |
| **EN İYİ ÇABA** | Tasarım & doğrulama puanını artırır | %40 havuzundan |
| **OPSİYONEL** | Tam puan için | %40 havuzundan |

---

## 2. ZORUNLU Testler

### 2.1 AXI Protokol Kontrolleri

| # | Test | Yöntem | Araç | Durum |
|---|------|--------|------|-------|
| Z-01 | AXI4-Lite CSR arayüzü protokol doğruluğu | UVM passive agent + SVA | Verilator / DSim | Bekliyor |
| Z-02 | AXI4 Master burst okuma protokolü (NPU→bellek) | UVM passive agent + SVA | Verilator / DSim | Bekliyor |
| Z-03 | AXI4-Lite slave protokolü (tüm çevre birimleri) | UVM passive agent | DSim | Bekliyor |
| Z-04 | AXI-Stream protokolü (UART1→YZ belleği) | UVM passive agent | DSim | Bekliyor |

**SVA kontrol listesi:**
- VALID bir saat sonra READY gelene kadar 1 kalmalı
- Yanıt kanalı RESP değeri 2'b00 (OKAY) olmalı
- Burst transferde WLAST doğru konumda olmalı
- RDATA, RVALID yüksekken geçerli olmalı

### 2.2 YZ Hızlandırıcı (NPU) Testleri

| # | Test | Yöntem | Araç | Durum |
|---|------|--------|------|-------|
| Z-05 | NPU smoke testi — sıfır vektörü girişi | Self-checking TB | Verilator | Bekliyor |
| Z-06 | "yes" sınıfı doğruluğu — referans ses | Self-checking TB, TFLite ref karşılaştırma | Verilator + Python | Bekliyor |
| Z-07 | "no" sınıfı doğruluğu | Self-checking TB | Verilator | Bekliyor |
| Z-08 | "silence" sınıfı doğruluğu | Self-checking TB | Verilator | Bekliyor |
| Z-09 | IRQ üretimi — DONE sonrası | Waveform + assertion | Verilator | Bekliyor |
| Z-10 | CSR R/W doğruluğu (NPU_CTRL, NPU_STATUS, RESULT) | Self-checking TB | Verilator | Kısmen hazır |

**Kabul kriteri:** Referans TFLite çıktısıyla fark ≤ %10 (şartname gereği)

### 2.3 Sistem Seviyesi Self-Checking Testler

| # | Test | Yöntem | Araç | Durum |
|---|------|--------|------|-------|
| Z-11 | Boot ROM'dan başlama ve uygulama yükleme | C test programı + waveform | Verilator + riscv-gcc | Bekliyor |
| Z-12 | UART0 veri gönderme/alma | C test programı | Verilator | Bekliyor |
| Z-13 | GPIO çıkış testi | C test programı | Verilator | Bekliyor |
| Z-14 | Timer kesme testi | C test programı | Verilator | Bekliyor |
| Z-15 | Uçtan uca: ses girişi → NPU → UART0 çıkış | C test programı | Verilator + FPGA | Bekliyor |

---

## 3. EN İYİ ÇABA Testler

### 3.1 Spike ISS Doğrulaması

| # | Test | Yöntem | Araç | Durum |
|---|------|--------|------|-------|
| E-01 | RV32I temel komutlar doğruluğu | Spike komut izi karşılaştırma | Spike ISS | Bekliyor |
| E-02 | RV32M çarpma/bölme doğruluğu | Spike karşılaştırma | Spike ISS | Bekliyor |
| E-03 | Kesme/exception handling | Spike karşılaştırma | Spike ISS | Bekliyor |
| E-04 | OBI-AXI köprüsü geçis doğruluğu | Komut izi + waveform | Spike + Verilator | Bekliyor |

### 3.2 Doğrulama Planı Belgesi

| # | Çıktı | Durum |
|---|-------|-------|
| E-05 | Bu doküman (verification_plan.md) | **Hazır** |
| E-06 | Test senaryosu → beklenen sonuç tablosu | Bekliyor |
| E-07 | Coverage raporu (Verilator) | Bekliyor |

---

## 4. OPSİYONEL Testler

| # | Test | Yöntem | Araç | Durum |
|---|------|--------|------|-------|
| O-01 | RTL kod coverage (line, branch, toggle) | Verilator --coverage | Verilator | Bekliyor |
| O-02 | Functional coverage — NPU FSM durum geçişleri | SV covergroup | DSim | Bekliyor |
| O-03 | Functional coverage — AXI burst uzunluğu dağılımı | SV covergroup | DSim | Bekliyor |
| O-04 | JTAG debug portu testi (+3 bonus puan) | JTAG agent | DSim | Opsiyonel |

---

## 5. FPGA Demo Senaryoları

| # | Senaryo | Beklenen Davranış |
|---|---------|-------------------|
| F-01 | UART1'den "yes" ses verisi gönder | LED 2 yanıyor, UART0 "yes" yazıyor |
| F-02 | UART1'den "no" ses verisi gönder | LED 3 yanıyor, UART0 "no" yazıyor |
| F-03 | Sessizlik gönder | LED 0 yanıyor, UART0 "silence" yazıyor |
| F-04 | Ard arda 3 çıkarım | Her birinde doğru IRQ ve sonuç |

---

## 6. Simülasyon Ortamı

| Araç | Kullanım | Platform |
|------|----------|----------|
| Verilator 5.036 | Birincil RTL simülasyon, lint | Linux/WSL |
| Metrics DSim | UVM, SystemVerilog assertion | Linux/WSL |
| Spike ISS | RISC-V komut izi doğrulama | Linux/WSL |
| Python 3 | Referans model, karşılaştırma scripti | Linux/WSL |
| Vivado | FPGA sentez, P&R, bitstream | Windows |
| OpenLane | Fiziksel tasarım, GDSII | Linux/WSL |

---

## 7. Referans Dosya Planı

```
weights/
  tiny_conv_weights.mem    → DepthwiseConv2D ağırlıkları (640 × INT8)
  tiny_conv_fc_weights.mem → FullyConnected ağırlıkları (16000 × INT8)
  tiny_conv_fc_bias.mem    → FC bias (4 × INT32)
  test_input_yes.mem       → "yes" referans girişi (1960 × INT8)
  test_input_no.mem        → "no" referans girişi
  test_input_silence.mem   → "silence" referans girişi
  expected_yes.txt         → Beklenen logit değerleri (TFLite referans)
```

Ağırlık dosyaları `scripts/extract_weights.py` scriptiyle TFLite Micro
modelinden otomatik çıkarılacak.

---

## 8. Güncelleme Geçmişi

| Tarih | Değişiklik | Kişi |
|-------|-----------|------|
| 2026-05-03 | İlk taslak oluşturuldu | Ali Salih Yıldırım |
