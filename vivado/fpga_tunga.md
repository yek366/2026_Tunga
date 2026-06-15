# FPGA Tam SoC — `gozlem_design_2` (Vivado 2025.2)

Takımın tam TUNGA SoC FPGA blok tasarımı. Bir ekip arkadaşı Vivado proje arşivi
(`fpga_tunga`, ~55 MB) olarak gönderdi. Arşivin tamamı build çıktısı ağırlıklı
(`.cache/.gen/.runs/.dcp/sim_netlist/.Xil`) → **GitHub'a konmaz** (repo dışı
`inbox/` altında, `.gitignore`'da). Versiyonlanabilir öz burada tutulur.

## Proje bilgisi
- **Vivado:** 2025.2
- **Hedef kart:** Nexys 4 (Artix-7) — constraint `dis_mihraklar.xdc`'den:
  100 MHz clk (E3), reset C12 (active-low), UART C4/D4, JTAG PMOD JA,
  QSPI flash pinleri, SPIx4 config. → [`constraints/dis_mihraklar.xdc`](constraints/dis_mihraklar.xdc)
- **Part:** `.xpr`'de `xc7a12ticsg325-1L` ama ⚠ **constraint Nexys 4 pinleri**
  (Nexys 4 = `xc7a100t-csg324`). Part ↔ kart UYUMSUZ — takım düzeltmeli.
  Ayrıca teknotest gate part'ı `xc7k325t` (Kintex) → üçü de farklı, netleşmeli.
- **Boot/firmware:** arşivde `boot.mem` (62 satır) + `firmware.mem` (10 satır,
  RISC-V test programı) var (Yağmur sw alanı). `.bit` bitstream arşivde YOK.
- **Blok tasarım:** `gozlem_design_2`
- **NPU bu BD'de YOK** — NPU entegre edilince bu block design'a eklenecek
  (CSR → AXI interconnect slave, AI_MEM → bus, IRQ → axi_intc).

## Entegre IP / modüller (hw_handoff'tan)
| Modül | Rol |
|-------|-----|
| `cv32e40p_top` | RISC-V çekirdek |
| `obi_to_axi_bridge` | OBI→AXI köprü (Sevda) |
| `obi_instr_mem` | Buyruk belleği |
| `boot_rom` | Boot ROM |
| `axi_interconnect` + `axi_bram_ctrl` + `blk_mem_gen` | AXI veri yolu + BRAM |
| `axi_intc` | Kesme denetleyici |
| `gpio_peripheral` / `uart_peripheral` / `uart_stream_peripheral` / `timer_peripheral` / `i2c_peripheral` | Çevre birimleri |
| `axi_qspi_T_v1_0` | QSPI |
| `jtag_debug_wrapper` | JTAG/Debug (+3 bonus) |
| `clk_wiz` / `proc_sys_reset` / `xlconcat` / `xlconstant` | Saat/reset/glue |

Tam adres haritası + bağlantılar: [`handoff/gozlem_design_2.hwh`](handoff/gozlem_design_2.hwh)
(Vivado hardware-handoff, BD'nin kaynak-niteliğindeki tek mevcut özeti).

## ⚠ Yeniden-üretilebilirlik açığı (yapılacak — Yuşa, Vivado sahibi)
Arşivde **`write_bd_tcl` / `write_project_tcl` recreate scripti YOK** ve **`.bit`
YOK**. Jüri akışı tek script ile reproduce etmeli (şartname). Gereken:
1. Vivado'da projeyi aç → `write_bd_tcl -force vivado/scripts/gozlem_design_2_bd.tcl`
2. `write_project_tcl -force vivado/scripts/recreate_fpga_tunga.tcl`
3. Pin constraint `.xdc`'leri `vivado/constraints/` altına ekle (şu an boş).
4. Bunları commit et → 55 MB binary yerine ~birkaç yüz KB script ile proje
   sıfırdan kurulabilir olur.

Mevcut eski BD scripti: `vivado/scripts/tunga_micro.tcl` (Yuşa, daha eski varyant).
