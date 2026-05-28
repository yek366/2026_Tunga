OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  /* İşlemcinin Boot adresi: 0x1A000000 */
  flash (rx) : ORIGIN = 0x1A000000, LENGTH = 32M
  ram (rwx)  : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS
{
  .text : {
    /* Boot kodunu en başa yerleştir */
    *(.text.init)
    *(.text)
    *(.rodata)
  } > flash

  .data : {
    *(.data)
  } > ram AT > flash

  .bss : {
    *(.bss)
  } > ram
}
