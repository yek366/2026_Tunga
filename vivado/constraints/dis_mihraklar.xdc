## ====================================================================
## NEXYS 4 - SYSTEM CLOCK & SYSTEM RESET
## ====================================================================
# Kart üzerindeki 100 MHz osilatör (E3 pinine bağlıdır)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_in1 }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_in1 }];

# Kart üzerindeki CPU_RESET butonu (Aktif Alçaktır - C12 pinine bağlıdır)
# DİKKAT: Clocking Wizard ve Reset IP ayarlarında reset tipini ACTIVE LOW seçmelisin!
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { reset }];

## ====================================================================
## NEXYS 4 - UART INTERFACE (USB-UART Bridge)
## ====================================================================
# Bilgisayarla haberleşecek olan ana UART hatları
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; # FTDI_TXD_MCU
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; # FTDI_RXD_MCU

## ====================================================================
## NEXYS 4 - JTAG INTERFACE (PMOD JA - Üst Sıra Örneği)
## ====================================================================
# Nexys 4'ün kendi USB-JTAG'i çipi programlamak için kilitlidir. 
# Bu yüzden yazdığın işlemciyi debug etmek için harici JTAG kablosunu PMOD JA'ya bağlamalısın.
set_property -dict { PACKAGE_PIN B13   IOSTANDARD LVCMOS33 } [get_ports { jtag_tck_i }]; # PMOD JA Pin 1
set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports { jtag_tms_i }]; # PMOD JA Pin 2
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 } [get_ports { jtag_tdi_i }]; # PMOD JA Pin 3
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports { jtag_tdo_pad }]; # PMOD JA Pin 4
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { jtag_trst_ni }]; # PMOD JA Pin 7

# JTAG hatlarının elektriksel kararlılığı için dahili dirençleri aktif ediyoruz
set_property PULLDOWN true [get_ports { jtag_tck_i }];
set_property PULLUP true   [get_ports { jtag_tms_i }];
set_property PULLUP true   [get_ports { jtag_tdi_i }];
set_property PULLUP true   [get_ports { jtag_trst_ni }];

## ====================================================================
## NEXYS 4 - QUAD SPI FLASH INTERFACE (Yerleşik SPI Flash Bacakları)
## ====================================================================
# Kartın üzerindeki yerleşik Spansion Quad SPI Flash belleğin gerçek çip bacakları
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { qspi_io0 }]; # SPI_MOSI
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { qspi_io1 }]; # SPI_MISO
set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { qspi_io2 }]; # SPI_WP
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { qspi_io3 }]; # SPI_HOLD
set_property -dict { PACKAGE_PIN L13   IOSTANDARD LVCMOS33 } [get_ports { qspi_ss }];  # SPI_CS
# Not: QSPI Clock (SCK) pini Artix-7 mimarisinde özel bir konfigürasyon bacağıdır (STARTUPE2).
# Eğer IP'n CCLK pinini normal I/O gibi sürmeye çalışırsa hata alırsın. 
# Genelde şemada qspi_sck external portu açılır ve bacak olarak E9 atanır:
set_property -dict { PACKAGE_PIN E9    IOSTANDARD LVCMOS33 } [get_ports { qspi_sck }]; 

## ====================================================================
## VIVADO CONFIGURATION BITSTREAM AYARLARI (Nexys 4 İçin Zorunlu)
## ====================================================================
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]