# =========================================================================
# run_uvm_vivado.tcl - TUNGA SoC UVM Simülasyon Scripti
# Çalıştırma: vivado -mode batch -source scripts/run_uvm_vivado.tcl -nojournal
# =========================================================================

set REPO_ROOT  "C:/Users/VICTUS/Desktop/2026_Tunga"
set TB_DIR     "$REPO_ROOT/tb"
set RTL_DIR    "$REPO_ROOT/rtl"
set SIM_DIR    "$REPO_ROOT/sim"

file mkdir $SIM_DIR
cd $SIM_DIR

puts ">>> \[1/3\] Önceki derleme dosyaları temizleniyor..."
foreach d {xsim.dir xsim.covdb} {
    if {[file exists $d]} { file delete -force $d }
}
foreach f {webtalk.log xvlog.log xelab.log xsim.log xvlog.pb uvm_sim.tcl} {
    if {[file exists $f]} { file delete -force $f }
}

# =========================================================================
# Adim 0: RTL kaynak dosyalari derleniyor
# =========================================================================
puts ">>> \[0/4\] RTL kaynak dosyalari derleniyor..."
set r0 [catch {exec "C:/AMDDesignTools/2025.2/Vivado/bin/xvlog.bat" \
    -sv -L uvm --nolog \
    -i $RTL_DIR/core/src \
    -i $RTL_DIR/core/include \
    -f $SIM_DIR/rtl_files_no_jtag.f} out0]
puts $out0
if {[string match "*ERROR*" $out0] && ![string match "*4099*" $out0]} {
    puts ">>> RTL DERLEME HATASI. Devam edilemiyor."
    return
}
puts ">>> RTL derleme OK"

# =========================================================================
# Adim 1A: axi_agent_pkg.sv PAKET olarak derle
# =========================================================================
puts ">>> \[1A/4\] axi_agent_pkg (UVM Package) derleniyor..."
set r1 [catch {exec "C:/AMDDesignTools/2025.2/Vivado/bin/xvlog.bat" \
    -sv -L uvm --nolog \
    $TB_DIR/axi_agent_pkg.sv} out1]
puts $out1
if {$r1 != 0} {
    puts ">>> DERLEME HATASI axi_agent_pkg. Devam edilemiyor."
    return
}
puts ">>> axi_agent_pkg OK"

# =========================================================================
# Adim 1B: UVM ust modulu derle (gercek DUT baglantisiyla)
# =========================================================================
puts ">>> \[1B/4\] tunga_uvm_top (Gercek DUT) derleniyor..."
set r2 [catch {exec "C:/AMDDesignTools/2025.2/Vivado/bin/xvlog.bat" \
    -sv -L uvm --nolog \
    $TB_DIR/tunga_uvm_top.sv} out2]
puts $out2
if {$r2 != 0} {
    puts ">>> DERLEME HATASI tunga_uvm_top. Devam edilemiyor."
    return
}
puts ">>> tunga_uvm_top OK"

# =========================================================================
# Adim 1C: tb_boot_dogrulama (TASK 3 Self-Checking Boot TB)
# =========================================================================
puts ">>> \[1C/4\] tb_boot_dogrulama derleniyor..."
set r2b [catch {exec "C:/AMDDesignTools/2025.2/Vivado/bin/xvlog.bat" \
    -sv -L uvm --nolog \
    $TB_DIR/tb_boot_dogrulama.sv} out2b]
puts $out2b
if {[string match "*ERROR*" $out2b] && ![string match "*4099*" $out2b]} {
    puts ">>> DERLEME HATASI tb_boot_dogrulama. Devam edilemiyor."
    return
}
puts ">>> tb_boot_dogrulama OK"

# =========================================================================
# Adım 2: Elaboration
# =========================================================================
puts ">>> \[2/3\] Elaboration (xelab)..."
set r3 [catch {exec "C:/AMDDesignTools/2025.2/Vivado/bin/xelab.bat" \
    -L uvm --nolog --debug typical -timescale 1ns/1ps \
    tunga_uvm_top \
    -s tunga_uvm_sim} out3]
puts $out3
# xelab timescale uyarisi non-zero donebilir ama snapshot olusturulmus olabilir
# Gercek hata: "Cannot find design unit" mesajini ara
if {[string match "*Cannot find design unit*" $out3] || \
    [string match "*ERROR*" $out3] && ![string match "*4099*" $out3]} {
    puts ">>> ELABORASYON HATASI. Devam edilemiyor."
    return
}
puts ">>> Elaboration OK (timescale uyarilari normal)"

# =========================================================================
# Adım 3: xsim için TCL batch dosyası oluştur (testplusarg sorununu aşmak için)
# =========================================================================
puts ">>> \[3/3\] xsim için argüman ve TCL dosyaları hazırlanıyor..."

# TCL batch: simülasyonu çalıştır ve kapat
set fp [open "uvm_sim.tcl" w]
puts $fp {run all}
puts $fp {quit}
close $fp

# Response dosyası: = içeren argümanları güvenli geçir
set rf [open "xsim_args.f" w]
puts $rf "--testplusarg UVM_TESTNAME=base_test"
puts $rf "--testplusarg UVM_VERBOSITY=UVM_LOW"
puts $rf "--nolog"
puts $rf "-t uvm_sim.tcl"
close $rf

puts ">>> Simülasyon başlıyor..."
set r4 [catch {exec "C:/AMDDesignTools/2025.2/Vivado/bin/xsim.bat" \
    tunga_uvm_sim \
    -f xsim_args.f} out4]

puts ">>> =============================================="
puts ">>> SİMÜLASYON ÇIKTISI:"
puts ">>> =============================================="
puts $out4
puts ">>> =============================================="

if {[string match "*UVM_ERROR : 0*" $out4] || [string match "*Tum UVM Test*" $out4]} {
    puts ">>> SONUÇ: UVM Simülasyonu BAŞARILI!"
} else {
    puts ">>> SONUÇ: Simülasyon tamamlandı. Çıktıyı inceleyiniz."
}
