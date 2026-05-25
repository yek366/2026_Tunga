#!/usr/bin/env python3
import os
import subprocess
import sys
import glob

# Terminal renk kodlari
GREEN = '\033[92m'
RED = '\033[91m'
RESET = '\033[0m'

def run_simulation():
    print("=== Teknofest 2026 CV32E40P UVM Otomasyon Betiği (DSim) ===\n")
    
    # Proje yollarini bul
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    
    rtl_dir = os.path.join(project_root, "rtl")
    tb_dir = os.path.join(project_root, "tb")
    sim_dir = os.path.join(project_root, "sim")
    
    os.makedirs(sim_dir, exist_ok=True)

    # Dosyalari topla
    rtl_files = glob.glob(os.path.join(rtl_dir, "*.v")) + glob.glob(os.path.join(rtl_dir, "*.sv"))
    tb_sv = os.path.join(tb_dir, "tb_tunga_soc.sv")
    
    if not os.path.exists(tb_sv):
        print(f"{RED}Hata: Yuşa'nın yazdığı testbench dosyası ({tb_sv}) bulunamadı!{RESET}")
        sys.exit(1)

    print("[1/1] Metrics DSim ile Derleme ve Simülasyon yürütülüyor...\n")
    print("-" * 50)
    
    top_module_isim = "tb_tunga_soc"
    
    # DSim komutu (Tek adimda derleme ve kosturma)
    dsim_cmd = [
        "dsim",
        "-top", top_module_isim,
        "-l", "dsim_run.log" # Loglari sim/ altinda tut
    ]
    
    dsim_cmd.extend(rtl_files)
    dsim_cmd.append(tb_sv)
    
    has_error = False
    
    try:
        # Executable'i calistir ve stdout'u anlik oku
        process = subprocess.Popen(
            dsim_cmd, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.STDOUT,
            text=True,
            cwd=sim_dir
        )
        
        for line in process.stdout:
            print(line, end="") # Loglari konsola bas
            
            # Hata kontrolu
            upper_line = line.upper()
            if "UVM_ERROR" in upper_line or "UVM_FATAL" in upper_line or "FAIL" in upper_line or "ERROR:" in upper_line:
                has_error = True

        process.wait()
        
        if process.returncode != 0:
            has_error = True
            
    except FileNotFoundError:
        print(f"\n{RED}Hata: 'dsim' komutu bulunamadi. Metrics DSim aracinin yuklu ve PATH'te oldugundan emin olun.{RESET}")
        sys.exit(1)

    print("-" * 50)
    
    # Sonuclari Degerlendirme
    if has_error:
        print(f"\n{RED}>>> TEST FAILED <<<{RESET}\n")
    else:
        print(f"\n{GREEN}>>> TEST PASSED <<<{RESET}\n")

if __name__ == "__main__":
    run_simulation()
