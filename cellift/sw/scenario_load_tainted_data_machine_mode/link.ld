OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x00000080;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  tainted_symbol = .;
}
