#!/usr/bin/env python3
import os
import subprocess
import sys
import glob

def main():
    print("=== Sistem Seviyesi Entegrasyon ve Boot Testi Otomasyonu ===\n")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    
    sw_dir = os.path.join(project_root, "sw")
    sim_dir = os.path.join(project_root, "sim")
    rtl_dir = os.path.join(project_root, "rtl")
    tb_dir = os.path.join(project_root, "tb")
    
    os.makedirs(sim_dir, exist_ok=True)
    os.makedirs(sw_dir, exist_ok=True)
    
    main_c = os.path.join(sw_dir, "main.c")
    link_ld = os.path.join(sw_dir, "link.ld")
    elf_file = os.path.join(sw_dir, "firmware.elf")
    hex_file = os.path.join(sim_dir, "flash_preload.hex")
    
    # ----------------------------------------------------------------
    # 1. RISC-V GCC İle C Kodunun Derlenmesi
    # ----------------------------------------------------------------
    print("[1/3] RISC-V GCC ile C test yazilimi derleniyor...")
    gcc_cmd = [
        "riscv32-unknown-elf-gcc",
        "-march=rv32imc",
        "-mabi=ilp32",
        "-nostartfiles",
        "-T", link_ld,
        main_c,
        "-o", elf_file
    ]
    
    try:
        subprocess.run(gcc_cmd, check=True)
        print("-> firmware.elf uretildi.")
    except FileNotFoundError:
        print("\033[91mHATA: 'riscv32-unknown-elf-gcc' bulunamadi. PATH'te kurulu oldugundan emin olun.\033[0m")
        sys.exit(1)
    except subprocess.CalledProcessError:
        print("\033[91mHATA: Derleme basarisiz!\033[0m")
        sys.exit(1)
        
    # ----------------------------------------------------------------
    # 2. ELF Dosyasının Bellek Modeli Uyumlu HEX'e Çevrilmesi
    # ----------------------------------------------------------------
    print("\n[2/3] ELF dosyasi Micron QSPI Flash uyumlu HEX formatina cevriliyor...")
    objcopy_cmd = [
        "riscv32-unknown-elf-objcopy",
        "-O", "verilog",
        elf_file,
        hex_file
    ]
    subprocess.run(objcopy_cmd, check=True)
    print("-> flash_preload.hex uretildi.")
    
    # ----------------------------------------------------------------
    # 3. Metrics DSim ile Ko-Simülasyon ve Boot Analizi
    # ----------------------------------------------------------------
    print("\n[3/3] Metrics DSim ile Simulasyon Baslatiliyor...")
    
    dsim_cmd = [
        "dsim",
        "-top", "tb_system_integration",
        "+define+FLASH_INIT_FILE=\"" + hex_file + "\"",
        os.path.join(tb_dir, "tb_system_integration.sv")
    ]
    
    # Mevcut RTL dosyalari listeye dahil edilir
    rtl_files = glob.glob(os.path.join(rtl_dir, "*.v")) + glob.glob(os.path.join(rtl_dir, "*.sv"))
    dsim_cmd.extend(rtl_files)
    
    try:
        process = subprocess.Popen(
            dsim_cmd, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.STDOUT,
            text=True,
            cwd=sim_dir
        )
        
        boot_verified = False
        print("-" * 50)
        
        # Self-Checking Mekanizmasi: UART stdout icinden yazi yakalama
        for line in process.stdout:
            print(line, end="") # DSim ciktilarini canli konsola bas
            
            if "SYSTEM BOOT OK" in line:
                boot_verified = True
                
        process.wait()
        print("-" * 50)
        
        if boot_verified:
            print("\033[92m>>> FULL SYSTEM BOOT VERIFIED <<<\033[0m\n")
        else:
            print("\033[91m>>> HATA: UART üzerinden 'SYSTEM BOOT OK' yakalanamadi! Boot sirasinda hata var. <<<\033[0m\n")
            sys.exit(1)
            
    except FileNotFoundError:
        print("\033[91mHATA: 'dsim' komutu bulunamadi!\033[0m")
        sys.exit(1)

if __name__ == "__main__":
    main()
