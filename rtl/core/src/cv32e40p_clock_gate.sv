// =============================================================================
// cv32e40p_clock_gate.sv — Behavioral Simulation Stub
// =============================================================================
// Teknofest 2026 / Tunga SoC Projesi
//
// AMAÇ: cv32e40p_sleep_unit.sv içinde kullanılan cv32e40p_clock_gate modülünün
//       XSIM simülasyonu için davranışsal (behavioral) karşılığıdır.
//       Gerçek FPGA sentezinde bu modül yerine donanım clock gating primitive'i
//       (örn: BUFGCE) kullanılır. Simülasyonda ise enable sinyali doğrudan
//       AND kapısı ile uygulanır.
//
// REFERANS: https://github.com/openhwgroup/cv32e40p/blob/master/bhv/cv32e40p_sim_clock_gate.sv
// =============================================================================

module cv32e40p_clock_gate (
  input  logic clk_i,        // Giriş saati
  input  logic en_i,         // Clock enable
  input  logic scan_cg_en_i, // Scan test enable (override)
  output logic clk_o         // Çıkış saati (gated)
);

  // Behavioral model: enable veya scan aktifse clock geçer
  assign clk_o = clk_i & (en_i | scan_cg_en_i);

endmodule
