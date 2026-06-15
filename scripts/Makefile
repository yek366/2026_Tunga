# ============================================================
# Makefile — TUNGA SoC TEKNOFEST 2026
# Kullanım:
#   make sim-npu      → NPU izole simülasyonu (Verilator)
#   make sim-system   → Sistem seviyesi simülasyon (ileride)
#   make lint-npu     → Verilator lint kontrolü
#   make clean        → Simülasyon çıktılarını temizle
# ============================================================

REPO_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))..

# ---- Araçlar ----
VERILATOR  := verilator
PYTHON3    := python3
RISCV_GCC  := riscv32-unknown-elf-gcc

# ---- Dizinler ----
RTL_DIR    := $(REPO_ROOT)/rtl
TB_DIR     := $(REPO_ROOT)/tb
SIM_DIR    := $(REPO_ROOT)/sim
OBJ_DIR    := $(REPO_ROOT)/obj_dir

# ---- NPU RTL dosyaları (npu_pkg ÖNCE) ----
NPU_RTL := \
    $(RTL_DIR)/npu/npu_pkg.sv           \
    $(RTL_DIR)/npu/local_buffer.sv      \
    $(RTL_DIR)/npu/input_buffer.sv      \
    $(RTL_DIR)/npu/fc_weight_buffer.sv  \
    $(RTL_DIR)/npu/softmax_argmax.sv    \
    $(RTL_DIR)/npu/fully_connected.sv   \
    $(RTL_DIR)/npu/depthwise_conv2d.sv  \
    $(RTL_DIR)/npu/fsm_controller.sv    \
    $(RTL_DIR)/npu/axi_controller.sv    \
    $(RTL_DIR)/npu/npu_top.sv

NPU_TB := $(TB_DIR)/npu/npu_tb.sv

# Requant birim testi (quant_requant standalone)
REQUANT_RTL := $(RTL_DIR)/npu/npu_pkg.sv $(RTL_DIR)/npu/quant_requant.sv
REQUANT_TB  := $(TB_DIR)/npu/requant_tb.sv

# ---- Verilator bayrakları ----
VFLAGS := \
    --sv --timing \
    --cc --exe     \
    --assert       \
    --trace        \
    -Wall          \
    -Wno-UNUSED    \
    -CFLAGS "-O2"

# ============================================================
.PHONY: all sim-npu sim-system lint-npu clean help

all: sim-npu

# ---- NPU simülasyonu ----
sim-npu: $(SIM_DIR)
	@echo "[VERILATOR] NPU simülasyonu derleniyor..."
	$(VERILATOR) $(VFLAGS) \
	    --top-module npu_tb \
	    $(NPU_RTL) $(NPU_TB) \
	    --Mdir $(OBJ_DIR)/npu \
	    -o npu_sim
	@echo "[MAKE] Derleniyor..."
	$(MAKE) -C $(OBJ_DIR)/npu -f Vnpu_tb.mk
	@echo "[SIM] Çalıştırılıyor..."
	$(OBJ_DIR)/npu/npu_sim
	@echo "[SIM] VCD: $(SIM_DIR)/npu_tb.vcd"

# ---- Sistem seviyesi simülasyon (henüz iskelet) ----
sim-system:
	@echo "[INFO] Sistem simülasyonu henüz hazır değil."
	@echo "       tunga_soc.sv ve sistem testbench'i tamamlandığında etkinleştirilecek."

# ---- Lint ----
lint-npu:
	@echo "[LINT] NPU modülleri kontrol ediliyor..."
	$(VERILATOR) --lint-only --sv -Wall \
	    $(NPU_RTL)
	@echo "[LINT] Tamamlandı."

# ---- sim dizini ----
$(SIM_DIR):
	mkdir -p $(SIM_DIR)

# ---- Temizlik ----
clean:
	rm -rf $(OBJ_DIR) $(SIM_DIR)/*.vcd $(SIM_DIR)/*.fst
	@echo "[CLEAN] Tamamlandı."

# ---- Yardım ----
help:
	@echo "Kullanılabilir hedefler:"
	@echo "  sim-npu     : NPU izole simülasyonu"
	@echo "  sim-system  : Sistem seviyesi simülasyon"
	@echo "  lint-npu    : NPU RTL lint kontrolü"
	@echo "  clean       : Simülasyon çıktılarını temizle"
