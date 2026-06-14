// Hakemlerin oluşturduğu helloworld.mem dosyasını Tunga'nın Boot ROM'una yüklüyoruz.
initial begin
    $readmemh("helloworld.mem", dut.u_tunga_soc.u_boot_rom.mem);
end