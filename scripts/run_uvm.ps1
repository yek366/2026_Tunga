# Vivado'yu kullanarak UVM simülasyonunu başlatır
$VivadoPath = "C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat"

if (-Not (Test-Path $VivadoPath)) {
    Write-Host "[HATA] Vivado bulunamadı: $VivadoPath" -ForegroundColor Red
    Write-Host "Lütfen Vivado yolunu run_uvm.ps1 içinden güncelleyin."
    exit
}

Write-Host "Vivado UVM Simülasyonu Başlatılıyor..." -ForegroundColor Cyan
& $VivadoPath -mode batch -source run_uvm_vivado.tcl
