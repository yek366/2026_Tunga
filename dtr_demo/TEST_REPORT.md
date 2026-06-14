# TEKNOTEST - Asgari Tasarım Doğrulama Raporu

Bu rapor, DTR aşamasında olan **Tunga MCU** tasarımımızın asgari tasarım gereksinimlerini (CV32E40P, UART0, Boot ROM ve Data SRAM) doğrulamak amacıyla gerçekleştirilen **TEKNOTEST** entegrasyonu, yapılan RTL iyileştirmelerini ve simülasyon adımlarını açıklamaktadır.

---

## 1. Keşfedilen Bellek Haritası (Memory Map)
Yapılan statik ve dinamik analizler neticesinde tasarımın asgari adres haritası şu şekilde belirlenmiştir:

| Periferik / Bellek | Başlangıç Adresi (Base) | Uzunluk | Bitiş Adresi | Tanım / Kaynak |
| :--- | :--- | :--- | :--- | :--- |
| **Boot ROM** | `0x00000000` | 1 KB | `0x000003FF` | `bootrom.ld` (Senkron AXI-Lite ROM) |
| **Data SRAM** | `0x20000000` | 8 KB | `0x20001FFF` | `bootrom.ld` (Senkron OBI SRAM) |
| **UART0** | `0x40020000` | 256 B | `0x400200FF` | `user_defines.h` (AXI-Lite Slave) |

---

## 2. Yapılanrtl ve Entegrasyon Değişiklikleri

### A. Adres Çözümleyici Güncellemesi (`soc_top.sv`)
SRAM ve UART adres aralıkları en katı şekilde sınırlandırılmıştır. Ayrıca işlemci veri yolunda çakışmaları ve çifte onay (grant) durumlarını önlemek için bir **Bus Serializer** (`bus_busy`) mantığı eklenmiştir. UART köprüsü aktif bir işlemi yürütürken SRAM istekleri bekletilerek veri yolu güvenliği sağlanmıştır:
* **SRAM Aralık Denetimi:** `(data_addr >= 32'h2000_0000) && (data_addr < 32'h2000_2000)`
* **UART Aralık Denetimi:** `(data_addr >= 32'h4002_0000) && (data_addr < 32'h4002_0100)`

### B. Default Slave (Hata Yönetici) Entegrasyonu (`soc_top.sv`)
İşlemcinin haritalandırılmamış (`!is_sram && !is_uart`) bir adrese erişmeye çalışması durumunda kilitlenmesini (deadlock) önlemek için **Default Slave** mekanizması entegre edilmiştir. Bu modül:
* Tanımsız istek yapıldığında anında `gnt` verir.
* Bir saat vuruşu sonra `rvalid` sinyalini onaylar ve geriye sahte veri olarak `32'hDEADBEEF` değerini döndürür.

### C. OBI-to-AXI4-Lite Köprüsü El Sıkışma Düzeltmesi (`soc_top.sv`)
Köprünün içindeki FSM, AXI4-Lite el sıkışma kurallarına tam uyumlu hale getirilmiştir:
* **Yazma Kanalları:** `awready_uart` ve `wready_uart` sinyalleri gelene kadar `awvalid` ve `wvalid` sinyalleri hatta tutulur, gelince temizlenir.
* **CPU Yanıtı:** CPU'ya giden `rvalid` işareti ancak UART slave'den `bvalid` (yazma için) veya `rvalid` (okuma için) geldiğinde onaylanır.
* **Gecikme Önleme:** Okuma verisi (`rdata_uart`), `rvalid_uart` geldiği çevrimde CPU veri yoluna doğrudan combinational olarak yansıtılarak fazladan 1-cycle veri gecikmesi önlenmiştir.

### D. Yanıt Yönlendirme Takibi (`active_dest`)
CPU'nun veri fazı tamamlanmadan yeni bir istek adresi sunması durumunda (OBI boru hattı yapısı gereği) yanıtın yanlış periferiğe yönlenmesini engellemek adına `active_dest` yazmacı eklenmiştir. Yanıtlar, isteğin ilk yapıldığı hedefe göre yönlendirilir.

### E. Göreceli Yollar (Relative Paths)
Hakem değerlendirmesinde hata alınmaması adına `user_files/compile_user_design.tcl` içerisindeki tüm absolute path'ler (mutlak yollar) göreceli yol (`../`) formatına dönüştürülmüştür. `teknotest` klasörünü ana reponuzun (`tunga_mcu/tunga_mcu/`) altına kopyaladığınızda kod doğrudan derlenecektir.

---

## 3. Simülasyonun Koşturulması (Tcl Console Üzerinden)
Sıfırdan projeyi oluşturup doğrulamak için şu adımları izleyin:
1. `vivado_proj` dizinini sistemden silin.
2. Vivado'yu açın ve Tcl konsoluna şu komutları yazın:
   ```tcl
   cd c:/Users/Acer/Downloads/teknotest_pack/teknotest
   source ./scripts/create_vivado_proj.tcl
   launch_simulation
   run -all
   ```

### Beklenen Çıktı Logu:
```text
[98170000] INFO: Read byte 0x52 ('R')
[98170000] INFO: Received expected byte 0x52 ('R')
[98170000] INFO: Sending byte 0x41 ('A') to DUT
[268290000] INFO: Read byte 0x48 ('H')
[355990000] INFO: Read byte 0x65 ('e')
...
[1232990000] INFO: Read byte 0x21 ('!')
[1232990000] TEST SUCCESS: Received expected string "Hello World!"
$finish called at time : 1232990 ns
```

---

## 4. Ekran Görüntüsü ve Waveform Raporlama Rehberi
Yarışma raporunuza eklemek üzere en iyi ekran görüntülerini Vivado üzerinden şu şekilde alabilirsiniz:

1. **Önemli Sinyalleri Dalga Şekli (Waveform) Ekranına Ekleyin:**
   * `/teknotest_tb/clk` (Sistem saati)
   * `/teknotest_tb/resetn` (Sistem sıfırlama)
   * `/teknotest_tb/uart_tx` ve `/teknotest_tb/uart_rx` (Ana UART pinleri)
   * `/teknotest_tb/dut/u_soc_top/state` (Köprü FSM'inin durum geçişleri: `IDLE`, `WAIT_WRITE`, `WAIT_READ`)
   * `/teknotest_tb/dut/u_soc_top/active_dest` (Routing takibi)
2. **Görünümü Optimize Edin:**
   * Grafik alanına tıklayıp **F** (Zoom Fit) tuşuna basarak tüm akışı sığdırın.
   * UART hattından geçen karakterleri rahat okumak için dalga şeklindeki `uart_tx` ve `uart_rx` sinyallerine sağ tıklayıp **Radix -> ASCII** yapın. Böylece dalga üzerinde `'R'`, `'A'`, `'H'`, `'e'` gibi harfleri doğrudan okuyabilirsiniz.
3. **Ekran Görüntüsünü Dışa Aktarın:**
   * Vivado üst menüsünden **File -> Export -> Export Image...** yolunu seçin.
   * Çözünürlüğü yüksek ayarlayarak dalga şeklinin net bir PNG görüntüsünü raporunuza veya reponuzdaki `images/` klasörüne ekleyin.
