# ============================================================
# Tunga SoC Vivado Projesi - Temiz Otomasyon TCL
# Uretildi: run_sim.py (Teknofest 2026)
# Bu dosya her calistirmada sifirdan uretilir.
# ============================================================

set proj_root "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga"
set proj_name "tunga_micro_1780258695"
set part      "xc7a12ticsg325-1L"

catch { close_project -quiet }
create_project $proj_name $proj_root/$proj_name -part $part -force

# ---- RTL Kaynak Dosyalari (sources_1) ----
set obj [get_filesets sources_1]
set core_files [list]
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/assertions.svh"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cf_math_pkg.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_aligner.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_alu.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_alu_div.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_apu_core_pkg.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_apu_disp.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_clock_gate.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_compressed_decoder.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_controller.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_core.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_cs_registers.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_decoder.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_ex_stage.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_ff_one.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_fifo.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_fpu_pkg.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_fp_wrapper.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_hwloop_regs.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_id_stage.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_if_stage.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_int_controller.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_load_store_unit.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_mult.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_obi_interface.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_pkg.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_popcnt.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_prefetch_buffer.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_prefetch_controller.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_register_file_ff.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_sleep_unit.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_top.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_cast_multi.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_classifier.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_divsqrt_multi.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_divsqrt_th_32.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_fma.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_fma_multi.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_noncomp.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_opgroup_block.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_opgroup_fmt_slice.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_opgroup_multifmt_slice.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_pkg.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_rounding.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_top.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/gated_clk_cell.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/lzc.sv"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_ctrl.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_ff1.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_pack_single.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_prepare.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_round_single.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_special.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_srt_single.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_top.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fpu_dp.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fpu_frbus.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fpu_src_type.v"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/registers.svh"
lappend core_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/rr_arb_tree.sv"
if {[llength $core_files] > 0} {
    add_files -norecurse -fileset $obj $core_files
}

set rtl_files [list]
lappend rtl_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/tunga_soc_top.sv"
if {[llength $rtl_files] > 0} {
    add_files -norecurse -fileset $obj $rtl_files
}

set_property top tunga_soc_top $obj
set_property top_auto_set 0    $obj

# ---- Testbench Dosyalari (sim_1) ----
set obj [get_filesets sim_1]
set core_files_sim [list]
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/assertions.svh"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cf_math_pkg.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_aligner.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_alu.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_alu_div.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_apu_core_pkg.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_apu_disp.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_clock_gate.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_compressed_decoder.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_controller.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_core.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_cs_registers.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_decoder.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_ex_stage.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_ff_one.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_fifo.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_fpu_pkg.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_fp_wrapper.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_hwloop_regs.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_id_stage.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_if_stage.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_int_controller.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_load_store_unit.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_mult.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_obi_interface.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_pkg.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_popcnt.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_prefetch_buffer.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_prefetch_controller.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_register_file_ff.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_sleep_unit.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/cv32e40p_top.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_cast_multi.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_classifier.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_divsqrt_multi.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_divsqrt_th_32.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_fma.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_fma_multi.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_noncomp.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_opgroup_block.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_opgroup_fmt_slice.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_opgroup_multifmt_slice.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_pkg.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_rounding.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/fpnew_top.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/gated_clk_cell.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/lzc.sv"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_ctrl.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_ff1.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_pack_single.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_prepare.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_round_single.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_special.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_srt_single.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fdsu_top.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fpu_dp.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fpu_frbus.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/pa_fpu_src_type.v"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/registers.svh"
lappend core_files_sim "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/rtl/core/src/rr_arb_tree.sv"
if {[llength $core_files_sim] > 0} {
    add_files -norecurse -fileset $obj $core_files_sim
}

set tb_files [list]
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/axi_agent_pkg.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/base_test.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/coverage_collector.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/seq_ai_accelerator.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/seq_jtag_debug.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/seq_peripherals.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/tb_system_integration.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/tb_tunga_soc.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/tb_tunga_soc_modified.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/tunga_env.sv"
lappend tb_files "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/tunga_soc_if.sv"
if {[llength $tb_files] > 0} {
    add_files -norecurse -fileset $obj $tb_files
}

# ---- DPI-C: Spike ISS Koprusu ----
add_files -norecurse -fileset $obj "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/spike_bridge.c"
catch { set_property file_type {C Source} [get_files -of_objects $obj "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/spike_bridge.c"] }
catch { set_property used_in_synthesis false [get_files -of_objects $obj "C:/Users/VICTUS/.gemini/antigravity/scratch/2026_Tunga/tb/spike_bridge.c"] }

set_property top          tb_tunga_soc_modified       $obj
set_property top_lib      xil_defaultlib $obj
set_property top_auto_set 0              $obj
set_property -name {xsim.elaborate.xelab.more_options} -value {-timescale 1ns/1ps} -objects $obj

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts {Proje hazir. Simulasyon baslatiliyor...}

# ---- XSIM Simulasyonu ----
launch_simulation
run all

puts {Simulasyon tamamlandi.}
exit
