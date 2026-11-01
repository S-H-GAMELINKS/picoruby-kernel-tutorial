# PicoRuby を用意する

この章では、カーネルに Ruby を載せるための部品を用意します。
カーネルのコードには触らず、開発環境（Docker イメージ）に次の 2 つを足します。

| 部品 | 何に使うか |
|---|---|
| **musl** | C の標準ライブラリ。PicoRuby の VM が `memcpy` などを使うため |
| **PicoRuby** | Ruby のコードをバイトコードに変換するコンパイラ `mrbc` と、それを実行する VM `libmruby.a` |

章の終わりには、Ruby のコードを C の配列に変換できるようになります。

```console
container:/work$ /opt/deps/picoruby/bin/mrbc -B hello_bytecode -o /tmp/hello_bytecode.c ruby/hello.rb
```

この章で作るファイルは、`deps/` の 3 つと、書き換える `Dockerfile` です。

```
picoruby-kernel/
├── Dockerfile              （書き換える）
├── deps/
│   ├── versions.cmake
│   ├── build_config.rb
│   └── CMakeLists.txt
└── ruby/hello.rb
```

## なぜ C の標準ライブラリが要るのか

PicoRuby の VM は C で書かれていて、`memcpy`（メモリのコピー）や `strlen`（文字列の長さ）、
`setjmp`/`longjmp`（例外の実装に使う）といった C の標準ライブラリの関数を使います。
OS の上で動くプログラムなら OS に入っている C ライブラリを使いますが、カーネルにはそれがありません。

そこで、小さくて静的リンクしやすい C ライブラリである [musl](https://musl.libc.org/) をカーネルと一緒にリンクします。

## deps/versions.cmake：使うバージョン

musl と PicoRuby のどのバージョンを使うかを決めます。

<!-- file: deps/versions.cmake -->
```cmake
{{#include ../../answer/deps/versions.cmake}}
```

タグ名（`v1.2.5` など）ではなくコミットの SHA で指定しています。
タグは後から付け替えられることがありますが、SHA は変わらないので、いつビルドしても同じソースになります。

## deps/build_config.rb：PicoRuby のビルド設定

PicoRuby は `rake` でビルドし、何をどうビルドするかを Ruby で書いた設定ファイルで決めます。

<!-- file: deps/build_config.rb -->
```ruby
{{#include ../../answer/deps/build_config.rb}}
```

1 回の `rake` で、性格の違う 2 つのものができます。

| できるもの | どこで動くか | 何をするか |
|---|---|---|
| `mrbc` | コンテナの中（ビルド時） | Ruby のコードをバイトコードに変換する |
| `libmruby.a` | カーネルの中（実行時） | バイトコードを実行する VM |

`MRuby::CrossBuild.new("kernel")` の中は、`libmruby.a` の設定です（`mrbc` は PicoRuby が自動で用意します）。
ポイントは 3 つあります。

- **コンパイルのフラグ**：2 章の `cmake/kernel.cmake` と同じく、OS のない環境向けにコンパイルします。
  さらに `-nostdinc` と `-isystem` で、コンテナの `/usr/include` ではなく musl のヘッダを使わせています。
  ここが混ざると、構造体の大きさなどが食い違ったまま、コンパイルもリンクも通ってしまいます。
- **`MRB_INT64` などの定義**：mruby の値（`mrb_value`）の形を決めます。4 章でカーネル側にも同じ定義を付けます。
- **`alloc_estalloc: false`**：VM がメモリを確保する関数を、PicoRuby ではなくカーネルが用意します（4 章で作ります）。

## deps/CMakeLists.txt：musl と PicoRuby をビルドする

ソースの取得からビルド、インストールまでを CMake の `ExternalProject` で書きます。

<!-- file: deps/CMakeLists.txt -->
```cmake
{{#include ../../answer/deps/CMakeLists.txt}}
```

- **musl** は、`configure` → `make` → `make install` という普通の手順でビルドします
- **PicoRuby** は、必要なサブモジュール（VM の mruby と、コンパイラ）だけを取得し、`build_config.rb` を指定して `rake` を実行します
- 最後に、使うものだけを `/opt/deps/picoruby` にまとめます。
  `libmruby.a` から `allocf.o`（mruby 標準のメモリ確保関数）を取り除いているのは、4 章でカーネルが同じ名前の関数を用意するためです

このファイルは、カーネルのビルドではなく Docker イメージを作るときに 1 回だけ実行します。

## Dockerfile：イメージに PicoRuby を入れる

`Dockerfile` を次のように書き換えます。

<!-- file: Dockerfile -->
```dockerfile
{{#include ../../answer/Dockerfile:all}}
```

1 章から変わったのは 2 か所です。

**パッケージを足しました。**

| パッケージ | 使い道 |
|---|---|
| `libc6-dev` | コンテナで動く `mrbc` をビルドするための C の標準ヘッダとライブラリ |
| `make` | musl のビルド |
| `ruby`、`rake` | PicoRuby のビルド |
| `git`、`ca-certificates` | musl と PicoRuby のソースを取得する |

**musl と PicoRuby をビルドする手順を足しました。**

```dockerfile
{{#include ../../answer/Dockerfile:deps}}
```

`deps/` をイメージにコピーして、`deps/CMakeLists.txt` を実行します。
できたものは `/opt/deps` に残り、途中のファイル（`/tmp/deps`）は消します。

## イメージを作り直す

コンテナに入っていたら、一度 `exit` で出てから、もう一度 `./container` を実行します。
`Dockerfile` と `deps/` が変わったので、イメージが作り直されます。
musl と PicoRuby をソースからビルドするので、10 分ほどかかります。

```console
container:/work$ exit
host$ ./container
Docker イメージ picoruby-kernel-tutorial:... を作成します（初回は数分かかります）
...
container:/work$
```

できたものを確かめます。

```console
container:/work$ ls /opt/deps/musl /opt/deps/picoruby
/opt/deps/musl:
bin  include  lib

/opt/deps/picoruby:
bin  include  lib
container:/work$ /opt/deps/picoruby/bin/mrbc --version
mrbc RITE0400 (2026-09-29T10:01:26Z  604666ec) Parser: Prism-1.9.0
```

## 手順2：Ruby で Hello World を書く

カーネルに埋め込む Ruby のコードを書きます。

<!-- file: ruby/hello.rb -->
```ruby
{{#include ../../answer/ruby/hello.rb}}
```

これだけです。

## 手順3の準備：バイトコードに変換してみる

カーネルの中には Ruby のパーサ（ソースコードを読む部分）を入れないので、
ビルド時に `mrbc` で VM が実行する命令列（バイトコード）に変換しておきます。

`-B 名前` を付けると、結果を C の配列として出力してくれます。試してみましょう。

```console
container:/work$ /opt/deps/picoruby/bin/mrbc -B hello_bytecode -o /tmp/hello_bytecode.c ruby/hello.rb
container:/work$ cat /tmp/hello_bytecode.c
#include <stdint.h>
#ifdef __cplusplus
extern
#endif
const uint8_t hello_bytecode[] = {
0x52,0x49,0x54,0x45,0x30,0x34,0x30,0x30,0x00,0x00,0x00,0x5c,0x48,0x53,0x4d,0x4b,
0x30,0x30,0x30,0x30,0x49,0x52,0x45,0x50,0x00,0x00,0x00,0x40,0x30,0x34,0x30,0x30,
0x00,0x00,0x00,0x34,0x00,0x01,0x00,0x04,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x0a,
0x5c,0x02,0x00,0x2f,0x01,0x00,0x01,0x3d,0x01,0x76,0x00,0x01,0x00,0x00,0x0b,0x48,
0x65,0x6c,0x6c,0x6f,0x20,0x57,0x6f,0x72,0x6c,0x64,0x00,0x00,0x01,0x00,0x04,0x70,
0x75,0x74,0x73,0x00,0x45,0x4e,0x44,0x00,0x00,0x00,0x00,0x08,
};
```

先頭の `0x52,0x49,0x54,0x45` は ASCII で `RITE`（mruby のバイトコードの印）です。
途中に `Hello World`（`0x48,0x65,...`）と `puts`（`0x70,0x75,0x74,0x73`）も見えます。

あとはこのファイルをカーネルと一緒にコンパイルすれば、`hello_bytecode` という配列としてカーネルから使えます。
次の章で、それをビルドの手順に組み込み、VM で実行します。
