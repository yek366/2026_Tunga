#!/usr/bin/env python3
# micro_features .cc dosyasindan int8 dizisini cikar, tiny_conv interpreter'a
# ver, sinifi yazdir. Amac: feature formati tiny_conv modeliyle uyumlu mu?
import re, sys
import numpy as np
from ai_edge_litert.interpreter import Interpreter

def parse_cc(path):
    txt = open(path).read()
    # dizinin govdesini al: '= {' ile '}' arasi
    m = re.search(r"=\s*\{(.*?)\}", txt, re.S)
    body = m.group(1)
    vals = [int(x) for x in re.findall(r"-?\d+", body)]
    return np.array(vals, dtype=np.int8)

LBL = {0:"silence",1:"unknown",2:"yes",3:"no"}
it = Interpreter(model_path="tflite/micro_speech_quantized.tflite"); it.allocate_tensors()
ind = it.get_input_details()[0]; outd = it.get_output_details()[0]

for path, name in [("tflite/yes_feat.cc","YES"), ("tflite/no_feat.cc","NO")]:
    arr = parse_cc(path)
    print(f"{name}: parse {arr.shape[0]} deger, min={arr.min()} max={arr.max()}")
    x = arr[:1960].reshape(1,1960).astype(np.int8)
    it.set_tensor(ind['index'], x); it.invoke()
    o = it.get_tensor(outd['index'])[0]
    cls = int(np.argmax(o))
    print(f"   -> interpreter sinif={cls} ({LBL[cls]})  logits={list(map(int,o))}")
