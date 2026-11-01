# PicoRuby と C でカーネルを書く

C で起動する最小のカーネルに [PicoRuby](https://github.com/picoruby/picoruby) の VM を載せて、
Ruby で `Hello World` を表示するまでを、空のディレクトリから自分の手で作るチュートリアルです。

```
boot ok
Hello World
```

**チュートリアル: https://s-h-gamelinks.github.io/picoruby-kernel-tutorial/**

1. 開発環境を作る（Docker）
2. 手順1：C で起動する最小のカーネル
3. PicoRuby を用意する
4. 手順2・3：Ruby で Hello World

必要なのは Docker だけです。

## このリポジトリの中身

```
docs/      チュートリアルの本文（mdBook）
answer/    完成形のコード。うまく動かないときに見比べる
```

完成形をそのまま動かすこともできます。

```console
host$ cd answer
host$ ./container
container:/work$ cmake --preset default
container:/work$ cd build
container:/work/build$ ninja run     # Ctrl-A を押してから X で終了
boot ok
Hello World
```

## チュートリアルを手元で読む

[mdBook](https://rust-lang.github.io/mdBook/) があれば、手元で表示できます。

```console
host$ mdbook serve docs --open
```

`main` ブランチに push すると、`.github/workflows/pages.yml` が GitHub Pages にデプロイします。
初回だけ、リポジトリの Settings → Pages で Source を「GitHub Actions」にしてください。

## ライセンス

チュートリアルの本文（`docs/`）とコード（`answer/`）は、どちらも [MIT License](LICENSE) で公開しています。

musl・PicoRuby・mruby のソースコードはこのリポジトリに含まれておらず、Docker イメージを作るときにダウンロードされます。
いずれも MIT License です。
