/* 起動用スタブ（boot/boot.S）のリンカスクリプト。
 *
 * スタブは 1MB の位置に置き、64 ビットのカーネル本体はちょうど 2MB の位置に
 * 置く。boot.S は 2MB へジャンプするので、ここがずれると起動しない。 */

ENTRY(_start)

SECTIONS
{
  . = 1M;

  /* Multiboot ヘッダはファイルの先頭近くになければならないので最初に置く。 */
  .multiboot : { *(.multiboot) }
  .text      : { *(.text*) }
  .rodata    : { *(.rodata*) }

  .bss : {
    __bss_start = .;
    *(.bss*)
    __bss_end = .;
  }

  /* スタブが 2MB を超えるとカーネル本体と重なってしまう。 */
  ASSERT(. <= 2M, "boot stub overlaps the kernel at 2MB")

  . = 2M;
  .kernel64 : { *(.kernel64) }
}
