# --- TUNGA MCU - NİHAİ VE KUSURSUZ SCRIPT ---

add_files ./user_files/teknotest_wrapper.sv

# 1. Ana Tasarım Dosyaları
add_files "../soc_top.sv"
add_files "../qspi_core_uart/qspi_core_uart.srcs/sources_1/imports/eneskrmz/Desktop/tunga/uart_stream/src/uart_stream_peripheral.sv"
add_files "../qspi_core_uart/qspi_core_uart.srcs/sources_1/imports/eneskrmz/Desktop/tunga/uart_stream/src/uart_tx.sv"
add_files "../soc_top.sv/soc_top.sv.srcs/sources_1/imports/rtl/uart_rx.sv"
add_files "../qspi_core_uart/qspi_core_uart.srcs/sources_1/imports/eneskrmz/Desktop/tunga/uart_stream/src/uart_pkg.sv"
add_files "../qspi_core_uart/qspi_core_uart.srcs/sources_1/imports/Desktop/tunga/qspicore/qspicore/qspicore.srcs/sim_1/imports/tunga/boot_rom.sv"
add_files "../rtl/tunga_sram.sv"

# 2. Paket Dosyaları
add_files "../qspi_core_uart/qspi_core_uart.srcs/sources_1/imports/eneskrmz/Desktop/cv32e40p-master/rtl/include/cv32e40p_apu_core_pkg.sv"
add_files "../qspi_core_uart/qspi_core_uart.srcs/sources_1/imports/eneskrmz/Desktop/cv32e40p-master/rtl/include/cv32e40p_fpu_pkg.sv"
add_files "../qspi_core_uart/qspi_core_uart.srcs/sources_1/imports/eneskrmz/Desktop/cv32e40p-master/rtl/include/cv32e40p_pkg.sv"

# 3. İŞTE O SON EKSİK PARÇA: CLOCK GATE
add_files "../qspi_core_uart/qspi_core_uart.srcs/sources_1/new/cv32e40p_clock_gate.sv"

# 4. Çekirdeğin Tüm Alt Modülleri
add_files [glob "../qspi_core_uart/qspi_core_uart.ipdefs/CV32_IP/src/*.sv"]

# 5. Kütüphane Yolları
set_property include_dirs [file normalize "./user_files/"] [list [get_filesets sources_1] [get_filesets sim_1]]
set_property include_dirs [file normalize "../qspi_core_uart/qspi_core_uart.srcs/sources_1/imports/eneskrmz/Desktop/cv32e40p-master/rtl/include/"] [list [get_filesets sources_1] [get_filesets sim_1]]

# 6. Top Modül Tescili
set_property top teknotest_wrapper [get_filesets sources_1]
set_property top teknotest_tb [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1