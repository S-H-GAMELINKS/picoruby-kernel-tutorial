# 手順2・3：Ruby で Hello World

この章では、2 章のカーネルに PicoRuby の VM を載せて、3 章で書いた `ruby/hello.rb` を実行します。

```console
container:/work/build$ ninja run
boot ok
Hello World
```

やることは次のとおりです。

1. `hello.rb` をバイトコードの C の配列に変換して、カーネルと一緒にビルドする（CMake）
2. VM が必要とする関数をカーネルに用意する（`kernel/kernel.c`、`kernel/hal.c`）
3. `kernel_main` で VM を起動して、その配列を実行する（`kernel/kernel.c`）

この章で作る・書き換えるファイルは次のとおりです。

```
picoruby-kernel/
├── CMakeLists.txt         （書き換える）
└── kernel/
    ├── kernel64.ld        （書き換える）
    ├── kernel.c           （書き換える）
    └── hal.c
```

## kernel/kernel.c：VM を起動する

`kernel/kernel.c` を次のように書き換えます。

<!-- file: kernel/kernel.c -->
```c
{{#include ../../answer/kernel/kernel.c:all}}
```

部分ごとに見ていきます。

### kernel_main

まず、全体の流れを決める `kernel_main` です。

```c
{{#include ../../answer/kernel/kernel.c:main}}
```

| 関数 | すること |
|---|---|
| `mrb_open()` | VM を作る |
| `mrb_define_method()` | `Kernel` モジュールに `puts` を定義する。これで Ruby のどこからでも `puts` が呼べる |
| `mrb_load_irep()` | バイトコードを読み込んで実行する |
| `mrb_close()` | VM を片付ける |

`hello_bytecode` は、3 章で試した `mrbc -B hello_bytecode` が出力する配列です。
別のファイル（ビルド時に作る `build/hello_bytecode.c`）にあるので、`extern` で宣言してから使います。

```c
{{#include ../../answer/kernel/kernel.c:bytecode}}
```

Ruby のコードで例外が起きると `mrb->exc` に例外オブジェクトが入るので、`inspect` した文字列を表示します。

> **つまずきポイント：mrb_print_error は使えない**
>
> mruby には例外を表示する `mrb_print_error` という関数もありますが、これは C 標準ライブラリの
> `fprintf(stderr, ...)` で出力します。musl の `fprintf` は最終的に OS に書き込みを頼む
> システムコール命令を実行しますが、このカーネルにはそれを受け付ける仕組みがありません。
> CPU 例外が起き、QEMU は何も表示せずに終了してしまいます。

### puts

Ruby の `puts` は、出力先がシリアルポートなのでカーネルで用意します。

```c
{{#include ../../answer/kernel/kernel.c:puts}}
```

`mrb_get_args(mrb, "*", ...)` で、引数をすべて配列として受け取ります。
`mrb_obj_as_string` で文字列にして（`to_s` を呼ぶのと同じです）、`RSTRING_PTR` と `RSTRING_LEN` で中身を取り出して書きます。

### メモリの確保：mrb_basic_alloc_func

VM はメモリが必要になると `mrb_basic_alloc_func` を呼びます。
mruby には libc の `malloc` を使う版が入っていますが、`malloc` は OS からメモリをもらう前提なのでカーネルでは使えません。
そこで 3 章で mruby の版を取り除き（`build_config.rb` の `alloc_estalloc: false` と、`deps/CMakeLists.txt` の `ar d ... allocf.o`）、
ここでカーネルの版を用意しています。

```c
{{#include ../../answer/kernel/kernel.c:alloc}}
```

大きな配列 `heap` の先頭から順に切り出していくだけの、いちばん単純な方法です。解放されたメモリは再利用しません。
Hello World を表示するのに使うのは 60KB ほどなので、256KB あれば足ります。

### 設定の食い違いを防ぐ

ファイルの先頭の `_Static_assert` は、mruby の値 `mrb_value` の形が想定どおりかをコンパイル時に確かめるものです。

```c
{{#include ../../answer/kernel/kernel.c:check}}
```

> **つまずきポイント：設定が食い違ってもリンクは通る**
>
> `MRB_NO_BOXING` などの定義は、`mrb_value` の形を変えます。
> `build_config.rb` で `libmruby.a` に付けた定義をカーネル側で付け忘れると、カーネルと `libmruby.a` で `mrb_value` の形が食い違います。
> それでもコンパイルもリンクも通ってしまい、たとえば `puts "Hello World"` が
> `#<String:0x...>` のような表示になるなど、わかりにくい壊れ方をします。

## kernel/hal.c：VM が求めるその他の関数

残りは、Hello World では使わないけれど、`libmruby.a` が参照しているので、ないとリンクできない関数です。

<!-- file: kernel/hal.c -->
```c
{{#include ../../answer/kernel/hal.c}}
```

## kernel/kernel64.ld：etext と edata を足す

VM は、データが「書き換えられない場所」にあるかどうかを `etext` と `edata` という 2 つの印で判定します。
書き換えられない場所にあるバイトコードや文字列は、コピーせずにそのまま使います。
`kernel/kernel64.ld` を、`.rodata` と `.data` を挟むように 2 行足した次の内容に書き換えます。

<!-- file: kernel/kernel64.ld -->
```
{{#include ../../answer/kernel/kernel64.ld:all}}
```

足したのはこの部分です。

```
{{#include ../../answer/kernel/kernel64.ld:etext}}
```

この 2 つがないと、リンク時に `undefined reference to 'etext'` というエラーになります。

## CMakeLists.txt：バイトコードと VM を組み込む

`CMakeLists.txt` を次のように書き換えます。

<!-- file: CMakeLists.txt -->
```cmake
{{#include ../../answer/CMakeLists.txt:all}}
```

2 章から足したのは 4 か所です。

**hello.rb をバイトコードの C の配列に変換する。**
`hello.rb` を書き換えると、`ninja` が `hello_bytecode.c` を作り直します。

```cmake
{{#include ../../answer/CMakeLists.txt:bytecode}}
```

**カーネルのソースに hal.c と hello_bytecode.c を足す。**

```cmake
{{#include ../../answer/CMakeLists.txt:kernel64}}
```

**PicoRuby の VM と musl をリンクする。**
`MRUBY_DEFINES` は、`build_config.rb` で `libmruby.a` をビルドしたときと同じ設定です。
ヘッダは、3 章の `build_config.rb` と同じように、コンテナの `/usr/include` ではなく musl と PicoRuby のものを使います。

```cmake
{{#include ../../answer/CMakeLists.txt:mruby}}
```

**自動テストを足す。**
`ctest` で、QEMU で起動して `boot ok` と `Hello World` が出るかを確かめられるようにします。
テストの中身は `cmake/boot_test.cmake` に書きます。

<!-- file: cmake/boot_test.cmake -->
```cmake
{{#include ../../answer/cmake/boot_test.cmake}}
```

## 動かしてみる

`CMakeLists.txt` を書き換えたので、`ninja` が自動で CMake の設定を更新してからビルドします。

```console
container:/work/build$ ninja
container:/work/build$ ninja run
boot ok
Hello World
```

`Hello World` と表示されたら完成です。QEMU は **Ctrl-A を押してから X** で終了します。

`ctest` でも確かめられます。

```console
container:/work/build$ ctest
...
100% tests passed, 0 tests failed out of 1
```

## 遊んでみる

`ruby/hello.rb` を書き換えて、もう一度 `ninja run` してみてください。

```ruby
3.times { |i| puts i }
puts [1, 2, 3].map { |x| x * 2 }.inspect
```

例外を起こすと、`kernel_main` の最後で例外の内容が表示されます。

```ruby
raise ArgumentError, "oops"
```

```console
container:/work/build$ ninja run
boot ok
#<ArgumentError: oops>
```
