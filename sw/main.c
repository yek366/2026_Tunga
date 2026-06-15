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

// Code Shadowing icin Bellek Bolgeleri
#define QSPI_BASE   0x20000000
#define IMEM_BASE   0x00001000
#define APP_SIZE    256 // Ornek olarak 256 kelime (1KB) kontrol edilecek

// Basit XOR Checksum Fonksiyonu
uint32_t calculate_checksum(uint32_t start_addr, uint32_t words) {
    uint32_t checksum = 0;
    volatile uint32_t *ptr = (volatile uint32_t *)start_addr;
    for (uint32_t i = 0; i < words; i++) {
        checksum ^= ptr[i];
    }
    return checksum;
}

// C Boot Entry Point
__attribute__((section(".text.init")))
void _start() {
    // 0. Code Shadowing (QSPI -> IMEM) Dogrulamasi
    uint32_t qspi_chk = calculate_checksum(QSPI_BASE, APP_SIZE);
    uint32_t imem_chk = calculate_checksum(IMEM_BASE, APP_SIZE);
    
    if (qspi_chk != imem_chk) {
        uart_print("HATA: Code Shadowing Kopyalama Basarisiz!\n");
        while(1); // Sistemi durdur
    }

    // 1. QSPI üzerinden başarılı boot ve doğrulama kanıtı
    uart_print("SYSTEM BOOT OK & CODE SHADOWING VERIFIED\n");

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
