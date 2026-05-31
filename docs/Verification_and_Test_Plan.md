# Doğrulama ve Test Planı (Verification and Test Plan)

## 1. Giriş ve Hedefler

Bu belge, Teknofest 2026 Çip Tasarım Yarışması Mikrodenetleyici Kategorisi kapsamında geliştirilen CV32E40P RISC-V çekirdekli SoC (Tunga) donanımının doğrulama stratejisini detaylandırmaktadır. 

Ana hedefimiz, tasarlanan SoC'nin şartnameye, endüstri standartlarına (UVM ve AXI) ve beklenen mimari performans kriterlerine birebir uyduğundan emin olmaktır. Doğrulama süreci boyunca Xilinx Vivado (XSIM) platformu kullanılarak yüksek performanslı bir ko-simülasyon ve otomasyon çevresi hedeflenmektedir.

### Başarı Kriterleri
- **Boot Akışının Doğrulanması:** Sistemin sıfırlama (reset) anından itibaren QSPI flash üzerinden başarıyla C/Assembly komutlarını çekip çalıştırmaya (boot) başlayabildiğinin uçtan uca kanıtlanması.
- **%100 AXI Protokol Uyumluluğu:** Açık kaynak AXI VIP ajanları üzerinden sistemdeki tüm okuma/yazma ve burst işlemlerinin protokole sıfır hata toleransıyla uyum sağlaması.
- **Çekirdek Komut İzlerinin (Instruction Trace) Eşleşmesi:** Çevrimiçi DPI-C ko-simülasyon mimarisi kurularak, RTL'den alınan komut izlerinin Spike ISS referans modeliyle anlık (online) %100 örtüşmesi.

---

## 2. Doğrulanacak Modüller ve Test Senaryoları

### İşlemci Çekirdeği (Core)
Çekirdek testleri, DSim üzerinden DPI-C köprüsü kurularak Spike ISS (Instruction Set Simulator) referans modeline anlık bağlanılması esasına dayanır.
- **Rastgele (Randomized) Komut Stresi Testi:** İşlemciye UVM dizileri (sequences) aracılığıyla rastgele oluşturulmuş yoğun RISC-V komut setleri (ALU, Memory Access, Branch) gönderilir. DPI-C ile Spike'a da aynı komut akışı iletilir; RTL'in ve Spike'ın register güncellemeleri döngü-döngü (cycle-accurate) eşleşmelidir.
- **Yönlendirilmiş (Directed) Kesme (Interrupt) Testi:** RISC-V çekirdeğine harici kesme kontrolcüsü üzerinden ani asenkron kesmeler (NMI/External/Timer) yollanır ve çekirdeğin anında kesme vektörüne (CSR trap) dallanıp işlemi Spike ile tutarlı yürüttüğü doğrulanır.

### Çevre Birimleri (Peripherals)
Çevre birimleri, kendi protokollerine uygun AXI VIP'ler ile stres altına sokulur.
- **Rastgele (Randomized) AXI Burst Testi:** AXI Master VIP kullanılarak çevre birimi register'larına farklı uzunluklarda ve hizalamalarda (unaligned/aligned burst) rastgele AXI okuma ve yazma işlemleri gerçekleştirilip, modüllerin asılı (hang) kalmadığı test edilir.
- **Yönlendirilmiş (Directed) Protokol Seviyesi Uçtan Uca Test:** UART tx/rx hatları, I2C cihaz etkileşimleri ve Timer sayıcı eşleşmeleri için özel yönlendirilmiş UVM testleri yazılır. UART baud oranında beklenen verinin hatasız iletildiği AXI monitorler tarafından kaydedilir.

### YZ Hızlandırıcı (AI Accelerator)
Hızlandırıcının, TensorFlow Lite Micro Speech mimarisiyle uygun donanımsal işlemleri sorunsuz yerine getirmesi beklenir.
- **Yönlendirilmiş (Directed) Ses Verisi (Speech) İşleme Testi:** UART-stream arayüzü ile dışarıdan beslenen ses verisi, donanımsal YZ hızlandırıcısından geçirilerek sınıflandırılır. Sonuçlar, yazılım ortamındaki Python/TFLite referans (golden) modelin çıktısıyla karşılaştırılır ve hata/sapma payının maksimum %10 sınırında kaldığı onaylanır.
- **Rastgele (Randomized) Kesme (Interrupt) ve Backpressure Testi:** Hızlandırıcı işlem yaparken, rastgele anlarda UART buffer'ı doldurularak backpressure oluşturulur ve hızlandırıcının işlemi bitirdiğinde CPU'ya başarılı bir interrupt bayrağı gönderdiği doğrulanır.

### Sistem ve Boot Testleri
- **Yönlendirilmiş (Directed) QSPI Boot Akışı Testi:** Sistem sıfırlandıktan hemen sonra (power-on reset), işlemci QSPI Master modülünü kullanarak flash bellek adres bölgesinden "ilk çalıştırma (boot) komutlarını" talep eder. VIP aracılığıyla sahte (dummy) flash üzerinden C/Assembly bootloader kodları döndürülür ve çekirdeğin başarılı bir şekilde main() fonksiyonuna ulaştığı kanıtlanır.
- **Rastgele (Randomized) Warm Reset Testi:** Sistem tam boot olup normal çalışmasına devam ederken rastgele zamanlarda yazılımsal ve donanımsal (warm/cold) resetler atılarak sistemin hiçbir state takılması yaşamadan baştan QSPI boot sekansına dönebildiği test edilir.

---

## 3. Metodoloji ve Araçlar

Doğrulama ve otomasyon metodolojimiz tamamen endüstri standartları çevresinde şekillendirilmiştir:
- **Simülasyon Aracı:** Hızlı derleme ve ko-simülasyon yetenekleri, DPI-C adaptasyonu ve donanım destekli simülasyon uyumluluğu sebebiyle **Xilinx Vivado (XSIM)** simülatörü ana motorumuzdur. UVM mimarisi doğrudan Xilinx UVM Kütüphanesi kullanılarak yürütülmektedir.
- **UVM ve AXI VIP:** Sistemdeki AXI veriyolu haberleşmesini ve protokol kurallarını (protocol checks) teyit etmek için açık kaynaklı UVM tabanlı ajanlar (Agents) ve kendi-kendini test eden (Self-Checking) Mock BFM'ler yapılandırılmıştır.
- **Otomasyon:** Testlerin başlatılması, derleme hatalarının ayrıştırılması ve loglarda "FAIL/UVM_ERROR" aranması gibi tüm CI/CD süreçleri özel Python otomasyon betikleri (`scripts/run_sim.py`) üzerinden tek tıkla yürütülmektedir.
- **Ko-Simülasyon (Co-Sim):** Online çevrimiçi kıyaslama için C++ / DPI-C arabirimleriyle Spike (RISC-V ISS) çekirdeğe gömülmüştür.

---

## 4. Kapsam (Coverage) ve İlerleme Takibi

Yarışma ve standartların bir gereği olarak kod ve fonksiyonel kapsam metrikleri, simülasyonlarımızdan toplanmaktadır:
- **Code Coverage:** Vivado XSIM kullanılarak RTL üzerindeki Statement, Branch, FSM ve Toggle Coverage verileri analiz edilecek ve ölü kodlar (dead-code) tespit edilecektir.
- **Functional Coverage:** `coverage_collector.sv` içerisindeki UVM Subscriber'lar ile donanım (UART baud rate vs.) ve AXI sınır değerlerinin (corner cases) durumları ölçülmekte, test bitiminde `report_phase` üzerinden "Fonksiyonel Kapsama Raporu" otomatik olarak loglanmaktadır.

### Test İlerleme Tablosu

| Test ID | Test Senaryosu Adı | Odak Modül | Durum | Başarı Oranı |
| :--- | :--- | :--- | :---: | :---: |
| `TC_CORE_01` | Rastgele Komut Stresi (Spike Co-Sim) | Çekirdek | Bekliyor | - |
| `TC_CORE_02` | Yönlendirilmiş Kesme (Interrupt) Trap | Çekirdek | Devam Ediyor | %50 |
| `TC_PER_01`  | AXI Rastgele Burst Yazma/Okuma | Çevre Birimleri | Bekliyor | - |
| `TC_PER_02`  | UART/I2C/Timer Protokol ve İşlev | Çevre Birimleri | Tamamlandı (Mock) | %100 |
| `TC_AI_01`   | TFLite Micro Speech Referans Kıyaslama | YZ Hızlandırıcı | Tamamlandı (Mock) | %100 |
| `TC_AI_02`   | AI Hızlandırıcı Backpressure ve Kesme | YZ Hızlandırıcı | Bekliyor | - |
| `TC_SYS_01`  | QSPI Master Uçtan Uca Boot Akışı | Sistem / QSPI | Tamamlandı | %100 |
| `TC_SYS_02`  | Rastgele Donanımsal/Yazılımsal Sıfırlama | Sistem | Bekliyor | - |
