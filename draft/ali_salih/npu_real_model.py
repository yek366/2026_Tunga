#!/usr/bin/env python3
# ============================================================
# npu_real_model.py — GERCEK tiny_conv .tflite'tan quant param + agirlik
# cikar, faithful integer inference uygula, TFLite interpreter'a (YER GERCEGI)
# karsi BIT-BIT dogrula. Random int8 girisle integer-matematik esitligini test
# eder (gercek ses verisi gerekmez). Gecince RTL'i bu golden'a gore degistiririz.
#
# Calistir: ~/tunga_venv/bin/python npu_real_model.py
# ============================================================
import os
import numpy as np

# requant cekirdegini dogrulanmis golden'dan al (bit-exact gemmlowp)
from npu_golden import (multiply_by_quantized_multiplier, quantize_multiplier,
                        _wrap_int32, IN_H, IN_W, NUM_FILTERS, KER_H, KER_W,
                        STRIDE_H, STRIDE_W, OUT_H, OUT_W, OUT_C, FC_FLAT, FC_OUTPUTS,
                        PAD_TOP, PAD_LEFT, INT8_MIN, INT8_MAX, INPUT_SIZE, WEIGHTS_DIR,
                        BLOB_BYTES, OFF_HDR, OFF_DW_MULT, OFF_DW_SHIFT, OFF_DW_BIAS, OFF_DW_W,
                        OFF_FC_MULT, OFF_FC_SHIFT, OFF_FC_BIAS, OFF_FC_OUTZP, OFF_FC_W,
                        _write_byte_mem)

from ai_edge_litert.interpreter import Interpreter

HERE = os.path.dirname(__file__)
MODEL = os.path.join(HERE, "tflite", "micro_speech_quantized.tflite")


def requant_clamp(acc, mult, shift, out_zp, amin, amax):
    v = multiply_by_quantized_multiplier(int(acc), int(mult), int(shift)) + int(out_zp)
    return max(amin, min(amax, v))


class RealModel:
    def __init__(self, path=MODEL):
        it = Interpreter(model_path=path)
        it.allocate_tensors()
        self.it = it
        det = {d['name']: d for d in it.get_tensor_details()}
        self.det = det
        inp = it.get_input_details()[0]
        out = it.get_output_details()[0]
        self.in_idx = inp['index']
        self.out_idx = out['index']
        self.input_scale, self.input_zp = inp['quantization']

        def qp(name):
            d = det[name]['quantization_parameters']
            return np.array(d['scales']), np.array(d['zero_points'])

        # --- DepthwiseConv weights [1,10,8,8] -> dw_w[c][kh][kw] ---
        fw = it.get_tensor(det['first_weights/read']['index'])  # [1,10,8,8]
        self.dw_w = np.transpose(fw[0], (2, 0, 1)).astype(np.int32)  # [8,10,8]
        dw_wsc, _ = qp('first_weights/read')                         # 8 scale
        self.dw_bias = it.get_tensor(det['Conv2D_bias']['index']).astype(np.int64)  # [8]
        relu_sc, relu_zp = qp('Relu')
        self.dw_out_scale = float(relu_sc[0]); self.dw_out_zp = int(relu_zp[0])
        # DW per-channel mult/shift: M_c = in_scale*w_scale_c/out_scale
        self.dw_mult = np.zeros(NUM_FILTERS, np.int64); self.dw_shift = np.zeros(NUM_FILTERS, np.int64)
        for c in range(NUM_FILTERS):
            m, s = quantize_multiplier(self.input_scale * float(dw_wsc[c]) / self.dw_out_scale)
            self.dw_mult[c] = m; self.dw_shift[c] = s
        # fused ReLU clamp: act_min = quantize(0) = out_zp ; act_max = 127
        self.dw_act_min = self.dw_out_zp
        self.dw_act_max = INT8_MAX

        # --- FullyConnected weights [4,4000] -> fc_w[n][i], per-channel (4) ---
        self.fc_w = it.get_tensor(det['final_fc_weights/read/transpose']['index']).astype(np.int32)  # [4,4000]
        fc_wsc, _ = qp('final_fc_weights/read/transpose')             # 4 scale
        self.fc_bias = it.get_tensor(det['MatMul_bias']['index']).astype(np.int64)  # [4]
        add_sc, add_zp = qp('add_1')
        self.fc_out_scale = float(add_sc[0]); self.fc_out_zp = int(add_zp[0])
        self.fc_mult = np.zeros(FC_OUTPUTS, np.int64); self.fc_shift = np.zeros(FC_OUTPUTS, np.int64)
        for n in range(FC_OUTPUTS):
            m, s = quantize_multiplier(self.dw_out_scale * float(fc_wsc[n]) / self.fc_out_scale)
            self.fc_mult[n] = m; self.fc_shift[n] = s
        # FC: fused activation YOK -> tam int8 clamp
        self.fc_act_min = INT8_MIN; self.fc_act_max = INT8_MAX

    # ---- faithful integer inference (RTL'in uygulayacagi matematik) ----
    def run(self, x_flat):
        x = np.asarray(x_flat, np.int32).reshape(IN_H, IN_W)
        dw = np.zeros((OUT_H, OUT_W, OUT_C), np.int32)
        for oh in range(OUT_H):
            for ow in range(OUT_W):
                for c in range(OUT_C):
                    acc = 0
                    for kh in range(KER_H):
                        ih = oh*STRIDE_H + kh - PAD_TOP
                        for kw in range(KER_W):
                            iw = ow*STRIDE_W + kw - PAD_LEFT
                            xv = int(x[ih, iw]) if (0 <= ih < IN_H and 0 <= iw < IN_W) else self.input_zp
                            acc += int(self.dw_w[c, kh, kw]) * (xv - self.input_zp)
                    acc += int(self.dw_bias[c])
                    dw[oh, ow, c] = requant_clamp(acc, self.dw_mult[c], self.dw_shift[c],
                                                  self.dw_out_zp, self.dw_act_min, self.dw_act_max)
        dwf = dw.reshape(-1).astype(np.int32)  # 4000
        logits = np.zeros(FC_OUTPUTS, np.int32)
        for n in range(FC_OUTPUTS):
            acc = 0
            for i in range(FC_FLAT):
                acc += int(self.fc_w[n, i]) * (int(dwf[i]) - self.dw_out_zp)
            acc = _wrap_int32(acc + int(self.fc_bias[n]))
            logits[n] = requant_clamp(acc, self.fc_mult[n], self.fc_shift[n],
                                      self.fc_out_zp, self.fc_act_min, self.fc_act_max)
        cls = int(np.argmax(logits))   # int8 logit argmax (per-channel requant sonrasi)
        return dwf.astype(np.int8), logits.astype(np.int8), cls

    # ---- TFLite interpreter (yer gercegi) ----
    def interp(self, x_flat):
        x = np.asarray(x_flat, np.int8).reshape(1, INPUT_SIZE)
        self.it.set_tensor(self.in_idx, x)
        self.it.invoke()
        out = self.it.get_tensor(self.out_idx)[0]   # labels_softmax int8 [4]
        # add_1 (FC ciktisi) okunabiliyorsa al
        try:
            add1 = self.it.get_tensor(self.det['add_1']['index'])[0].astype(np.int8)
        except Exception:
            add1 = None
        return out, int(np.argmax(out)), add1


def _i32le(v):
    return list(int(np.uint32(np.int32(v)) & 0xFFFFFFFF).to_bytes(4, "little"))


def build_blob(m):
    """Gercek model parametrelerinden AI_MEM blob'u (npu_pkg layout ile birebir)."""
    blob = bytearray(BLOB_BYTES)
    blob[OFF_HDR+0] = int(np.uint8(np.int8(m.input_zp)))
    blob[OFF_HDR+1] = int(np.uint8(np.int8(m.dw_out_zp)))
    blob[OFF_HDR+2] = int(np.uint8(np.int8(m.dw_act_min)))
    blob[OFF_HDR+3] = int(np.uint8(np.int8(m.dw_act_max)))
    for c in range(NUM_FILTERS):
        blob[OFF_DW_MULT+4*c:OFF_DW_MULT+4*c+4]  = bytes(_i32le(m.dw_mult[c]))
        blob[OFF_DW_SHIFT+4*c:OFF_DW_SHIFT+4*c+4] = bytes(_i32le(m.dw_shift[c]))
        blob[OFF_DW_BIAS+4*c:OFF_DW_BIAS+4*c+4]   = bytes(_i32le(m.dw_bias[c]))
    idx = OFF_DW_W
    for c in range(NUM_FILTERS):
        for kh in range(KER_H):
            for kw in range(KER_W):
                blob[idx] = int(np.uint8(m.dw_w[c, kh, kw])); idx += 1
    for n in range(FC_OUTPUTS):
        blob[OFF_FC_MULT+4*n:OFF_FC_MULT+4*n+4]  = bytes(_i32le(m.fc_mult[n]))
        blob[OFF_FC_SHIFT+4*n:OFF_FC_SHIFT+4*n+4] = bytes(_i32le(m.fc_shift[n]))
        blob[OFF_FC_BIAS+4*n:OFF_FC_BIAS+4*n+4]   = bytes(_i32le(m.fc_bias[n]))
    blob[OFF_FC_OUTZP:OFF_FC_OUTZP+4] = bytes(_i32le(m.fc_out_zp))
    idx = OFF_FC_W
    for n in range(FC_OUTPUTS):
        for i in range(FC_FLAT):
            blob[idx] = int(np.uint8(m.fc_w[n, i])); idx += 1
    assert idx == BLOB_BYTES
    return blob


def _read_feat_mem(path):
    """weights/feat_<label>.mem (2-hex bayt/satir) -> np.int8[1960] (uint8->int8 reinterpret)."""
    bytes_ = [int(line.strip(), 16) & 0xFF for line in open(path) if line.strip()]
    assert len(bytes_) == INPUT_SIZE, f"{path}: {len(bytes_)} != {INPUT_SIZE}"
    return np.array(bytes_, dtype=np.uint8).astype(np.int8)


def emit(seed=777, feat_file=None):
    """Gercek model blob'u + test girisi + (interpreter'la dogrulanmis) beklenen ciktilari
    weights/ altina yaz — RTL npu_tb bunlari okur. Boylece RTL = gercek tiny_conv modeli.
    feat_file verilirse GERCEK ses feature vektoru giris olur (random yerine)."""
    os.makedirs(WEIGHTS_DIR, exist_ok=True)
    m = RealModel()
    if feat_file:
        x = _read_feat_mem(feat_file)
    else:
        rng = np.random.default_rng(seed)
        x = rng.integers(INT8_MIN, INT8_MAX+1, size=INPUT_SIZE, dtype=np.int8)
    dwf, logits, cls = m.run(x)                 # golden (bit-exact gemmlowp)
    _, icls, add1 = m.interp(x)                 # TFLite interpreter (yer gercegi)
    assert cls == icls, f"golden cls {cls} != interp {icls}"
    if add1 is not None:
        assert np.array_equal(logits, add1), "golden logit != interp add_1"
    _write_byte_mem(os.path.join(WEIGHTS_DIR, "npu_weights.mem"), build_blob(m))
    _write_byte_mem(os.path.join(WEIGHTS_DIR, "npu_input.mem"),  [int(np.uint8(v)) for v in x])
    _write_byte_mem(os.path.join(WEIGHTS_DIR, "npu_dwout.mem"),  [int(np.uint8(v)) for v in dwf])
    _write_byte_mem(os.path.join(WEIGHTS_DIR, "npu_logits.mem"), [int(np.uint8(v)) for v in logits])
    with open(os.path.join(WEIGHTS_DIR, "npu_expected_class.txt"), "w") as f:
        f.write(f"{cls}\n")
    print(f"[OK] GERCEK model blob yazildi. class={cls} (interp={icls}) logits={list(map(int,logits))}")
    print(f"[OK] interpreter ile dogrulandi -> RTL npu_tb bu gercek modele karsi kosacak")


def main():
    import sys
    if "--feature" in sys.argv:
        ff = sys.argv[sys.argv.index("--feature") + 1]
        emit(feat_file=ff)
        return
    if "--emit" in sys.argv:
        emit()
        return
    m = RealModel()
    print(f"[INFO] input_zp={m.input_zp} dw_out_zp={m.dw_out_zp} fc_out_zp={m.fc_out_zp}")
    print(f"[INFO] dw_mult[0:3]={list(m.dw_mult[:3])} dw_shift={list(m.dw_shift)}")
    print(f"[INFO] fc_mult={list(m.fc_mult)} fc_shift={list(m.fc_shift)}")

    rng = np.random.default_rng(123)
    N = 12
    cls_match = 0; logit_exact = 0
    for t in range(N):
        x = rng.integers(INT8_MIN, INT8_MAX+1, size=INPUT_SIZE, dtype=np.int8)
        dwf, logits, cls = m.run(x)
        soft, icls, add1 = m.interp(x)
        ok = (cls == icls)
        cls_match += ok
        le = (add1 is not None and np.array_equal(logits, add1))
        logit_exact += le
        print(f"  t={t:2d} golden_cls={cls} interp_cls={icls} {'OK' if ok else 'XXX'} "
              f"| golden_logits={list(map(int,logits))} interp_add1={None if add1 is None else list(map(int,add1))}")
    print(f"\n[SONUC] sinif eslesme: {cls_match}/{N} | FC logit bit-exact: {logit_exact}/{N}")
    if cls_match == N:
        print(">>> GOLDEN integer-matematigi TFLite interpreter ile TUTARLI <<<")
    else:
        print(">>> UYUSMAZLIK: quant anlayisi yanlis, RTL'e gecmeden duzelt <<<")


if __name__ == "__main__":
    main()
