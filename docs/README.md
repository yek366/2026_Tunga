# 2026 Tunga - UVM Doğrulama Ortamı (Verification Environment)

Bu dizin yapısı, Teknofest 2026 Çip Tasarım Yarışması Mikrodenetleyici Kategorisi için geliştirilen CV32E40P RISC-V SoC projesinin izole doğrulama süreçlerini yürütmek amacıyla oluşturulmuştur.

## Dizin Yapısı

- `rtl/` : Tasarım ekibine ait güncel RTL kaynak kodları.
- `tb/` : Testbench hiyerarşisi, UVM bileşenleri (agent, env, sequences, vb.) ve test senaryoları.
- `sim/` : Simülasyon süreçlerinin yürütüldüğü çalışma dizini (loglar, dalga formları ve derleme çıktıları burada tutulur).
- `scripts/`: Derleme ve simülasyon adımlarını otomatize eden betikler (Makefile, Python).
- `docs/` : Doğrulama planları, test raporları ve kullanım kılavuzları.

## Kurulum ve Çalıştırma

1. **Gereksinimler:** Metrics DSim veya Verilator araçlarının sisteme kurulu ve ortam değişkenlerinin (PATH) ayarlanmış olduğundan emin olun.
2. Simülasyon adımları için `sim/` dizinine geçin veya `scripts/` altındaki otomasyon betiklerini kullanın.
3. Python betikleri kullanılıyorsa, gerekli bağımlılıklar için bir sanal ortam oluşturup aktif edin:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   ```
4. Derleme ve testleri başlatmak için projeye özel tanımlanmış olan Makefile / script komutunu çalıştırın.

---

## Jüri İnceleme ve Çalıştırma Kılavuzu (Otomasyon)

Jüri üyelerinin, doğrulama ortamını kendi sunucularında tek tıkla test edebilmesi için Python tabanlı bir otomasyon betiği hazırlanmıştır. 

### Bağımlılıklar (Requirements)
Sisteme herhangi bir harici Python paketi kurmanıza gerek yoktur (Python 3.x standart kütüphanelerini kullanır). Ancak simülatör olarak aşağıdaki aracın sistemde (PATH ortam değişkeninde) yüklü olması şarttır:
- **Metrics DSim** (UVM ve SV destekli yüksek performanslı simülatör)

### Testleri Çalıştırma

Terminal veya PowerShell üzerinden projenin kök dizinine gidiniz. Aşağıdaki tek komut ile tüm test süreci sırasıyla; derleme (compile), simülasyon (execute) ve sonuç analizi olarak gerçekleştirilecektir:

```bash
# Windows / Linux ortamı
python scripts/run_sim.py
```

Bu script çalıştığında:
1. `rtl/` altındaki kodlar ile testbench'i bağlayıp `DSim` kullanarak tek adımda derleyecek ve koşturacaktır.
2. Simülasyon loglarını `sim/` dizinine kaydedecek ve standart çıktıları eş zamanlı olarak konsola basacak.
3. Logların içindeki `UVM_ERROR`, `UVM_FATAL` ve `FAIL` yapılarını analiz edip en sonda jüri için terminale yeşil **TEST PASSED** veya kırmızı **TEST FAILED** yazdıracaktır.
