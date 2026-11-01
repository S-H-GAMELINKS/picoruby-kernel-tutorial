# 手順1：C で起動する最小のカーネル

この章では、QEMU で起動してシリアルポートに `boot ok` と表示するだけのカーネルを作ります。
Ruby はまだ出てきません。

```console
container:/work/build$ ninja run
boot ok
```

## 全体の流れ

QEMU の `-kernel` オプションでカーネルを渡すと、CPU は **32 ビットモード** でカーネルの先頭から動き始めます。
一方、C のコードは 64 ビットでコンパイルします。そこでカーネルを 2 つの部分に分けます。

| ファイル | ビット数 | 役割 |
|---|---|---|
| `boot/boot.S` | 32 → 64 | 64 ビットモードに切り替えて、カーネル本体にジャンプする |
| `kernel/entry64.S` | 64 | スタックを用意して、C の `kernel_main` を呼ぶ |
| `kernel/kernel.c`、`kernel/serial.c` | 64 | `boot ok` をシリアルポートに出す |

ビルドの流れは次のとおりです。64 ビットのカーネル本体を先に作り、それを 32 ビットの起動用プログラムに丸ごと埋め込みます。

```
kernel/*.c, entry64.S ──▶ kernel64.elf ──▶ kernel64.bin ─┐
                         （ELF）            （中身だけ）   │ .incbin で埋め込む
boot/boot.S ─────────────────────────────────────────────┴─▶ kernel.elf
                                                            （QEMU に渡すもの）
```

この章で作るファイルは次の 10 個です。

```
picoruby-kernel/
├── Dockerfile, container      （1 章で作ったもの）
├── CMakeLists.txt
├── CMakePresets.json
├── cmake/kernel.cmake
├── boot/boot.S
├── boot/multiboot.ld
└── kernel/
    ├── entry64.S
    ├── kernel64.ld
    ├── kernel.h
    ├── serial.c
    └── kernel.c
```

## boot/boot.S：64 ビットモードへの切り替え

最初に、電源が入って（QEMU が起動して）最初に動くプログラムを作ります。

<!-- file: boot/boot.S -->
```asm
{{#include ../../answer/boot/boot.S}}
```

上から順に見ていきます。

### Multiboot ヘッダ

QEMU の `-kernel` は、**Multiboot** という規格に沿ったカーネルを読み込めます。
ファイルの先頭近くに、決まった値（マジックナンバー `0x1BADB002`）とフラグ、チェックサムの 3 つを置くだけです。
チェックサムは「3 つを足すと 0 になる値」です。

### ページテーブル

64 ビットモードでは、**ページング**（仮想アドレスを物理アドレスに変換する仕組み）を必ず使います。
変換の対応表がページテーブルです。

ここでは一番単純な形にします。

- **恒等マップ**：仮想アドレス = 物理アドレス。アドレスを変換していることを意識せずに済みます
- **2MB ページ**：本来 4 段あるテーブルが 3 段（PML4 → PDPT → PD）で済みます
- **先頭 32MB だけ**：PD のエントリを 16 個（16 × 2MB）埋めます。カーネルはこの範囲に収まります

```
PML4[0] ──▶ PDPT[0] ──▶ PD[0]  ──▶ 物理 0MB〜2MB
                        PD[1]  ──▶ 物理 2MB〜4MB   ← カーネル本体はここから
                        ...
                        PD[15] ──▶ 物理 30MB〜32MB
```

### 64 ビットモードを有効にする

4 つの手順で切り替えます。

1. `CR4` の PAE ビットを立てる（64 ビットモードの前提条件）
2. `CR3` に PML4 のアドレスを入れる
3. `EFER` レジスタの LME ビットを立てる（「64 ビットモードを使う」という宣言）
4. `CR0` の PG ビットを立ててページングを有効にする。この瞬間に 64 ビットモードになる

`CR4` では SSE 命令を使うためのビット（OSFXSR と OSXMMEXCPT）も立てています。
gcc は x86_64 向けのコードに SSE 命令を普通に使うので、これがないと C のコードの途中で CPU 例外が起きます。

最後に 64 ビット用の GDT（セグメントの定義表）を読み込み、`ljmp` で 64 ビットのコードにジャンプします。
あとは 2MB の位置にあるカーネル本体へジャンプするだけです。

### カーネル本体の埋め込み

ファイルの最後の `.incbin "kernel64.bin"` で、64 ビットのカーネル本体（このあと作ります）をそのまま埋め込んでいます。

## boot/multiboot.ld：起動用プログラムの配置

`boot.S` の各部分をメモリのどこに置くかを、**リンカスクリプト** で決めます。

<!-- file: boot/multiboot.ld -->
```
{{#include ../../answer/boot/multiboot.ld}}
```

起動用プログラムは 1MB の位置に、埋め込んだカーネル本体（`.kernel64`）はちょうど 2MB の位置に置きます。
`boot.S` は 2MB へジャンプするので、ここがずれると起動しません。

## kernel/entry64.S：C を呼ぶ準備

ここから 64 ビットのカーネル本体です。2MB の位置に置かれ、`boot.S` からジャンプしてきます。

<!-- file: kernel/entry64.S -->
```asm
{{#include ../../answer/kernel/entry64.S}}
```

C の関数を呼ぶ前に、2 つの準備が必要です。

- **BSS をゼロで埋める**：C では「初期値を書かないグローバル変数は 0」と決まっていますが、それを保証するのはこのコードです
- **スタックを用意する**：関数呼び出しや局所変数に使います

## kernel/kernel64.ld：カーネル本体の配置

カーネル本体のリンカスクリプトです。4 章で 2 行足します。

<!-- file: kernel/kernel64.ld -->
```
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
  .rodata : { *(.rodata*) }
  .data   : { *(.data*) }

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
```

- `. = 2M;` でカーネル本体を 2MB の位置に置きます
- `.text.entry`（entry64.S の `_start64`）を先頭に置くので、2MB ちょうどが入り口になります
- 最後の `ASSERT` で、カーネルが boot.S のマップした 32MB に収まっているかをビルド時に確かめます
- `/DISCARD/` の意味は、この章の最後の「つまずきポイント」で説明します

## kernel/kernel.h と kernel/serial.c：シリアルポートへの出力

カーネルの出力先は、シリアルポート（COM1）にします。
QEMU を `-serial mon:stdio` 付きで起動すると、COM1 に書いた文字がそのままターミナルに表示されます。

まず、カーネルの C のファイルが共通で使うヘッダです。

<!-- file: kernel/kernel.h -->
```c
{{#include ../../answer/kernel/kernel.h}}
```

シリアルポートは I/O ポート `0x3F8`〜`0x3FF` で操作します。
x86 では I/O ポートの読み書きに専用の命令（`in` と `out`）を使うので、それぞれを呼ぶ小さな関数 `inb` と `outb` を用意しています。

次に、シリアルポートを使う関数です。

<!-- file: kernel/serial.c -->
```c
{{#include ../../answer/kernel/serial.c}}
```

`serial_init` で速度などを設定したら、あとは送信バッファが空くのを待って 1 バイトずつ書くだけです。

## kernel/kernel.c：boot ok

`entry64.S` から呼ばれる `kernel_main` です。

<!-- file: kernel/kernel.c -->
```c
#include "kernel.h"

void
kernel_main(void)
{
    serial_init();
    serial_puts("boot ok\n");
}
```

## CMake でビルドする

ここからはビルドの設定です。ファイルは 3 つあります。

### cmake/kernel.cmake：OS のない環境向けにビルドする

普通の CMake は「いま動いている OS 向けのプログラム」を作ろうとします。
そこで、OS のない x86_64 向けにビルドすることを CMake に教える **ツールチェーンファイル** を作ります。

<!-- file: cmake/kernel.cmake -->
```cmake
{{#include ../../answer/cmake/kernel.cmake}}
```

### CMakePresets.json：cmake の設定をまとめる

`cmake` に毎回オプションを並べるかわりに、設定を `CMakePresets.json` に書いておきます。

<!-- file: CMakePresets.json -->
```json
{{#include ../../answer/CMakePresets.json}}
```

| 設定 | 意味 |
|---|---|
| `"generator": "Ninja"` | ビルドに Ninja を使う |
| `"binaryDir"` | ビルドの成果物を `build/` に置く |
| `"toolchainFile"` | `cmake/kernel.cmake` を読み込む |

### CMakeLists.txt：ビルドの手順

<!-- file: CMakeLists.txt -->
```cmake
cmake_minimum_required(VERSION 3.25)
project(picoruby_kernel_tutorial LANGUAGES C ASM)

{{#include ../../answer/CMakeLists.txt:tools}}

# ---------------------------------------------------------------- 64 ビットのカーネル本体
add_executable(kernel64
  kernel/entry64.S
  kernel/kernel.c
  kernel/serial.c
)

{{#include ../../answer/CMakeLists.txt:link}}
```

- `kernel64` は CMake の普通の実行ファイルとしてビルドし、リンカスクリプトに `kernel64.ld` を使います
- `objcopy -O binary` で、ELF からメモリに置く中身だけを取り出した `kernel64.bin` を作ります
- `boot.S` は 32 ビットのコードなので、`-m32` を付けてアセンブルし、`ld -m elf_i386` でリンクします
- `ninja run` で QEMU を起動します。`-serial mon:stdio` でシリアルポートをターミナルにつなぎます。
  `-no-reboot` は、CPU 例外でカーネルが落ちたときに再起動を繰り返さず、QEMU を終了させるためです

## 動かしてみる

コンテナに入って、`cmake --preset default` でビルド用のディレクトリ `build/` を作ります。これは最初に 1 回だけです。

```console
host$ ./container
container:/work$ cmake --preset default
...
-- Build files have been written to: /work/build
```

`build/` に移って、ビルドして起動します。

```console
container:/work$ cd build
container:/work/build$ ninja
[7/7] Generating kernel.elf
container:/work/build$ ninja run
boot ok
```

`boot ok` と表示されたら成功です。カーネルは `kernel_main` から戻ると `hlt` で止まるので、
**Ctrl-A を押してから X** を押して QEMU を終了してください。

> **つまずきポイント：何も表示されずに QEMU が終了する**
>
> カーネルが CPU 例外で落ちると、`-no-reboot` を付けているので QEMU は何も表示せずに終了します。
> 原因を調べるときは、QEMU に `-d int` を付けると、起きた CPU 例外とそのときのアドレスが表示されます。
>
> ```console
> container:/work/build$ qemu-system-x86_64 -kernel kernel.elf -display none -serial stdio -no-reboot -d int
> ```
>
> たとえば `kernel64.ld` の `/DISCARD/` の行を消すと、この失敗が起きます。
> gcc はオブジェクトファイルに実行には使わない情報（`.note.gnu.property` など）を付け足し、
> それが 2MB の先頭に置かれて、CPU がそれを命令として実行してしまうためです。

## やり直したいとき

ビルドがおかしくなったときは、影響の小さい順に次の方法でやり直せます。
どの方法でも、自分で書いたソースコードは消えません。

| やりたいこと | コマンド | 消えるもの |
|---|---|---|
| ビルドの成果物だけ消して作り直す | `container:/work/build$ ninja clean` | `kernel.elf` など、ビルドでできたファイル |
| CMake の設定からやり直す | `container:/work$ cmake --preset default --fresh` | `build/` の中の CMake の設定 |
| 開発環境ごと作り直す | `host$ ./container --rebuild` | Docker イメージ |
