#!/usr/bin/env python3
# ============================================================
# Script  : npu_golden.py
# Project : TUNGA SoC - TEKNOFEST 2026
# Author  : Ali Salih Yildirim
# Desc    : TUNGA NPU icin BIT-EXACT golden (altin) referans modeli.
#           TFLite Micro "Tiny Conv" INT8 cikarim hattini, donanimin
#           (RTL) uyguladigi TAM integer aritmetigiyle birebir tekrarlar:
#             - DepthwiseConv2D (SAME padding, per-channel requant, fused ReLU)
#             - Flatten
#             - FullyConnected (int32 logits) -> Argmax
#           gemmlowp "MultiplyByQuantizedMultiplier" fixed-point requant'i
#           bit-bit dogru sekilde tekrarlanir (RTL ile ayni sonuc).
#
#           Bu betik AYNI ZAMANDA, RTL self-checking testbench'inin
#           kullandigi AI_MEM agirlik/giris/beklenen-cikti .mem dosyalarini
#           uretir. Boylece golden = tek dogruluk kaynagi.
#
#           Gercek tiny_conv .tflite eline gectiginde, ayni requant cekirdegi
#           ile gercek agirliklar/quant parametreleri yuklenip TFLite
#           interpreter ciktisina karsi %10 dogruluk testi yapilacak (Tier-2).
#
# Kullanim:
#   python3 npu_golden.py --seed 42 --emit
#     -> weights/ altina npu_weights.mem, npu_input.mem, npu_expected.txt yazar
#   python3 npu_golden.py --selftest
#     -> ic tutarlilik testleri
# ============================================================

import argparse
import os
import numpy as np

# ---- Model boyutlari (sartname Tiny Conv) ----
IN_H, IN_W, IN_C = 49, 40, 1          # giris spektrogram 49x40x1
INPUT_SIZE = IN_H * IN_W * IN_C       # 1960
NUM_FILTERS = 8                       # depth_multiplier=8, in_c=1 -> 8 cikis kanali
KER_H, KER_W = 10, 8
STRIDE_H, STRIDE_W = 2, 2
OUT_H, OUT_W = 25, 20                 # SAME padding, stride 2
OUT_C = NUM_FILTERS                   # 8
FC_FLAT = OUT_H * OUT_W * OUT_C       # 4000
FC_OUTPUTS = 4

# ---- SAME padding miktari (sabit, modelden) ----
# total_pad = (O-1)*S + K - I  ;  pad_before = total_pad//2
def _same_pad(I, O, S, K):
    total = max((O - 1) * S + K - I, 0)
    return total // 2  # pad_before
PAD_TOP = _same_pad(IN_H, OUT_H, STRIDE_H, KER_H)   # 4
PAD_LEFT = _same_pad(IN_W, OUT_W, STRIDE_W, KER_W)  # 3

INT8_MIN, INT8_MAX = -128, 127
INT32_MIN, INT32_MAX = -(1 << 31), (1 << 31) - 1

WEIGHTS_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "weights"))

# ============================================================
# AI_MEM agirlik blob yerlesimi (RTL ile BIREBIR ayni olmali)
# Cok-baytli alanlar little-endian. Tum int32 alanlar 4 bayt.
# ============================================================
OFF_HDR      = 0      # byte0=input_zp, byte1=dw_out_zp, byte2=dw_act_min, byte3=dw_act_max
OFF_DW_MULT  = 4      # 8 x int32  -> 4..35
OFF_DW_SHIFT = 36     # 8 x int32  -> 36..67   (isaretli; saga kaydirma icin negatif)
OFF_DW_BIAS  = 68     # 8 x int32  -> 68..99
OFF_DW_W     = 100    # 640 x int8 -> 100..739
OFF_FC_MULT  = 740    # 4 x int32  -> 740..755   (FC per-channel)
OFF_FC_SHIFT = 756    # 4 x int32  -> 756..771
OFF_FC_BIAS  = 772    # 4 x int32  -> 772..787
OFF_FC_OUTZP = 788    # 1 x int32  -> 788..791   (FC cikis zero-point)
OFF_FC_W     = 792    # 16000 x int8 -> 792..16791
BLOB_BYTES   = OFF_FC_W + FC_OUTPUTS * FC_FLAT   # 16792

# ============================================================
# gemmlowp fixed-point requant cekirdegi (bit-exact)
# ============================================================
def _trunc_div(n, d):
    """C++ tamsayi bolmesi: sifira dogru kirpma."""
    q = abs(n) // abs(d)
    return -q if (n < 0) ^ (d < 0) else q

def sat_round_doubling_high_mul(a, b):
    """gemmlowp SaturatingRoundingDoublingHighMul: (2*a*b)'nin yuksek 32 biti, yuvarlamali."""
    a = int(np.int32(a)); b = int(np.int32(b))
    if a == INT32_MIN and b == INT32_MIN:
        return INT32_MAX
    ab = a * b
    nudge = (1 << 30) if ab >= 0 else (1 - (1 << 30))
    result = _trunc_div(ab + nudge, 1 << 31)
    return max(INT32_MIN, min(INT32_MAX, result))

def rounding_divide_by_pot(x, exponent):
    """gemmlowp RoundingDivideByPOT: yuvarlamali 2^exponent bolme (aritmetik kaydirma)."""
    x = int(x)
    if exponent == 0:
        return x
    mask = (1 << exponent) - 1
    remainder = x & mask
    threshold = (mask >> 1) + (1 if x < 0 else 0)
    return (x >> exponent) + (1 if remainder > threshold else 0)

def _wrap_int32(v):
    """C int32 tasma sarmasi (RTL 'x <<< shift' 32-bit sarmasiyla ayni)."""
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v >= (1 << 31) else v

def multiply_by_quantized_multiplier(x, mult, shift):
    """TFLite MultiplyByQuantizedMultiplier. shift>0 sola, shift<=0 saga kaydirma."""
    left_shift = shift if shift > 0 else 0
    right_shift = 0 if shift > 0 else -shift
    x_ls = _wrap_int32(x * (1 << left_shift))
    high = sat_round_doubling_high_mul(x_ls, mult)
    return rounding_divide_by_pot(high, right_shift)

def quantize_multiplier(real_m):
    """Gercek M (>0) -> (int32 mantissa, shift). M = mantissa * 2^(shift-31)."""
    if real_m == 0.0:
        return 0, 0
    mant, exp = np.frexp(real_m)          # M = mant * 2^exp, mant in [0.5,1)
    q = int(round(mant * (1 << 31)))
    if q == (1 << 31):
        q //= 2
        exp += 1
    assert (1 << 30) <= q <= (1 << 31)
    return int(np.int32(q)), int(exp)     # shift = exp (M<1 -> exp<=0 -> saga)


# ============================================================
# Model tanimi (rastgele ama gecerli quantize edilmis model)
# ============================================================
class QuantModel:
    def __init__(self, seed=42):
        rng = np.random.default_rng(seed)
        self.rng = rng

        # --- Zero point'ler ---
        self.input_zp  = int(rng.integers(-20, 20))   # giris (asimetrik int8)
        self.dw_out_zp = int(rng.integers(-20, 20))   # DW cikis = FC giris zp

        # --- Fused ReLU aktivasyon araligi (DW cikisi) ---
        self.dw_act_min = self.dw_out_zp              # ReLU: kuantize 0 alt siniri
        self.dw_act_max = INT8_MAX

        # --- DepthwiseConv2D agirliklari (per-channel, simetrik zp=0) ---
        self.dw_w = rng.integers(-40, 41, size=(NUM_FILTERS, KER_H, KER_W), dtype=np.int32).astype(np.int8)
        self.dw_bias = rng.integers(-2000, 2000, size=NUM_FILTERS, dtype=np.int32)

        # Gercekci olcekler -> per-channel M_c = s_in*s_w_c/s_out (hepsi <1)
        s_in = 0.05
        s_out = 0.10
        s_w = rng.uniform(0.002, 0.02, size=NUM_FILTERS)
        self.dw_mult = np.zeros(NUM_FILTERS, dtype=np.int32)
        self.dw_shift = np.zeros(NUM_FILTERS, dtype=np.int32)
        for c in range(NUM_FILTERS):
            m, s = quantize_multiplier(s_in * s_w[c] / s_out)
            self.dw_mult[c] = m
            self.dw_shift[c] = s

        # --- FullyConnected agirliklari (PER-CHANNEL, simetrik zp=0) ---
        # Gercek tiny_conv FC'si per-channel (4 olcek). Random golden FARKLI
        # per-channel mult uretir -> RTL'in per-channel requant yolunu en iyi test eder.
        self.fc_w = rng.integers(-30, 31, size=(FC_OUTPUTS, FC_FLAT), dtype=np.int32).astype(np.int8)
        self.fc_bias = rng.integers(-5000, 5000, size=FC_OUTPUTS, dtype=np.int32)
        s_in_fc, s_out_fc = 0.10, 0.15
        fc_sw = rng.uniform(0.002, 0.02, size=FC_OUTPUTS)
        self.fc_mult = np.zeros(FC_OUTPUTS, dtype=np.int32)
        self.fc_shift = np.zeros(FC_OUTPUTS, dtype=np.int32)
        for n in range(FC_OUTPUTS):
            m, s = quantize_multiplier(s_in_fc * fc_sw[n] / s_out_fc)
            self.fc_mult[n] = m
            self.fc_shift[n] = s
        self.fc_out_zp = int(rng.integers(-20, 20))
        self.fc_act_min = INT8_MIN
        self.fc_act_max = INT8_MAX

    # ---- Faithful (bit-exact) cikarim ----
    def run(self, x_flat):
        """x_flat: (1960,) int8. Doner: (dw_out_flat int8 4000, logits int32 4, cls int)."""
        x = np.asarray(x_flat, dtype=np.int32).reshape(IN_H, IN_W)  # 49x40
        dw_out = np.zeros((OUT_H, OUT_W, OUT_C), dtype=np.int32)

        for oh in range(OUT_H):
            for ow in range(OUT_W):
                for c in range(OUT_C):
                    acc = 0
                    for kh in range(KER_H):
                        ih = oh * STRIDE_H + kh - PAD_TOP
                        for kw in range(KER_W):
                            iw = ow * STRIDE_W + kw - PAD_LEFT
                            if 0 <= ih < IN_H and 0 <= iw < IN_W:
                                xv = int(x[ih, iw])
                            else:
                                xv = self.input_zp          # padding = zero point (gercek 0)
                            wv = int(self.dw_w[c, kh, kw])
                            acc += wv * (xv - self.input_zp)
                    acc += int(self.dw_bias[c])
                    val = multiply_by_quantized_multiplier(acc, int(self.dw_mult[c]), int(self.dw_shift[c]))
                    val += self.dw_out_zp
                    val = max(self.dw_act_min, min(self.dw_act_max, val))
                    dw_out[oh, ow, c] = val

        # Flatten: [oh][ow][c] -> oh*OUT_W*OUT_C + ow*OUT_C + c
        dw_flat = dw_out.reshape(-1).astype(np.int32)   # 4000

        # FullyConnected -> PER-CHANNEL requant -> INT8 logit -> argmax
        # (her noron farkli olcek; int8 argmax = TFLite sinifi)
        logits = np.zeros(FC_OUTPUTS, dtype=np.int32)
        for n in range(FC_OUTPUTS):
            acc = 0
            for i in range(FC_FLAT):
                acc += int(self.fc_w[n, i]) * (int(dw_flat[i]) - self.dw_out_zp)
            acc = _wrap_int32(acc + int(self.fc_bias[n]))   # RTL int32 akumulator
            logits[n] = requant_relu(acc, int(self.fc_mult[n]), int(self.fc_shift[n]),
                                     self.fc_out_zp, self.fc_act_min, self.fc_act_max)
        cls = int(np.argmax(logits))   # int8 logit argmax (ilk maksimum = RTL tie-break)
        return dw_flat.astype(np.int8), logits.astype(np.int8), cls

    # ---- Blob (.mem) yazimi ----
    def _i32_le_bytes(self, v):
        return list(int(np.uint32(np.int32(v)) & 0xFFFFFFFF).to_bytes(4, "little"))

    def build_blob(self):
        blob = bytearray(BLOB_BYTES)
        blob[OFF_HDR + 0] = int(np.uint8(np.int8(self.input_zp)))
        blob[OFF_HDR + 1] = int(np.uint8(np.int8(self.dw_out_zp)))
        blob[OFF_HDR + 2] = int(np.uint8(np.int8(self.dw_act_min)))
        blob[OFF_HDR + 3] = int(np.uint8(np.int8(self.dw_act_max)))
        for c in range(NUM_FILTERS):
            blob[OFF_DW_MULT + 4*c: OFF_DW_MULT + 4*c+4]  = bytes(self._i32_le_bytes(self.dw_mult[c]))
            blob[OFF_DW_SHIFT + 4*c: OFF_DW_SHIFT + 4*c+4] = bytes(self._i32_le_bytes(self.dw_shift[c]))
            blob[OFF_DW_BIAS + 4*c: OFF_DW_BIAS + 4*c+4]   = bytes(self._i32_le_bytes(self.dw_bias[c]))
        # DW weights [filter][kh][kw]
        idx = OFF_DW_W
        for c in range(NUM_FILTERS):
            for kh in range(KER_H):
                for kw in range(KER_W):
                    blob[idx] = int(np.uint8(self.dw_w[c, kh, kw])); idx += 1
        for n in range(FC_OUTPUTS):
            blob[OFF_FC_MULT + 4*n: OFF_FC_MULT + 4*n+4]  = bytes(self._i32_le_bytes(self.fc_mult[n]))
            blob[OFF_FC_SHIFT + 4*n: OFF_FC_SHIFT + 4*n+4] = bytes(self._i32_le_bytes(self.fc_shift[n]))
            blob[OFF_FC_BIAS + 4*n: OFF_FC_BIAS + 4*n+4]   = bytes(self._i32_le_bytes(self.fc_bias[n]))
        blob[OFF_FC_OUTZP: OFF_FC_OUTZP+4] = bytes(self._i32_le_bytes(self.fc_out_zp))
        # FC weights [neuron][input]
        idx = OFF_FC_W
        for n in range(FC_OUTPUTS):
            for i in range(FC_FLAT):
                blob[idx] = int(np.uint8(self.fc_w[n, i])); idx += 1
        assert idx == BLOB_BYTES
        return blob


def requant_relu(acc, mult, shift, out_zp, act_min, act_max):
    """DW cikis requant'i (RTL npu_pkg::requant_relu ile birebir)."""
    v = multiply_by_quantized_multiplier(int(acc), int(mult), int(shift)) + int(out_zp)
    v = max(int(act_min), min(int(act_max), v))
    return int(np.int8(v))


def emit_requant_vectors(path, n=3000, seed=7):
    """RTL requant birim testbench'i icin (acc mult shift out_zp act_min act_max expected)."""
    rng = np.random.default_rng(seed)
    edge_acc = [0, 1, -1, 2, -2, INT32_MAX, INT32_MIN, INT32_MAX-1, INT32_MIN+1,
                1 << 20, -(1 << 20), 1 << 28, -(1 << 28)]
    edge_shift = [0, -1, -2, -7, -10, -12, 1, 2]
    rows = []
    # kose durumlari x tum shift'ler, M~0.5 ve M~rastgele
    for a in edge_acc:
        for s in edge_shift:
            m, _ = quantize_multiplier(0.5)
            rows.append((a, m, s, 0, INT8_MIN, INT8_MAX))
    # rastgele
    for _ in range(n):
        a = int(rng.integers(INT32_MIN, INT32_MAX, dtype=np.int64))
        m, sh = quantize_multiplier(float(rng.uniform(0.0005, 0.95)))
        zp = int(rng.integers(-30, 30))
        amin = int(rng.integers(-128, 0))
        amax = int(rng.integers(amin + 1, 128))
        rows.append((a, m, sh, zp, amin, amax))
    with open(path, "w") as f:
        f.write(f"{len(rows)}\n")
        for (a, m, sh, zp, amin, amax) in rows:
            e = requant_relu(a, m, sh, zp, amin, amax)
            f.write(f"{a} {m} {sh} {zp} {amin} {amax} {e}\n")
    print(f"[OK] requant vektorleri -> {path} ({len(rows)} satir)")


def _write_byte_mem(path, byte_iter):
    with open(path, "w") as f:
        for b in byte_iter:
            f.write(f"{int(b) & 0xFF:02X}\n")


def emit(seed, out_dir=WEIGHTS_DIR):
    os.makedirs(out_dir, exist_ok=True)
    model = QuantModel(seed=seed)
    rng = np.random.default_rng(seed + 1000)
    x = rng.integers(-100, 100, size=INPUT_SIZE, dtype=np.int32).astype(np.int8)

    dw_flat, logits, cls = model.run(x)

    blob = model.build_blob()
    _write_byte_mem(os.path.join(out_dir, "npu_weights.mem"), blob)
    _write_byte_mem(os.path.join(out_dir, "npu_input.mem"), [int(np.uint8(v)) for v in x])
    # Derin karsilastirma icin DW cikisi (int8) ve FC logit'leri
    _write_byte_mem(os.path.join(out_dir, "npu_dwout.mem"), [int(np.uint8(v)) for v in dw_flat])
    # FC logit'leri (4 × INT8 hex, per-channel requant sonrası) — TB derin karşılaştırma
    with open(os.path.join(out_dir, "npu_logits.mem"), "w") as f:
        for n in range(FC_OUTPUTS):
            f.write(f"{int(np.uint8(np.int8(logits[n]))):02X}\n")
    with open(os.path.join(out_dir, "npu_expected.txt"), "w") as f:
        f.write(f"class {cls}\n")
        for n in range(FC_OUTPUTS):
            f.write(f"logit{n} {int(logits[n])}\n")
    # RTL TB icin sadece-sinif dosyasi (kolay $fscanf)
    with open(os.path.join(out_dir, "npu_expected_class.txt"), "w") as f:
        f.write(f"{cls}\n")

    print(f"[OK] weights/ -> npu_weights.mem ({BLOB_BYTES} B), npu_input.mem ({INPUT_SIZE} B)")
    print(f"[OK] beklenen: class={cls}  logits={list(map(int, logits))}")
    print(f"[INFO] input_zp={model.input_zp} dw_out_zp={model.dw_out_zp} "
          f"act=[{model.dw_act_min},{model.dw_act_max}] PAD_TOP={PAD_TOP} PAD_LEFT={PAD_LEFT}")
    return model, x, dw_flat, logits, cls


# ============================================================
# Ic tutarlilik testleri
# ============================================================
def selftest():
    ok = True

    # 1) gemmlowp bilinen vektorler (gemmlowp birim testlerinden turetilmis)
    #    M ~ 0.5 (mult=2^30, shift=0) ile x -> ~x/2 yuvarlamali
    m_half, s_half = quantize_multiplier(0.5)
    assert (m_half, s_half) == (1 << 30, 0), (m_half, s_half)
    for x in [0, 1, 2, 3, 100, -1, -2, -3, -100, 12345, -12345]:
        got = multiply_by_quantized_multiplier(x, m_half, s_half)
        exp = int(np.round(x * 0.5).astype(np.int64))  # banker? gemmlowp .5 -> away from zero up
        # gemmlowp: round-half-up (pozitif), negatifte de yukari (zero'ya dogru degil)
        # x=1 -> 1 ; x=-1 -> 0 ; x=3 -> 2 ; x=-3 -> -1
        # bunu acik dogrula:
    # acik beklenenler:
    checks = {0:0, 1:1, 2:1, 3:2, 100:50, -1:0, -2:-1, -3:-1, -100:-50}
    for x, e in checks.items():
        g = multiply_by_quantized_multiplier(x, 1 << 30, 0)
        if g != e:
            print(f"[FAIL] requant(0.5) x={x} got={g} exp={e}"); ok = False

    # 2) M ~ 0.25 (mult=2^30, shift=-1)
    m_q, s_q = quantize_multiplier(0.25)
    assert s_q == -1 and m_q == (1 << 30), (m_q, s_q)
    # NOT: gemmlowp negatif yarimi floor'a yuvarlar: -2*0.25=-0.5 -> -1 (0 degil)
    for x, e in {0:0, 2:1, 4:1, 8:2, -2:-1, -4:-1}.items():
        g = multiply_by_quantized_multiplier(x, m_q, s_q)
        if g != e:
            print(f"[FAIL] requant(0.25) x={x} got={g} exp={e}"); ok = False

    # 3) run() deterministik + sinif araliginda
    model, x, dw_flat, logits, cls = emit(seed=42, out_dir=os.path.join(os.path.dirname(__file__), "_selftest_out"))
    assert 0 <= cls < FC_OUTPUTS
    assert dw_flat.shape[0] == FC_FLAT
    # DW cikisi ReLU sonrasi: hepsi >= act_min
    assert dw_flat.min() >= model.dw_act_min, (dw_flat.min(), model.dw_act_min)

    # 4) FC logit'leri artik PER-CHANNEL requant edilmis INT8 -> tam int8 araliginda
    assert logits.dtype == np.int8
    assert all(INT8_MIN <= int(v) <= INT8_MAX for v in logits)
    # per-channel mult'lar gercekten farkli (random model kapsami)
    assert len(set(map(int, model.fc_mult))) >= 2, "fc_mult per-channel cesitliligi yok"

    print("[SELFTEST]", "GECTI" if ok else ">>> BASARISIZ <<<")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--emit", action="store_true", help="weights/ altina .mem vektorleri yaz")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--requant-vectors", action="store_true",
                    help="weights/requant_vectors.txt uret (RTL birim test)")
    args = ap.parse_args()
    if args.selftest:
        selftest()
    if args.requant_vectors:
        os.makedirs(WEIGHTS_DIR, exist_ok=True)
        emit_requant_vectors(os.path.join(WEIGHTS_DIR, "requant_vectors.txt"))
    if args.emit or not (args.selftest or args.requant_vectors):
        emit(args.seed)


if __name__ == "__main__":
    main()
