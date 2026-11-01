# 開発環境を作る

カーネルを作るには、C コンパイラやアセンブラ、リンカ、仮想マシン（QEMU）が必要です。
これらを自分のマシンに直接入れるかわりに、Docker のコンテナの中に開発環境を作ります。
この章の終わりには、次のようにコンテナの中のシェルに入れるようになります。

```console
host$ ./container
container:/work$
```

## 作業ディレクトリを作る

まず、カーネルを作るためのディレクトリを作ります。名前は何でも構いません。
以降、ファイルのパスはすべてこのディレクトリからの相対パスで書きます。

```console
host$ mkdir picoruby-kernel
host$ cd picoruby-kernel
```

## Dockerfile

開発環境のイメージを作る `Dockerfile` を作ります。

<!-- file: Dockerfile -->
```dockerfile
# チュートリアルの開発環境。
#
# カーネルのビルドと実行に必要なものは全部この中に入っている。
# ホストからは ./container で入る（x86_64 のイメージとして作られる）。
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# gcc/binutils  カーネルをビルドするコンパイラとリンカ
# cmake/ninja   ビルドシステム
# qemu          カーネルを動かす仮想マシン
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc binutils \
      cmake ninja-build \
      qemu-system-x86 \
 && rm -rf /var/lib/apt/lists/*

# ホストのシェルと見分けられるように、プロンプトを "container:" で始める。
RUN echo 'PS1="container:\w\$ "' >> /etc/bash.bashrc

WORKDIR /work
```

入れているのは 4 種類です。

| パッケージ | 使い道 |
|---|---|
| `gcc` | C コンパイラ。アセンブリのファイル（`.S`）もこれで扱う |
| `binutils` | リンカ `ld` や、ELF から中身を取り出す `objcopy` |
| `cmake`、`ninja-build` | ビルドの手順を書いて、実行する |
| `qemu-system-x86` | x86_64 の仮想マシン。作ったカーネルをここで起動する |

PicoRuby のビルドに必要なものは、3 章で足します。

## container スクリプト

毎回 `docker build` や `docker run` を打つのは面倒なので、コンテナに入るためのスクリプト `container` を作ります。

<!-- file: container -->
```bash
{{#include ../../answer/container}}
```

作ったら実行できるようにしておきます。

```console
host$ chmod +x container
```

このスクリプトがしていることは 2 つです。

**イメージを用意する。**
`Dockerfile`（と、3 章で作る `deps/` の中身）からハッシュ値を計算して、イメージのタグにしています。
そのタグのイメージがまだなければ `docker build` します。
ファイルを書き換えるとタグが変わるので、必要なときだけイメージが作り直されます。

**コンテナを起動する。**
`-v "$PWD":/work` で、このディレクトリをコンテナの `/work` にマウントします。
ホストで編集したファイルが、そのままコンテナの中から見えます。
`-u` でホストと同じユーザーとして動かすので、コンテナの中で作ったファイルもホストのユーザーのものになります。

`--platform linux/amd64` は、イメージを x86_64 向けに作るための指定です。
gcc はコンテナと同じアーキテクチャ向けのコードを出すので、x86_64 のカーネルを作るにはコンテナも x86_64 である必要があります。
ARM の Mac などでは Docker がエミュレーションで動かすので、そのぶん時間がかかります。

## コンテナに入る

```console
host$ ./container
Docker イメージ picoruby-kernel-tutorial:... を作成します（初回は数分かかります）
...
container:/work$
```

プロンプトが `container:/work$` に変わればコンテナの中です。道具が揃っているか確かめておきましょう。

```console
container:/work$ gcc --version
gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
...
container:/work$ qemu-system-x86_64 --version
QEMU emulator version 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18)
...
```

コンテナから出るときは `exit` です。

## コマンドを打つ場所

以降は、コマンドを打つ場所をプロンプトで区別します。

| プロンプト | 場所 | 打つコマンド |
|---|---|---|
| `host$` | 自分のマシン | `./container` |
| `container:/work$` | コンテナの中 | `cmake`、`ninja` など、それ以外すべて |

ファイルの編集はホストの好きなエディタで行い、ビルドと実行はコンテナの中で行います。

```
ホスト                           コンテナ
picoruby-kernel/  ◀── 同じ ──▶  /work/
  エディタで編集する                cmake / ninja / QEMU を動かす
```
