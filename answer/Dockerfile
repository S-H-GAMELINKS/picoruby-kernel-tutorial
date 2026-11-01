# ANCHOR: all
# チュートリアルの開発環境。
#
# カーネルのビルドと実行に必要なものは全部この中に入っている。
# ホストからは ./container で入る（x86_64 のイメージとして作られる）。
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# gcc/binutils  カーネルと PicoRuby をビルドするコンパイラとリンカ
# cmake/ninja   ビルドシステム
# qemu          カーネルを動かす仮想マシン
# ruby/rake     PicoRuby のビルドに使う
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc binutils libc6-dev \
      cmake ninja-build make \
      qemu-system-x86 \
      ruby rake \
      git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ANCHOR: deps
# musl と PicoRuby をビルドして /opt/deps に置く。
# 手順は deps/CMakeLists.txt に書いてある。
COPY deps /src/deps
RUN cmake -S /src/deps -B /tmp/deps -G Ninja -DDEPS_DIR=/opt/deps \
 && cmake --build /tmp/deps \
 && rm -rf /tmp/deps
# ANCHOR_END: deps

# ホストのシェルと見分けられるように、プロンプトを "container:" で始める。
RUN echo 'PS1="container:\w\$ "' >> /etc/bash.bashrc

WORKDIR /work
# ANCHOR_END: all
