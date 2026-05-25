#include <iostream>
#include <memory>
#include <verilated.h>

// "Vtop.h" Verilator tarafindan top module (RTL) adina gore otomatik uretilir.
// Eger top module adiniz farkliysa (ornek: cv32e40p_core) burayi "Vcv32e40p_core.h" olarak guncellemelisiniz.
#include "Vtop.h"

int main(int argc, char** argv) {
    // Verilator ortam argumanlarini ayarla
    Verilated::commandArgs(argc, argv);
    
    // Top module ornegini (instance) akilli isaretci ile olustur
    auto top = std::make_unique<Vtop>();

    // Sinyallerin baslangic durumlari
    top->clk = 0;
    top->rst_n = 0; // Aktif dusuk (active-low) reset varsayilmistir

    // Simulasyon zaman degiskeni
    vluint64_t main_time = 0;

    // Reset dongusu: Ilk 10 saat vurusunda reset sinyalini basili tut
    while (main_time < 20 && !Verilated::gotFinish()) {
        if (main_time > 10) {
            top->rst_n = 1; // 10 birim zaman sonra reset'i kaldir
        }
        
        // Saati toggle et (her 1 zaman biriminde yarim periyot)
        top->clk = !top->clk;
        
        // Modulun yeni durumunu degerlendir
        top->eval();
        
        main_time++;
    }

    // Ana simulasyon dongusu
    // RTL icerisinden $finish veya $stop cagrisi gelene kadar (veya timeout) calisir
    // Timeout degeri burada sembolik olarak 10000 alinmistir
    while (main_time < 10000 && !Verilated::gotFinish()) {
        top->clk = !top->clk;
        top->eval();
        main_time++;
    }

    // Simulasyon bitisi: temiz kapanis islemleri
    top->final();
    
    std::cout << "Simulasyon tamamlandi. (Zaman: " << main_time << ")" << std::endl;
    return 0;
}
