# 2026 Tunga - UVM Doğrulama Ortamı (Verification Environment)

Bu dizin yapısı, Teknofest 2026 Çip Tasarım Yarışması Mikrodenetleyici Kategorisi için geliştirilen CV32E40P RISC-V SoC projesinin doğrulama süreçlerini yürütmek amacıyla oluşturulmuştur.

## Dizin Yapısı

- `rtl/` : Tasarım ekibine ait güncel RTL kaynak kodları.
- `tb/` : Testbench hiyerarşisi, UVM bileşenleri (agent, env, sequences, vb.) ve test senaryoları.
- `sim/` : Simülasyon süreçlerinin yürütüldüğü çalışma dizini (loglar, dalga formları ve derleme çıktıları burada tutulur).
- `scripts/`: Derleme ve simülasyon adımlarını otomatize eden betikler (Python).
- `docs/` : Doğrulama planları, test raporları ve kullanım kılavuzları.

## Kurulum ve Çalıştırma

1. **Gereksinimler:** Metrics DSim aracının sisteme kurulu ve ortam değişkenlerinin (PATH) ayarlanmış olduğundan emin olun.
2. Simülasyon adımları için `sim/` dizinine geçin veya `scripts/` altındaki otomasyon betiklerini kullanın.
3. Gerekli bağımlılıklar için bir sanal ortam oluşturup aktif edin:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   ```
4. Derleme ve testleri başlatmak için projeye özel tanımlanmış olan script komutunu çalıştırın.
