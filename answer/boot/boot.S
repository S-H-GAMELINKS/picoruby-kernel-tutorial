/* 起動用スタブ：32 ビットで起動し、64 ビットモードに切り替えてカーネルへジャンプする。
 *
 * QEMU の -kernel オプション（Multiboot 方式）でカーネルを起動すると、CPU は
 * 32 ビットのプロテクトモード・ページング無効の状態でここに来る。
 * 一方、カーネル本体は 64 ビットのコードなので、このスタブで次の準備をする。
 *
 *   1. ページテーブルを作る（64 ビットモードではページングが必須）
 *   2. 64 ビットモード（ロングモード）を有効にする
 *   3. 2MB の位置に埋め込んだカーネル本体へジャンプする
 */

/* ---------------------------------------------------------------- Multiboot ヘッダ
 * ファイルの先頭 8KB 以内にこの 3 つの値があると、QEMU は Multiboot 形式の
 * カーネルとして読み込んでくれる。 */
.set MULTIBOOT_MAGIC,    0x1BADB002
.set MULTIBOOT_FLAGS,    0
.set MULTIBOOT_CHECKSUM, -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

.section .multiboot, "a"
.align 4
    .long MULTIBOOT_MAGIC
    .long MULTIBOOT_FLAGS
    .long MULTIBOOT_CHECKSUM

/* ---------------------------------------------------------------- ページテーブル
 * 4 段のページテーブルのうち、2MB ページを使うと 3 段（PML4・PDPT・PD）で済む。
 * それぞれ 1 枚（4KB、512 エントリ）ずつ用意する。 */
.section .bss
.align 4096
pml4: .skip 4096
pdpt: .skip 4096
pd:   .skip 4096

.align 16
stack_bottom:
    .skip 4096
stack_top:

/* ---------------------------------------------------------------- GDT
 * 64 ビットモードに入るには、64 ビット用のコードセグメントが必要。 */
.section .rodata
.align 8
gdt64:
    .quad 0x0000000000000000    /* 0x00: ヌル（必ず先頭に置く） */
    .quad 0x00AF9A000000FFFF    /* 0x08: 64 ビットコード */
    .quad 0x00CF92000000FFFF    /* 0x10: データ */
gdt64_end:
gdt64_ptr:
    .word gdt64_end - gdt64 - 1
    .long gdt64

/* 先頭から何 MB をマップするか。カーネル本体（2MB から始まる）がこの範囲に
 * 収まっている必要がある。kernel/kernel64.ld で同じ値をチェックしている。 */
.set MAPPED_MB,  32
.set PAGE_2MB,   0x200000

.section .text
.code32
.global _start
_start:
    cli
    mov $stack_top, %esp

    /* BSS（ページテーブルとスタック）をゼロで埋める。 */
    mov $__bss_start, %edi
    mov $__bss_end, %ecx
    sub %edi, %ecx
    xor %eax, %eax
    rep stosb

    /* ---- 1. ページテーブルを作る
     * 仮想アドレス = 物理アドレス になるように対応付ける（恒等マップ）。
     *
     *   PML4[0] -> PDPT
     *   PDPT[0] -> PD
     *   PD[i]   -> 物理アドレス i * 2MB  （i = 0 .. 15、合計 32MB）
     *
     * 下位ビットはフラグ: 0x1 = 存在する、0x2 = 書き込み可、0x80 = 2MB ページ */
    mov $pdpt, %eax
    or  $0x3, %eax
    mov %eax, pml4

    mov $pd, %eax
    or  $0x3, %eax
    mov %eax, pdpt

    mov $pd, %edi
    mov $0x83, %eax                   /* 物理アドレス 0 から、存在・書き込み可・2MB */
    mov $(MAPPED_MB * 0x100000 / PAGE_2MB), %ecx
1:  mov %eax, (%edi)
    add $PAGE_2MB, %eax
    add $8, %edi
    loop 1b

    /* ---- 2. 64 ビットモードを有効にする */

    /* CR4: PAE（ビット 5）は 64 ビットモードに必須。
     *      OSFXSR（ビット 9）と OSXMMEXCPT（ビット 10）は SSE 命令を使うため。
     *      C コンパイラは x86_64 向けのコードに SSE 命令を普通に使う。 */
    mov %cr4, %eax
    or  $(1 << 5 | 1 << 9 | 1 << 10), %eax
    mov %eax, %cr4

    /* CR3: PML4 の場所を CPU に教える。 */
    mov $pml4, %eax
    mov %eax, %cr3

    /* EFER レジスタ（MSR 0xC0000080）の LME（ビット 8）を立てる。 */
    mov $0xC0000080, %ecx
    rdmsr
    or  $(1 << 8), %eax
    wrmsr

    /* CR0: ページング（ビット 31）を有効にすると、64 ビットモードが動き出す。 */
    mov %cr0, %eax
    or  $(1 << 31), %eax
    mov %eax, %cr0

    /* 64 ビット用の GDT を読み込み、64 ビットコードセグメント（0x08）へジャンプする。 */
    lgdt gdt64_ptr
    ljmp $0x08, $long_mode

.code64
long_mode:
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss

    /* ---- 3. カーネル本体へジャンプする */
    mov $0x200000, %rax
    jmp *%rax

/* ---------------------------------------------------------------- カーネル本体
 * 64 ビットのカーネル（kernel64.bin）をそのまま埋め込む。
 * boot/multiboot.ld で、このセクションを 2MB の位置に置いている。 */
.section .kernel64, "a"
.incbin "kernel64.bin"
