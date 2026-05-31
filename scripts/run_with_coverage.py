#!/usr/bin/env python3
import os
import subprocess
import sys
import glob

def main():
    print("=== Metrics DSim - Coverage Raporlama Otomasyonu ===\n")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    
    sim_dir = os.path.join(project_root, "sim")
    rtl_dir = os.path.join(project_root, "rtl")
    tb_dir = os.path.join(project_root, "tb")
    
    os.makedirs(sim_dir, exist_ok=True)
    
    # ----------------------------------------------------------------
    # 1. '-cover' Argümanı ile Simülasyon Koşumu
    # ----------------------------------------------------------------
    # b: branch, e: expression, s: statement, t: toggle coverage
    dsim_cmd = [
        "dsim",
        "-top", "tb_system_integration",
        "-cover", "b,e,s,t",
        "-dump-cov", "coverage_data.ucdb", # UCDB formatında veritabanı
        os.path.join(tb_dir, "tb_system_integration.sv")
    ]
    
    sv_files = glob.glob(os.path.join(rtl_dir, "*.v")) + glob.glob(os.path.join(rtl_dir, "*.sv"))
    sv_files += glob.glob(os.path.join(tb_dir, "*.sv"))
    dsim_cmd.extend(sv_files)
    
    print("[1/2] DSim ile simülasyon ve kapsam (coverage) verisi toplamasi baslatiliyor...")
    try:
        subprocess.run(dsim_cmd, cwd=sim_dir, check=True)
        print("-> Simulasyon tamamlandi ve 'coverage_data.ucdb' veritabani olusturuldu.")
    except FileNotFoundError:
        print("\033[91mHATA: 'dsim' komutu bulunamadi. PATH'i kontrol edin.\033[0m")
        sys.exit(1)
    except subprocess.CalledProcessError:
        print("\033[91mHATA: Simulasyon sirasinda hata olustu.\033[0m")
        sys.exit(1)
        
    # ----------------------------------------------------------------
    # 2. Coverage Raporunun Üretilmesi (HTML ve Text formatında)
    # ----------------------------------------------------------------
    print("\n[2/2] HTML ve Metin Kapsam Raporu (Coverage Report) Uretiliyor...")
    
    report_cmd = [
        "dsim",
        "-cov-merge", "coverage_data.ucdb",
        "-cov-report-html", "html_report",
        "-cov-report-txt", "coverage_summary.txt"
    ]
    
    try:
        subprocess.run(report_cmd, cwd=sim_dir, check=True)
        print("\n\033[92m>>> COVERAGE RAPORU BASARIYLA OLUSTURULDU <<<\033[0m")
        print("-> HTML Rapor Dizini: sim/html_report/index.html")
        print("-> Ozet Metin Dosyasi: sim/coverage_summary.txt\n")
    except subprocess.CalledProcessError:
        print("\033[91mHATA: Rapor uretimi basarisiz!\033[0m")
        sys.exit(1)

if __name__ == "__main__":
    main()
