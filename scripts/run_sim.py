#!/usr/bin/env python3
import os
import subprocess
import sys
import glob

# Terminal renk kodlari (Juri ciktilari icin)
GREEN = '\033[92m'
RED = '\033[91m'
RESET = '\033[0m'

def run_simulation():
    print("=== Teknofest 2026 CV32E40P UVM Otomasyon Betiği ===\n")
    
    # Proje yollarini dinamik olarak bul
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    
    rtl_dir = os.path.join(project_root, "rtl")
    tb_dir = os.path.join(project_root, "tb")
    sim_dir = os.path.join(project_root, "sim")
    
    # sim klasoru yoksa olustur
    os.makedirs(sim_dir, exist_ok=True)

    # RTL dosyalarini bul (.v ve .sv)
    rtl_files = glob.glob(os.path.join(rtl_dir, "*.v")) + glob.glob(os.path.join(rtl_dir, "*.sv"))
    tb_cpp = os.path.join(tb_dir, "sim_main.cpp")
    
    if not rtl_files:
        print(f"{RED}Uyari: rtl/ klasorunde RTL dosyasi bulunamadi. Derleme hata verebilir.{RESET}")

    # ==========================================
    # 1. ADIM: Verilator ile Derleme (Compile)
    # ==========================================
    print("[1/2] Verilator ile derleme başlatılıyor...")
    
    # top module adini burada "top" varsayiyoruz, farkliysa asagidaki satiri duzenleyin.
    top_module_isim = "top"
    
    verilator_cmd = [
        "verilator",
        "-Wall",
        "-Wno-lint",     # Lint uyarilarini bastir
        "-Wno-fatal",    # Uyarilari hataya cevirmeyi engelle
        "--cc",          # C++ ciktisi uret
        "--exe",         # Calistirilabilir dosya (executable) uret
        "--build",       # Otomatik derle
        "-Mdir", os.path.join(sim_dir, "obj_dir"), # Cikti dizini
        "--top-module", top_module_isim
    ]
    
    verilator_cmd.extend(rtl_files)
    verilator_cmd.append(tb_cpp)
    
    try:
        subprocess.run(verilator_cmd, cwd=project_root, check=True)
        print("-> Derleme Başarılı.\n")
    except subprocess.CalledProcessError:
        print(f"\n{RED}Derleme Hatası! RTL veya Testbench kodlarinizi kontrol edin.{RESET}")
        sys.exit(1)
    except FileNotFoundError:
        print(f"\n{RED}Hata: 'verilator' komutu bulunamadi. Sisteme kurulu oldugundan emin olun.{RESET}")
        sys.exit(1)

    # ==========================================
    # 2. ADIM: Simülasyonu Çalıştırma (Execute)
    # ==========================================
    print(f"[2/2] Simülasyon {top_module_isim} modülü için yürütülüyor...\n")
    print("-" * 50)
    
    # Uretilen executable yolu
    exe_path = os.path.join(sim_dir, "obj_dir", f"V{top_module_isim}")
    if os.name == 'nt' and os.path.exists(exe_path + ".exe"):
        exe_path += ".exe"
        
    if not os.path.exists(exe_path):
        print(f"{RED}Hata: Calistirilabilir dosya bulunamadi: {exe_path}{RESET}")
        sys.exit(1)

    has_error = False
    
    # Executable'i calistir ve stdout'u anlik oku
    process = subprocess.Popen(
        [exe_path], 
        stdout=subprocess.PIPE, 
        stderr=subprocess.STDOUT,
        text=True,
        cwd=sim_dir
    )
    
    for line in process.stdout:
        print(line, end="") # Simulasyon loglarini konsola oldugu gibi bas
        
        # Test durumunu yakalamak icin keyword arama
        upper_line = line.upper()
        if "UVM_ERROR" in upper_line or "UVM_FATAL" in upper_line or "FAIL" in upper_line:
            has_error = True

    process.wait()
    print("-" * 50)
    
    # ==========================================
    # 3. ADIM: Sonuclari Degerlendirme
    # ==========================================
    if has_error:
        print(f"\n{RED}>>> TEST FAILED <<<{RESET}\n")
    else:
        print(f"\n{GREEN}>>> TEST PASSED <<<{RESET}\n")

if __name__ == "__main__":
    run_simulation()
