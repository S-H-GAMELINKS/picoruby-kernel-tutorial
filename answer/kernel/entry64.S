/* 64 ビットのカーネル本体の入り口。
 *
 * boot/boot.S が 64 ビットモードに切り替えたあと、ここ（2MB の位置）に
 * ジャンプしてくる。C の関数を呼ぶ前に、BSS のクリアとスタックの準備をする。 */

.section .text.entry, "ax"
.code64
.global _start64
_start64:
    /* BSS をゼロで埋める。C では「初期値のないグローバル変数は 0」と
     * 決まっているが、それを保証するのはここの仕事。 */
    mov $__bss_start, %rdi
    mov $__bss_end, %rcx
    sub %rdi, %rcx
    xor %eax, %eax
    rep stosb

    mov $stack_top, %rsp
    call kernel_main

    /* kernel_main から戻ってきたら、CPU を止めたままにする。 */
1:  cli
    hlt
    jmp 1b

/* C のコード（と PicoRuby の VM）が使うスタック。 */
.section .bss
.align 16
stack_bottom:
    .skip 64 * 1024
stack_top:
