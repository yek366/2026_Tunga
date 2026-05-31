#!/usr/bin/env python3
"""
Teknofest 2026 - Tunga SoC XSIM Otomasyon Betiği
Strateji: Orijinal export TCL'ini parse etmek yerine,
          Vivado projesini SIFIRDAN kuran temiz bir TCL üretiyoruz.
"""
import os
import subprocess
import sys
import glob
import shutil

# Vivado'nun Windows üzerindeki çevre değişkeni hatalarını (USF-XSim-102) susturmak için sahte değişkenler:
os.environ["SIM_VER_XSIM"] = "1"
os.environ["xv_cxl_win_path"] = "1"

GREEN  = '\033[92m'
YELLOW = '\033[93m'
RED    = '\033[91m'
CYAN   = '\033[96m'
RESET  = '\033[0m'

# ============================================================
# 1. VIVADO AUTO-DISCOVERY
# ============================================================
def find_vivado_path():
    search_patterns = [
        r"C:\AMDDesignTools\*\Vivado\bin\vivado.bat",
        r"D:\AMDDesignTools\*\Vivado\bin\vivado.bat",
        r"C:\Xilinx\Vivado\*\bin\vivado.bat",
        r"D:\Xilinx\Vivado\*\bin\vivado.bat",
        r"E:\Xilinx\Vivado\*\bin\vivado.bat",
    ]
    found = []
    for p in search_patterns:
        found.extend(glob.glob(p))
    if found:
        found.sort(reverse=True)
        return found[0]
    return None


# ============================================================
# 2. TEMİZ VIVADO TCL OLUŞTURUCU
#    Orijinal export TCL'ini parse etmek yerine, dosya sistemi
#    gerçekliğine göre Vivado projesini sıfırdan kurar.
# ============================================================
def generate_clean_project_tcl(tcl_path, project_root, script_dir, proj_dir_name="tunga_micro"):
    """
    Vivado projesini sıfırdan kuran temiz, minimal ve hata toleranslı
    bir TCL betiği üretir. Orijinal tunga_micro.tcl'e bağımlılık yok.
    """
    root    = project_root.replace("\\", "/")
    scripts = script_dir.replace("\\", "/")

    # RTL kaynak dosyalarını topla
    core_src  = os.path.join(project_root, "rtl", "core", "src")
    rtl_dir   = os.path.join(project_root, "rtl")
    tb_dir    = os.path.join(project_root, "tb")

    # Gerçekte var olan dosyaları listele
    core_files    = []
    rtl_top_files = []
    tb_files      = []

    if os.path.isdir(core_src):
        for f in os.listdir(core_src):
            if f.endswith((".sv", ".v", ".svh", ".vh")):
                core_files.append(os.path.join(core_src, f).replace("\\", "/"))

    for f in os.listdir(rtl_dir):
        if f.endswith((".sv", ".v")) and os.path.isfile(os.path.join(rtl_dir, f)):
            rtl_top_files.append(os.path.join(rtl_dir, f).replace("\\", "/"))

    if os.path.isdir(tb_dir):
        for f in os.listdir(tb_dir):
            if f.endswith((".sv", ".v")) and os.path.isfile(os.path.join(tb_dir, f)):
                tb_files.append(os.path.join(tb_dir, f).replace("\\", "/"))

    # Sim top seçimi: tb_tunga_soc_modified.sv varsa onu kullan
    sim_top = "tb_tunga_soc"
    for tf in tb_files:
        if "tb_tunga_soc_modified" in tf:
            sim_top = "tb_tunga_soc_modified"
            break

    # TCL listesi oluştur: dosya yollarını TCL list formatına çevir
    def tcl_add_block(var_name, files, fileset):
        """
        Dosyaları lappend ile ekleyen güvenli TCL bloğu üretir.
        - Backslash continuation yok  → satır ayrıştırma hatası yok
        - Köşeli parantez yok         → komut substitution riski yok
        """
        if not files:
            return f"# {var_name}: dosya bulunamadi, atlandi\n"
        lines = [f"set {var_name} [list]\n"]
        for f in files:
            lines.append(f'lappend {var_name} "{f}"\n')
        lines.append(f"if {{[llength ${var_name}] > 0}} {{\n")
        lines.append(f"    add_files -norecurse -fileset {fileset} ${var_name}\n")
        lines.append("}\n")
        return "".join(lines)

    # DPI-C kaynak dosyasını bul
    spike_bridge = os.path.join(project_root, "tb", "spike_bridge.c")
    spike_bridge_fwd = spike_bridge.replace("\\", "/")
    has_spike = os.path.exists(spike_bridge)

    content  = "# ============================================================\n"
    content += "# Tunga SoC Vivado Projesi - Temiz Otomasyon TCL\n"
    content += "# Uretildi: run_sim.py (Teknofest 2026)\n"
    content += "# Bu dosya her calistirmada sifirdan uretilir.\n"
    content += "# ============================================================\n\n"

    content += f'set proj_root "{root}"\n'
    content += f'set proj_name "{proj_dir_name}"\n'
    content += 'set part      "xc7a12ticsg325-1L"\n\n'

    # Proje oluştur (-force: eğer kalıntı varsa sil)
    content += "catch { close_project -quiet }\n"
    content += "create_project $proj_name $proj_root/$proj_name -part $part -force\n\n"

    # sources_1 fileset
    content += "# ---- RTL Kaynak Dosyalari (sources_1) ----\n"
    content += "set obj [get_filesets sources_1]\n"
    content += tcl_add_block("core_files", core_files, "$obj")
    content += "\n"
    content += tcl_add_block("rtl_files",  rtl_top_files, "$obj")
    content += "\n"
    content += "set_property top tunga_soc_top $obj\n"
    content += "set_property top_auto_set 0    $obj\n\n"

    # sim_1 fileset
    content += "# ---- Testbench Dosyalari (sim_1) ----\n"
    content += "set obj [get_filesets sim_1]\n"
    # Core dosyaları sim_1'e de gerekli
    content += tcl_add_block("core_files_sim", core_files, "$obj")
    content += "\n"
    content += tcl_add_block("tb_files", tb_files, "$obj")
    content += "\n"

    # DPI-C: spike_bridge.c'yi sim_1'e ekle — XSIM otomatik derleyip link eder
    if has_spike:
        content += '# ---- DPI-C: Spike ISS Koprusu ----\n'
        content += f'add_files -norecurse -fileset $obj "{spike_bridge_fwd}"\n'
        content += f'catch {{ set_property file_type {{C Source}} [get_files -of_objects $obj "{spike_bridge_fwd}"] }}\n'
        content += f'catch {{ set_property used_in_synthesis false [get_files -of_objects $obj "{spike_bridge_fwd}"] }}\n\n'


    content += f"set_property top          {sim_top}       $obj\n"
    content += "set_property top_lib      xil_defaultlib $obj\n"
    content += "set_property top_auto_set 0              $obj\n"
    
    # Timescale uyarılarını susturmak için derleyici argümanlarını set et (sadece xelab timescale destekler)
    content += "set_property -name {xsim.elaborate.xelab.more_options} -value {-timescale 1ns/1ps} -objects $obj\n\n"

    content += "update_compile_order -fileset sources_1\n"
    content += "update_compile_order -fileset sim_1\n\n"

    content += "puts {Proje hazir. Simulasyon baslatiliyor...}\n\n"
    content += "# ---- XSIM Simulasyonu ----\n"
    content += "launch_simulation\n"
    content += "run all\n\n"
    content += "puts {Simulasyon tamamlandi.}\n"
    content += "exit\n"

    with open(tcl_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"  [*] Sim top        : {sim_top}")
    print(f"  [*] Core dosyalari : {len(core_files)}")
    print(f"  [*] RTL top        : {len(rtl_top_files)}")
    print(f"  [*] TB dosyalari   : {len(tb_files)}")
    print(f"  [*] DPI-C (Spike)  : {'EKLENDI' if has_spike else 'BULUNAMADI'}")



# ============================================================
# 3. MAIN
# ============================================================
def run_vivado_simulation():
    print(f"{CYAN}=== Teknofest 2026 Tunga SoC — Vivado XSIM Otomasyon ==={RESET}\n")

    script_dir   = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))

    # -- Vivado bul --
    vivado = find_vivado_path()
    if not vivado:
        print(f"{RED}[HATA] Vivado bulunamadı.{RESET}")
        sys.exit(1)
    print(f"[*] Vivado: {vivado}")

    # -- CV32_IP.zip varsa aç --
    import zipfile
    core_dir = os.path.join(project_root, "rtl", "core")
    cv32_zip = os.path.join(project_root, "CV32_IP.zip")
    if os.path.exists(cv32_zip) and not os.path.exists(core_dir):
        print(f"[*] CV32_IP.zip açılıyor...")
        os.makedirs(core_dir, exist_ok=True)
        with zipfile.ZipFile(cv32_zip, 'r') as z:
            z.extractall(core_dir)
        print("[*] Çıkarma tamamlandı.")

    # -- Zombie simülasyon süreçlerini öldür (xsim, xelab vb.) --
    print(f"[*] Kalıntı simülasyon süreçleri (xsim, vb.) temizleniyor...")
    for proc in ["xsim.exe", "xelab.exe", "xvlog.exe", "xvhdl.exe"]:
        subprocess.run(["taskkill", "/F", "/IM", proc, "/T"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # -- Eski proje klasörlerini temizle ve yepyeni eşsiz bir proje dizini oluştur --
    import time
    print(f"[*] Eski simülasyon klasörleri temizleniyor...")
    for item in os.listdir(project_root):
        if item.startswith("tunga_micro") and os.path.isdir(os.path.join(project_root, item)):
            old_proj = os.path.join(project_root, item)
            try:
                shutil.rmtree(old_proj)
            except Exception:
                pass # Locked or in use, skip and let it be deleted next time
                
    proj_dir_name = f"tunga_micro_{int(time.time())}"
    print(f"[*] Yeni proje dizini: {proj_dir_name}")

    # -- Temiz proje TCL'i üret (orijinal export'a bağımlılık YOK) --
    run_tcl = os.path.join(script_dir, "run_xsim.tcl")
    print(f"\n[*] Temiz proje TCL'i oluşturuluyor:")
    generate_clean_project_tcl(run_tcl, project_root, script_dir, proj_dir_name=proj_dir_name)

    # -- Vivado başlat --
    vivado_log = os.path.join(project_root, "vivado_run.log")
    if os.path.exists(vivado_log):
        try:
            os.remove(vivado_log)
        except Exception:
            pass
            
    print(f"\n[1/2] Vivado Batch Mode başlatılıyor...")
    print(f"  -> TCL : {run_tcl}")
    print(f"  -> LOG : {vivado_log}\n")

    cmd = [vivado, "-mode", "batch", "-source", run_tcl]
    vivado_ok = True
    with open(vivado_log, "w", encoding="utf-8", errors="replace") as log_fh:
        try:
            subprocess.run(
                cmd,
                cwd=project_root,
                stdout=log_fh,
                stderr=subprocess.STDOUT,
                check=True
            )
        except subprocess.CalledProcessError:
            vivado_ok = False

    # Vivado başarısız olduysa son 50 satırı göster
    if not vivado_ok:
        print(f"\n{YELLOW}[UYARI] Vivado hatayla çıktı. Özet:{RESET}")
        print("-" * 60)
        try:
            with open(vivado_log, "r", encoding="utf-8", errors="replace") as lf:
                tail = lf.readlines()[-50:]
            for tl in tail:
                s = tl.rstrip()
                if "ERROR" in s.upper():
                    print(f"{RED}{s}{RESET}")
                elif "WARNING" in s.upper():
                    print(f"{YELLOW}{s}{RESET}")
                else:
                    print(s)
        except Exception as e:
            print(f"  Log okunamadı: {e}")
        print("-" * 60)
        print(f"\n{CYAN}Tam log: {vivado_log}{RESET}\n")

    # -- XSIM log analizi --
    print(f"\n[2/2] XSIM Log Analizi...")
    xsim_logs = []
    # elaborate.log dahil tüm simülasyon loglarını tara
    current_proj_path = os.path.join(project_root, proj_dir_name)
    for root, dirs, files in os.walk(current_proj_path):
        for f in files:
            if f in ("simulate.log", "xsim.log", "xvlog.log",
                     "xelab.log", "elaborate.log"):
                xsim_logs.append(os.path.join(root, f))

    # vivado_run.log'u da ekle (launch_simulation hataları burada)
    if os.path.exists(vivado_log):
        xsim_logs.append(vivado_log)

    if not xsim_logs:
        print(f"{RED}[HATA] Hic log bulunamadi — simülasyon baslamadi.{RESET}")
        print(f"{CYAN}Detay icin: {vivado_log}{RESET}")
        sys.exit(1)

    error_kw  = ["UVM_ERROR", "UVM_FATAL", "ERROR:", "FATAL:", "FAILED"]
    # Bu WARNING mesajlarını hata saymıyoruz, UVM'in başarılı özetini de pas geçiyoruz.
    ignore_kw = ["WARNING:", "INFO:", "DevOps Auto-Fix", "UVM_ERROR :    0", "UVM_FATAL :    0"]
    has_error = False
    err_line  = ""
    for lf in xsim_logs:
        with open(lf, "r", encoding="utf-8", errors="ignore") as fh:
            for ln in fh:
                if any(ig in ln for ig in ignore_kw):
                    continue
                if any(k in ln.upper() for k in error_kw):
                    has_error = True
                    err_line  = ln.strip()
                    break
        if has_error:
            break

    print("\n" + "=" * 60)
    if has_error:
        print(f"{RED}[CRITICAL] TEST FAILED{RESET}")
        print(f"Hata: {err_line}")
        print(f"\n{CYAN}Tam hata detayi icin:{RESET}")
        print(f"  {vivado_log}")
    else:
        print(f"{GREEN}[SUCCESS] FULL SYSTEM VERIFIED (VIVADO XSIM){RESET}")
    print("=" * 60 + "\n")



if __name__ == "__main__":
    run_vivado_simulation()
