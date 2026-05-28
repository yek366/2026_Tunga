#!/usr/bin/env python3
import os
import random

def generate_golden_vectors():
    print("=== TFLite Micro Speech - Golden Vector Uretici ===\n")
    
    # Yollar (sim klasörü altına kaydedilecek çünkü simülatör orada koşuyor)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    sim_dir = os.path.join(project_root, "sim")
    
    os.makedirs(sim_dir, exist_ok=True)
    
    # 1. Sembolik (Mock) girdi (stimulus) üretimi
    # Örnek: TFLite modelini besleyecek 16 adet 16-bit ses/feature verisi
    num_samples = 16
    stimulus_data = []
    
    print(f"[{num_samples}] adet sembolik ses feature verisi uretiliyor...")
    for _ in range(num_samples):
        val = random.randint(0, 65535) # 16-bit işaretsiz mock veri
        stimulus_data.append(val)
        
    # 2. Beklenen İdeal (Golden) Sonucun Hesaplanması
    # Normalde burada TFLite modeli çağrılıp inference yapılır. 
    # Şartname gereği donanımı simüle etmek adına matematiksel bir mock işlem (örn. ortalama alma)
    ideal_result = sum(stimulus_data) // len(stimulus_data)
    
    # 3. %10 Tolerans kuralının (Accuracy Loss) uygulanması
    # Tolerans Python'da önceden hesaplanır ve testbench'e sadece sınırlar verilir.
    min_bound = int(ideal_result * 0.90)
    max_bound = int(ideal_result * 1.10)
    
    print(f"İdeal (Golden) Sonuç  : {ideal_result}")
    print(f"Minimum Sınır (%90)  : {min_bound}")
    print(f"Maksimum Sınır (%110): {max_bound}\n")
    
    # 4. Verileri .hex Dosyalarına Formatlama
    stimulus_file = os.path.join(sim_dir, "ai_stimulus.hex")
    min_file = os.path.join(sim_dir, "ai_expected_min.hex")
    max_file = os.path.join(sim_dir, "ai_expected_max.hex")
    
    # Stimulus dosyasını doldur
    with open(stimulus_file, "w") as f:
        for val in stimulus_data:
            f.write(f"{val:08X}\n") # 32-bit hex
            
    # Tolerans sınır dosyalarını doldur
    with open(min_file, "w") as f:
        f.write(f"{max(0, min_bound):08X}\n")
        
    with open(max_file, "w") as f:
        f.write(f"{max(0, max_bound):08X}\n")
        
    print(f"Dosyalar basariyla '{sim_dir}' klasorune kaydedildi:")
    print(" -> ai_stimulus.hex")
    print(" -> ai_expected_min.hex")
    print(" -> ai_expected_max.hex")

if __name__ == "__main__":
    generate_golden_vectors()
