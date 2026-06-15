#!/usr/bin/env python3
# compare_traces.py: Spike ISS komut izi (trace) ile RTL simülasyon izini karşılaştırır.
import sys
import os

def parse_spike_log(filepath):
    """Spike log dosyasından PC ve komutları (instruction) çıkartır."""
    trace = []
    if not os.path.exists(filepath):
        print(f"[HATA] Spike log dosyası bulunamadı: {filepath}")
        return trace

    with open(filepath, 'r') as f:
        for line in f:
            # Örnek Spike satırı: core   0: 0x00001000 (0x00000013) nop
            if "core" in line and "0x" in line:
                parts = line.split()
                try:
                    pc = parts[2]
                    instr = parts[3].strip('()')
                    trace.append((pc, instr))
                except IndexError:
                    continue
    return trace

def parse_rtl_log(filepath):
    """RTL log dosyasından PC ve komutları çıkartır."""
    trace = []
    if not os.path.exists(filepath):
        print(f"[HATA] RTL log dosyası bulunamadı: {filepath}")
        return trace

    with open(filepath, 'r') as f:
        for line in f:
            # Örnek RTL satırı: Time: 100ns, PC: 00001000, Instr: 00000013
            if "PC:" in line:
                parts = line.split(',')
                try:
                    pc = "0x" + parts[1].split(':')[1].strip()
                    instr = "0x" + parts[2].split(':')[1].strip()
                    trace.append((pc, instr))
                except IndexError:
                    continue
    return trace

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Kullanım: python compare_traces.py <spike_log_dosyasi> <rtl_log_dosyasi>")
        sys.exit(1)

    spike_trace = parse_spike_log(sys.argv[1])
    rtl_trace = parse_rtl_log(sys.argv[2])

    if not spike_trace or not rtl_trace:
        print("[HATA] Log dosyalarından biri boş veya okunamadı. Karşılaştırma iptal edildi.")
        sys.exit(1)

    min_len = min(len(spike_trace), len(rtl_trace))
    print(f"Toplam {min_len} adet komut (instruction) karşılaştırılıyor...")

    for i in range(min_len):
        if spike_trace[i] != rtl_trace[i]:
            print(f"==================================================")
            print(f"[HATA] {i+1}. Adımda UYUŞMAZLIK tespit edildi!")
            print(f"Spike ISS (Altın Referans) : PC={spike_trace[i][0]}, Komut={spike_trace[i][1]}")
            print(f"RTL Simülasyon Sonucu      : PC={rtl_trace[i][0]}, Komut={rtl_trace[i][1]}")
            print(f"==================================================")
            sys.exit(1)
            
    print("[BAŞARILI] RTL simülasyonu ile Spike ISS (Altın Referans) birebir eşleşiyor! TEBRİKLER!")
