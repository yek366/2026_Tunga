# =============================================================
# TUNGA SoC — teknotest design file list (Yuşa soc_top entegrasyonu)
# Tüm yollar teknotest/ dizinine GÖRE relative (absolute = jüri fail).
# Tasarım RTL'i ../rtl altında. create_vivado_proj.tcl içinden çağrılır.
# =============================================================

# ---- CV32E40P core (OpenHW) — explicit manifest, fp_wrapper HARİÇ (FPU=0) ----
set core ../rtl/core/cv32e40p/rtl
add_files $core/include/cv32e40p_apu_core_pkg.sv
add_files $core/include/cv32e40p_fpu_pkg.sv
add_files $core/include/cv32e40p_pkg.sv
add_files $core/cv32e40p_if_stage.sv
add_files $core/cv32e40p_cs_registers.sv
add_files $core/cv32e40p_register_file_ff.sv
add_files $core/cv32e40p_load_store_unit.sv
add_files $core/cv32e40p_id_stage.sv
add_files $core/cv32e40p_aligner.sv
add_files $core/cv32e40p_decoder.sv
add_files $core/cv32e40p_compressed_decoder.sv
add_files $core/cv32e40p_fifo.sv
add_files $core/cv32e40p_prefetch_buffer.sv
add_files $core/cv32e40p_hwloop_regs.sv
add_files $core/cv32e40p_mult.sv
add_files $core/cv32e40p_int_controller.sv
add_files $core/cv32e40p_ex_stage.sv
add_files $core/cv32e40p_alu_div.sv
add_files $core/cv32e40p_alu.sv
add_files $core/cv32e40p_ff_one.sv
add_files $core/cv32e40p_popcnt.sv
add_files $core/cv32e40p_apu_disp.sv
add_files $core/cv32e40p_controller.sv
add_files $core/cv32e40p_obi_interface.sv
add_files $core/cv32e40p_prefetch_controller.sv
add_files $core/cv32e40p_sleep_unit.sv
add_files $core/cv32e40p_core.sv
add_files ../rtl/core/cv32e40p/bhv/cv32e40p_sim_clock_gate.sv

# ---- UART0 (stream) periferik yığını ----
add_files ../rtl/peripherals/uart_pkg.sv
add_files ../rtl/peripherals/uart_tx.sv
add_files ../rtl/peripherals/uart_rx.sv
add_files ../rtl/peripherals/sync_fifo.sv
add_files ../rtl/peripherals/uart_stream_peripheral.sv

# ---- Bellekler + SoC top ----
add_files ../rtl/boot/boot_rom.sv
add_files ../rtl/memory/tunga_sram.sv
add_files ../rtl/top/soc_top.sv

# ---- Wrapper (user_files) ----
add_files ./user_files/teknotest_wrapper.sv

# ---- Defines: simülasyon + behavioral clock-gate modeli ----
set_property verilog_define {SIMULATION USE_CG_BEHAV_MODELS} \
    [list [get_filesets sources_1] [get_filesets sim_1]]
