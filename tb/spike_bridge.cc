#include <iostream>
#include <svdpi.h>

// Spike ISS'in (C++ tarafı) sembolik arayüz tanımlaması
class SpikeISS {
public:
    void step() {
        // Spike simülatörünü 1 cycle ilerlet (Instruction fetch, decode, execute vs.)
        // std::cout << "[Spike DPI-C] ISS 1 cycle ilerletildi." << std::endl;
    }
    
    void reset() {
        // Spike durumunu sıfırla
        std::cout << "[Spike DPI-C] ISS Resetlendi." << std::endl;
    }
};

// Global ISS instance
static SpikeISS* spike_instance = nullptr;

extern "C" {
    // SystemVerilog'dan çağrılacak olan DPI-C fonksiyonu
    void spike_step(svLogic clk, svLogic rst_n) {
        // İlk çağrıldığında instance oluştur
        if (spike_instance == nullptr) {
            spike_instance = new SpikeISS();
            std::cout << "[Spike DPI-C] Spike ISS Koprusu Baslatildi." << std::endl;
        }

        // rst_n = 0 (sv_0) ise sistemi sıfırla, değilse çalıştır
        if (rst_n == sv_0) {
            spike_instance->reset();
        } else if (clk == sv_1) {
            // Sadece pozitif saat kenarında ilerlet
            spike_instance->step();
        }
    }
}
