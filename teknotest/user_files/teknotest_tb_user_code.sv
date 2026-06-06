// Load the compiled test program into the boot ROM array.
// helloworld.mem filename is fixed by DDK (added by create_vivado_proj.tcl).
// Hierarchy: tb(dut) -> teknotest_wrapper(u_soc) -> tunga_soc_min(u_bootrom) -> rom
initial begin
    $readmemh("helloworld.mem", dut.u_soc.u_bootrom.rom);
end
