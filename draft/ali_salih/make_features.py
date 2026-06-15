#!/usr/bin/env python3
# ============================================================
# make_features.py — Resmi micro_speech ses verisinden (yes/no/silence wav)
# REFERANS 1960-int8 feature vektoru cikarir (modelin KENDI audio_preprocessor'u
# ile) ve tiny_conv interpreter'in dogru sinifladigini DOGRULAR.
# Cikti: weights/feat_<label>.mem  (RTL NPU testi icin gercek ses girisi)
#
# Pipeline (kanonik micro_speech): 1 sn @16kHz = 16000 int16 ->
#   49 pencere (480 sample=30ms, stride 320=20ms) -> her pencere audio_preprocessor
#   -> 40 int8 feature -> concat 1960 -> tiny_conv model -> sinif.
# Calistir: ~/tunga_venv/bin/python make_features.py
# ============================================================
import os
import numpy as np
from tflite_micro.python.tflite_micro.runtime import Interpreter

HERE = os.path.dirname(__file__)
T = os.path.join(HERE, "tflite")
WEIGHTS = os.path.normpath(os.path.join(HERE, "..", "..", "weights"))

WIN, STRIDE, NFRAME, NFEAT = 480, 320, 49, 40   # micro_speech standart
LBL = {0: "silence", 1: "unknown", 2: "yes", 3: "no"}

def read_wav_int16(path):
    raw = open(path, "rb").read()
    # standart 44-bayt PCM WAV header
    return np.frombuffer(raw[44:], dtype="<i2")

def extract(pp, samples):
    feats = np.zeros(NFRAME * NFEAT, dtype=np.int8)
    for i in range(NFRAME):
        win = samples[i*STRIDE : i*STRIDE + WIN].astype(np.int16).reshape(1, WIN)
        pp.set_input(win, 0)
        pp.invoke()
        feats[i*NFEAT:(i+1)*NFEAT] = pp.get_output(0).reshape(-1).astype(np.int8)
    return feats

def main():
    pp = Interpreter.from_file(os.path.join(T, "audio_pp_int8.tflite"))
    md = Interpreter.from_file(os.path.join(T, "micro_speech_quantized.tflite"))
    os.makedirs(WEIGHTS, exist_ok=True)

    cases = [("yes", "yes_1000ms.wav", 2),
             ("no",  "no_1000ms.wav",  3),
             ("silence", "silence_1000ms.wav", 0)]
    allok = True
    for label, wav, expect in cases:
        s = read_wav_int16(os.path.join(T, wav))
        feats = extract(pp, s)
        md.set_input(feats.reshape(1, 1960), 0)
        md.invoke()
        out = md.get_output(0).reshape(-1)
        cls = int(np.argmax(out))
        ok = (cls == expect)
        allok &= ok
        print(f"{label:8s} -> interpreter sinif={cls} ({LBL[cls]}) beklenen={expect} "
              f"{'OK' if ok else 'XXX'}  logits={list(map(int,out))}")
        with open(os.path.join(WEIGHTS, f"feat_{label}.mem"), "w") as f:
            for v in feats:
                f.write(f"{int(np.uint8(v)):02X}\n")
    print(">>> Feature cikarma + sinif dogrulama:", "GECTI" if allok else "BASARISIZ")

if __name__ == "__main__":
    main()
