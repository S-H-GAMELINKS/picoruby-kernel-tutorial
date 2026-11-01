# はじめに

このチュートリアルでは、OS のないマシン（QEMU の仮想マシン）の上で Ruby のコードを動かし、
`Hello World` を表示するカーネルを、空のディレクトリから自分の手で作ります。

```
boot ok
Hello World
```

`boot ok` は C で書いたカーネルが、`Hello World` はカーネルに埋め込んだ Ruby のコードが表示したものです。

## 作るもの

| 章 | 作るもの | 章の終わりに見えるもの |
|---|---|---|
| [開発環境を作る](01-setup.md) | Docker の開発環境 | コンテナの中のシェル |
| [手順1：C で起動する最小のカーネル](02-minimal-kernel.md) | 64 ビットモードに切り替えて C を呼ぶカーネル | `boot ok` |
| [PicoRuby を用意する](03-picoruby.md) | C の標準ライブラリ（musl）と PicoRuby のビルド | Ruby のコードから作ったバイトコード |
| [手順2・3：Ruby で Hello World](04-hello-ruby.md) | PicoRuby の VM を載せたカーネル | `Hello World` |

各章では、作るファイルの中身を全文示します。順番にファイルを作り（書き写すかコピーして）、
説明を読み、ビルドして動かす、という流れで進みます。

## Ruby をどうやってカーネルで動かすのか

[PicoRuby](https://github.com/picoruby/picoruby) は、マイコンのような小さな環境向けの Ruby 処理系です。
VM は mruby で、OS がなくても動くように作られています。

カーネルの中には Ruby のパーサ（ソースコードを読む部分）を入れません。
ビルド時に PicoRuby のコンパイラで Ruby のコードを **バイトコード**（VM が実行する命令列）に変換し、
それを C の配列としてカーネルに埋め込みます。カーネルは PicoRuby の VM を起動して、その配列を実行します。

OS がないので、PicoRuby が必要とするもののうち足りないものはカーネルが用意します。

| PicoRuby が必要とするもの | 用意する方法 |
|---|---|
| メモリの確保 | カーネルの中の大きな配列から切り出す |
| `puts` の出力先 | C で `puts` を定義して、シリアルポートに書く |
| `memcpy` などの C 標準ライブラリ | [musl libc](https://musl.libc.org/) を一緒にリンクする |

## 起動の流れ

完成したカーネルは、次の順に動きます。

```
QEMU（-kernel kernel.elf）
  │  32 ビットモードで起動
  ▼
boot/boot.S         ページテーブルを作り、64 ビットモードに切り替える
  │  2MB の位置へジャンプ
  ▼
kernel/entry64.S    スタックを用意する
  │  call kernel_main
  ▼
kernel/kernel.c     シリアルポートに "boot ok" を出す
  │                 PicoRuby の VM を起動し、埋め込んだバイトコードを実行する
  ▼
ruby/hello.rb       puts "Hello World"
  │  C で定義した puts が呼ばれる
  ▼
kernel/serial.c     シリアルポートに書く → ターミナルに表示される
```

## 前提知識と必要なもの

- Ruby が書けること
- C が少し読めること（ポインタと配列がわかれば十分です）
- OS 開発やアセンブリの経験は不要です。必要なことはその都度説明します

必要なソフトウェアは Docker だけです。コンパイラや QEMU は、1 章で作る Docker イメージに入れます。

## 完成形のコード

完成したコードは、このチュートリアルのリポジトリの
[`answer/`](https://github.com/S-H-GAMELINKS/picoruby-kernel-tutorial/tree/main/answer) にあります。
うまく動かないときは、自分のファイルと見比べてください。

## この先

ここで作るカーネルは、Ruby のコードを 1 回実行して止まるだけです。
PicoRuby でファイルシステムやネットワークまで書いたカーネルの例として、
[picoruby-kernel](https://github.com/S-H-GAMELINKS/picoruby-kernel) があります。
