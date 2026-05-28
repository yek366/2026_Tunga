#include <stdint.h>

// Çevre Birimleri Donanım Adresleri
#define UART0_TX_REG        (*(volatile uint32_t*)0x40000000)
#define AI_ACCEL_CSR_REG    (*(volatile uint32_t*)0x50000000)
#define AI_ACCEL_STATUS_REG (*(volatile uint32_t*)0x50000004)

// Basit UART Yazdırma Fonksiyonu
void uart_print(const char* str) {
    while (*str) {
        UART0_TX_REG = *str++;
    }
}

// C Boot Entry Point
__attribute__((section(".text.init")))
void _start() {
    // 1. QSPI üzerinden başarılı boot edildiğinin kanıtı
    uart_print("SYSTEM BOOT OK\n");

    // 2. YZ Hızlandırıcıya yapılandırma komutu gönder
    // 0x01: İşlemi Başlat
    AI_ACCEL_CSR_REG = 0x00000001;

    // 3. YZ Hızlandırıcının işlemi bitirip interrupt/status bayrağı kaldırmasını bekle (Polling)
    while ((AI_ACCEL_STATUS_REG & 0x1) == 0) {
        // Bekle
    }

    uart_print("AI INFERENCE COMPLETE\n");

    // İşletim sisteminin çökmemesi için sonsuz döngü
    while (1) {
        // Bekle
    }
}
