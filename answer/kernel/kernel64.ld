/* ANCHOR: all */
/* 64 ビットのカーネル本体のリンカスクリプト。
 *
 * カーネルは 2MB の位置から始まるように配置する。boot/boot.S はこの位置に
 * ジャンプする。 */

ENTRY(_start64)

SECTIONS
{
  /* gcc が付け足す、実行には使わない情報。残しておくと 2MB の先頭に
   * 置かれることがあり、そこへジャンプした CPU がデータを命令として実行してしまう。 */
  /DISCARD/ : { *(.note*) *(.comment) *(.eh_frame*) }

  . = 2M;

  /* 入り口（entry64.S の _start64）を必ず先頭に置く。 */
  .text   : { *(.text.entry) *(.text*) }

  /* ANCHOR: etext */
  /* PicoRuby の VM は、あるデータが「書き換えられない場所」にあるかを
   *   etext < アドレス < edata
   * で判定し、そうならコピーせずにそのまま使う。埋め込んだバイトコードや
   * 文字列リテラルが置かれる .rodata を、この 2 つで挟んでおく。 */
  etext = .;
  .rodata : { *(.rodata*) }
  .data   : { *(.data*) }
  edata = .;
  /* ANCHOR_END: etext */

  .bss : {
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  }

  _end = .;

  /* boot/boot.S がマップするのは先頭 32MB だけ。それを超えると、
   * マップされていないアドレスに触れた瞬間に CPU 例外が起きる。 */
  ASSERT(_end <= 32M, "kernel does not fit in the 32MB mapped by boot/boot.S")
}
/* ANCHOR_END: all */
