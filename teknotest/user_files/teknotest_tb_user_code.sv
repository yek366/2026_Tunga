// helloworld.mem'i boot ROM dizisine yükle (dosya adı DDK sabiti).
// Hiyerarşi: tb(dut) -> teknotest_wrapper(u_tunga_soc) -> soc_top(u_boot_rom) -> mem
initial begin
    $readmemh("helloworld.mem", dut.u_tunga_soc.u_boot_rom.mem);
end
