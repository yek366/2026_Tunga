#!/usr/bin/env python3
# ============================================================
# inspect_tflite.py — gercek tiny_conv .tflite modelini incele
# Tensor sekillerini + quant parametrelerini dok; sartname/RTL dim'leriyle
# eslestigini dogrula (1960 giris, DWConv 8x10x8, FC 4x4000, 4 sinif).
# ============================================================
import sys

try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:
    try:
        from tflite_runtime.interpreter import Interpreter
    except ImportError:
        from tensorflow.lite import Interpreter

path = sys.argv[1] if len(sys.argv) > 1 else "tflite/micro_speech_quantized.tflite"
it = Interpreter(model_path=path)
it.allocate_tensors()

print("== INPUT ==")
for d in it.get_input_details():
    print(f"  {d['name']} shape={list(d['shape'])} dtype={d['dtype'].__name__} quant={d['quantization']}")
print("== OUTPUT ==")
for d in it.get_output_details():
    print(f"  {d['name']} shape={list(d['shape'])} dtype={d['dtype'].__name__} quant={d['quantization']}")

print("== TUM TENSORLAR (sekil + quant) ==")
for d in it.get_tensor_details():
    shape = list(d['shape'])
    qp = d.get('quantization_parameters', {})
    scales = qp.get('scales', [])
    zps = qp.get('zero_points', [])
    nsc = len(scales)
    print(f"  idx={d['index']:2d} {d['name'][:48]:48s} shape={shape} dtype={d['dtype'].__name__} "
          f"nscale={nsc} zp0={zps[0] if len(zps) else '-'}")
