# =============================================================
# TUNGA SoC — teknotest design file list
# All paths are RELATIVE to the teknotest/ directory (absolute paths
# fail during DDK evaluation). Design RTL lives in ../rtl (sibling of
# teknotest/). Run from within teknotest/ via create_vivado_proj.tcl.
# =============================================================

# ---- CV32E40P core (OpenHW) ----
# Explicit manifest list (cv32e40p_manifest.flist). FPU=0, so
# cv32e40p_fp_wrapper.sv is intentionally EXCLUDED — it imports fpnew_pkg
# (CVFPU), which is not vendored. A glob of rtl/*.sv would pull it and
# break compilation. Packages first, then RTL, then top, then sim clock gate.
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
add_files $core/cv32e40p_top.sv
add_files ../rtl/core/cv32e40p/bhv/cv32e40p_sim_clock_gate.sv

# ---- TUNGA gate RTL ----
add_files ../rtl/memory/obi_bootrom.sv
add_files ../rtl/memory/obi_sram.sv
add_files ../rtl/bus/obi2axil.sv

# ---- UART0 peripheral ----
add_files ../rtl/peripherals/uart_pkg.sv
add_files ../rtl/peripherals/uart_rx.sv
add_files ../rtl/peripherals/uart_tx.sv
add_files ../rtl/peripherals/uart_peripheral.sv

# ---- SoC top + wrapper ----
add_files ../rtl/top/tunga_soc_min.sv
add_files ./user_files/teknotest_wrapper.sv

# Note: CV32E40P RTL has no `include directives (packages are added as design
# files and compiled in dependency order), so no +incdir is required here.
# create_vivado_proj.tcl re-sets include_dirs to ./user_files afterwards, so any
# include_dirs set here would be overwritten anyway.

# ---- Defines: simulation + behavioral clock-gate model ----
set_property verilog_define {SIMULATION USE_CG_BEHAV_MODELS} \
    [list [get_filesets sources_1] [get_filesets sim_1]]
