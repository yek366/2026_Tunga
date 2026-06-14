#!/usr/bin/env python3
# ============================================================
# Script  : extract_weights.py
# Project : TUNGA SoC — TEKNOFEST 2026
# Author  : Ali Salih Yıldırım
# Date    : 2026-05-03
# Desc    : TFLite Micro "Tiny Conv" modelinden INT8 ağırlıkları
#           çıkarır ve Verilog $readmemh uyumlu .mem dosyaları üretir.
#           Çıktı dosyaları weights/ klasörüne yazılır.
# Kullanım:
#   pip install numpy flatbuffers
#   python3 extract_weights.py --model path/to/tiny_conv_int8.tflite
# ============================================================

import argparse
import struct
import os
import numpy as np

# Çıktı dizini
WEIGHTS_DIR = os.path.join(os.path.dirname(__file__), "../../weights")

# ---- Model boyutları (Tiny Conv şartnamesinden) ----
DW_NUM_FILTERS = 8
DW_KERNEL_H    = 10
DW_KERNEL_W    = 8
DW_WEIGHT_SIZE = DW_NUM_FILTERS * DW_KERNEL_H * DW_KERNEL_W  # 640 byte

FC_OUTPUTS     = 4
FC_INPUTS      = 4000
FC_WEIGHT_SIZE = FC_OUTPUTS * FC_INPUTS  # 16000 byte
FC_BIAS_SIZE   = FC_OUTPUTS              # 4 × INT32 = 16 byte


def write_mem_file(filename: str, data: np.ndarray, bits: int = 8):
    """
    Verilog $readmemh uyumlu .mem dosyası yazar.
    bits=8  → her satır 2 hex karakter (INT8)
    bits=32 → her satır 8 hex karakter (INT32)
    """
    os.makedirs(WEIGHTS_DIR, exist_ok=True)
    path = os.path.join(WEIGHTS_DIR, filename)
    fmt = f"{{:0{bits // 4}X}}"
    with open(path, "w") as f:
        for val in data.flatten():
            if bits == 8:
                f.write(fmt.format(int(val) & 0xFF) + "\n")
            elif bits == 32:
                f.write(fmt.format(int(val) & 0xFFFFFFFF) + "\n")
    print(f"[OK] {path} yazıldı ({len(data.flatten())} eleman)")


def write_test_input(filename: str, data: np.ndarray):
    """Giriş test vektörünü .mem dosyasına yazar."""
    write_mem_file(filename, data, bits=8)


def extract_from_tflite(model_path: str):
    """
    TFLite flatbuffer'dan tensor verilerini çıkarır.
    flatbuffers paketi gereklidir: pip install flatbuffers
    """
    try:
        import flatbuffers
        from flatbuffers import builder as flatbuffers_builder
    except ImportError:
        print("[HATA] flatbuffers paketi bulunamadı: pip install flatbuffers")
        return

    with open(model_path, "rb") as f:
        model_data = f.read()

    # TFLite flatbuffer parse (basit offset tabanlı yaklaşım)
    # Gerçek uygulama için tflite.schema_fb kullanılabilir
    # TODO: flatbuffers schema ile tam parse implementasyonu
    print(f"[INFO] Model yüklendi: {len(model_data)} byte")
    print("[TODO] Flatbuffer parse implementasyonu tamamlanacak.")
    print("       Şimdilik dummy veriler üretiliyor.")

    # ---- Dummy veri üretimi (test için) ----
    # Gerçek modelden çıkarılana kadar küçük sabit değerler kullan
    dw_weights = np.zeros(DW_WEIGHT_SIZE, dtype=np.int8)
    fc_weights = np.zeros(FC_WEIGHT_SIZE, dtype=np.int8)
    fc_bias    = np.zeros(FC_BIAS_SIZE,   dtype=np.int32)

    # Identity benzeri: ilk filtre köşegen 1
    dw_weights[0] = 1

    write_mem_file("tiny_conv_dw_weights.mem",  dw_weights, bits=8)
    write_mem_file("tiny_conv_fc_weights.mem",  fc_weights, bits=8)
    write_mem_file("tiny_conv_fc_bias.mem",     fc_bias,    bits=32)
    print("[INFO] Ağırlık dosyaları weights/ klasörüne yazıldı.")


def generate_test_inputs():
    """
    Testbench için referans giriş vektörleri üretir.
    Gerçek test: TFLite çalıştırıp giriş/çıkış kaydet.
    """
    rng = np.random.default_rng(seed=42)

    # Sıfır vektörü → beklenen sınıf: 0 (silence)
    silence_input = np.zeros(1960, dtype=np.int8)
    write_test_input("test_input_silence.mem", silence_input)

    # Rastgele vektör (gerçek ses yerine placeholder)
    yes_input = rng.integers(-64, 64, size=1960, dtype=np.int8)
    write_test_input("test_input_yes.mem", yes_input)

    no_input = rng.integers(-64, 64, size=1960, dtype=np.int8)
    write_test_input("test_input_no.mem", no_input)

    print("[INFO] Test giriş dosyaları weights/ klasörüne yazıldı.")
    print("[UYARI] Gerçek ses verileri TFLite Micro referans implementasyonundan")
    print("        alınmalı ve beklenen çıktılar karşılaştırma için kaydedilmeli.")


def main():
    parser = argparse.ArgumentParser(
        description="TFLite Tiny Conv INT8 ağırlıklarını .mem formatına dönüştür"
    )
    parser.add_argument("--model", type=str, default=None,
                        help="TFLite model dosyası (.tflite)")
    parser.add_argument("--test-inputs", action="store_true",
                        help="Test giriş vektörlerini üret")
    args = parser.parse_args()

    if args.model:
        extract_from_tflite(args.model)
    else:
        print("[INFO] --model belirtilmedi, dummy ağırlıklar üretiliyor.")
        dw_weights = np.zeros(DW_WEIGHT_SIZE, dtype=np.int8)
        fc_weights = np.zeros(FC_WEIGHT_SIZE, dtype=np.int8)
        fc_bias    = np.zeros(FC_BIAS_SIZE,   dtype=np.int32)
        write_mem_file("tiny_conv_dw_weights.mem",  dw_weights, bits=8)
        write_mem_file("tiny_conv_fc_weights.mem",  fc_weights, bits=8)
        write_mem_file("tiny_conv_fc_bias.mem",     fc_bias,    bits=32)

    if args.test_inputs:
        generate_test_inputs()


if __name__ == "__main__":
    main()
