# カーネルに埋め込む PicoRuby（libmruby.a）のビルド設定。
#
# PicoRuby のビルドは rake で行い、何をどうビルドするかはこのファイルで決める。
# deps/CMakeLists.txt が次のように呼び出す:
#
#   MUSL_DIR=/opt/deps/musl MRUBY_CONFIG=.../deps/build_config.rb rake
#
# 1回の rake で次の2つができる:
#
#   build/mrbc/default/bin/mrbc  Ruby のコードをバイトコードに変換するコンパイラ
#                                （コンテナの中で動くプログラム。PicoRuby が自動で用意する）
#   build/kernel/lib/libmruby.a  カーネルにリンクする PicoRuby の VM

MUSL_DIR = ENV.fetch("MUSL_DIR")
GCC_INCLUDE_DIR = `gcc -print-file-name=include`.strip

# "kernel" という名前のクロスビルド。成果物は build/kernel/ 以下に置かれる。
MRuby::CrossBuild.new("kernel") do |conf|
  conf.toolchain :gcc

  # カーネル本体（cmake/kernel.cmake）と同じフラグでコンパイルする。
  #
  #   -ffreestanding         標準ライブラリがあることを前提にしない
  #   -fno-stack-protector   スタック保護の仕組み（OS の支援が要る）を使わない
  #   -fno-pie               決まったアドレスに置くので位置独立コードにしない
  #   -nostdinc -isystem ... コンテナの /usr/include ではなく musl のヘッダを使う
  #
  # コンテナのヘッダが混ざると、構造体の大きさなどが musl と食い違っても
  # コンパイルもリンクも通ってしまい、実行時に壊れる。
  conf.cc.flags = %W(
    -ffreestanding -fno-stack-protector -fno-pie
    -nostdinc
    -isystem #{MUSL_DIR}/include
    -isystem #{GCC_INCLUDE_DIR}
  )

  # mruby の値の表現を決める定義。すべてのファイルを同じ定義でコンパイルしないと、
  # ファイルごとに mrb_value の形が変わってしまう。カーネル側（CMakeLists.txt の
  # MRUBY_DEFINES）にも同じものを付ける。
  #
  #   MRB_INT64        Ruby の Integer を 64 ビットにする
  #   MRB_NO_BOXING    mrb_value を「型 + 値」の構造体にする
  #   MRB_UTF8_STRING  String を UTF-8 として扱う
  conf.cc.defines += %w(MRB_INT64 MRB_NO_BOXING MRB_UTF8_STRING)

  # PicoRuby の VM（mruby）を使う設定にする。
  #
  # alloc_estalloc: false で、PicoRuby が用意しているメモリ管理（Estalloc）を
  # 使わないようにする。VM のメモリ確保関数 mrb_basic_alloc_func はカーネル側
  # （kernel/kernel.c）で用意する。
  #
  # なお mruby にも標準の mrb_basic_alloc_func（libc の malloc を使う）が
  # 入っていて、カーネルのものと名前がぶつかるので、ビルド後に
  # deps/CMakeLists.txt で libmruby.a から取り除く。
  conf.picoruby(alloc_estalloc: false)
end
