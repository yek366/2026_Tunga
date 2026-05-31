#include <stdio.h>
#include <stdlib.h>
#include <svdpi.h>

// Spike ISS'in (C tarafı) sembolik arayüz tanımlaması
typedef struct {
    int dummy_state;
} SpikeISS;

void spike_step_internal(SpikeISS* iss) {
    // Spike simülatörünü 1 cycle ilerlet (Instruction fetch, decode, execute vs.)
    // printf("[Spike DPI-C] ISS 1 cycle ilerletildi.\n");
}

void spike_reset(SpikeISS* iss) {
    // Spike durumunu sıfırla
    printf("[Spike DPI-C] ISS Resetlendi.\n");
}

// Global ISS instance
static SpikeISS* spike_instance = NULL;

// SystemVerilog'dan çağrılacak olan DPI-C fonksiyonu
void spike_step(svLogic clk, svLogic rst_n) {
    // İlk çağrıldığında instance oluştur
    if (spike_instance == NULL) {
        spike_instance = (SpikeISS*)malloc(sizeof(SpikeISS));
        spike_instance->dummy_state = 0;
        printf("[Spike DPI-C] Spike ISS Koprusu Baslatildi.\n");
    }

    // rst_n = 0 (sv_0) ise sistemi sıfırla, değilse çalıştır
    if (rst_n == sv_0) {
        spike_reset(spike_instance);
    } else if (clk == sv_1) {
        // Sadece pozitif saat kenarında ilerlet
        spike_step_internal(spike_instance);
    }
}
