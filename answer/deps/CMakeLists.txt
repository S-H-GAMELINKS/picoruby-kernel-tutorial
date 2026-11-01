# カーネルが使うライブラリ（musl と PicoRuby）をビルドして DEPS_DIR に置く。
#
# Docker イメージを作るときに Dockerfile から1回だけ実行される:
#
#   cmake -S deps -B /tmp/deps -G Ninja -DDEPS_DIR=/opt/deps
#   cmake --build /tmp/deps
#
# 同じディレクトリの versions.cmake（バージョン）と build_config.rb
# （PicoRuby のビルド設定）を使う。
#
# できあがる DEPS_DIR の中身:
#
#   musl/include/      C の標準ヘッダ（string.h など）
#   musl/lib/libc.a    memcpy や strlen などの実装
#   picoruby/bin/mrbc  Ruby のコードをバイトコードに変換するコンパイラ
#   picoruby/include/  mruby.h などの VM のヘッダ
#   picoruby/lib/libmruby.a  PicoRuby の VM

cmake_minimum_required(VERSION 3.25)
project(picoruby_kernel_deps NONE)

include(ExternalProject)
include(${CMAKE_CURRENT_LIST_DIR}/versions.cmake)

set(DEPS_DIR /opt/deps CACHE PATH "ライブラリのインストール先")
set(BUILD_CONFIG ${CMAKE_CURRENT_LIST_DIR}/build_config.rb)
cmake_host_system_information(RESULT NPROC QUERY NUMBER_OF_LOGICAL_CORES)

# ---------------------------------------------------------------- musl
# PicoRuby の VM は memcpy・strlen・setjmp などの C 標準ライブラリの関数を使う。
# カーネルには OS がないので、それらを musl から借りてくる。
ExternalProject_Add(musl
  GIT_REPOSITORY ${MUSL_URL}
  GIT_TAG        ${MUSL_REF}
  UPDATE_COMMAND ""
  BUILD_IN_SOURCE 1   # musl の configure はソースツリー内でのビルドだけに対応している
  CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=-fno-stack-protector
      ./configure --prefix=${DEPS_DIR}/musl --disable-shared
  BUILD_COMMAND   make -j${NPROC}
  INSTALL_COMMAND make install
)

# ---------------------------------------------------------------- PicoRuby
# PicoRuby には多くのサブモジュールがあるが、使うのは VM（mruby）と
# コンパイラ（mruby-compiler・mruby-bin-mrbc）だけなので、それだけを取得する。
# mruby-compiler の中の prism（Ruby のパーサ）は再帰的に取得される。
set(PICORUBY_SUBMODULES
  mrbgems/picoruby-mruby/lib/mruby
  mrbgems/mruby-compiler
  mrbgems/mruby-bin-mrbc
)

ExternalProject_Add(picoruby
  DEPENDS musl
  GIT_REPOSITORY ${PICORUBY_URL}
  GIT_TAG        ${PICORUBY_REF}
  GIT_SUBMODULES ${PICORUBY_SUBMODULES}
  GIT_SUBMODULES_RECURSE ON
  UPDATE_COMMAND ""
  BUILD_IN_SOURCE 1   # PicoRuby の rake はソースツリー内の build/ に成果物を置く
  CONFIGURE_COMMAND ""
  BUILD_COMMAND ${CMAKE_COMMAND} -E env
      MUSL_DIR=${DEPS_DIR}/musl
      MRUBY_CONFIG=${BUILD_CONFIG}
      rake -j${NPROC}
  # 使うものだけを DEPS_DIR/picoruby にまとめる。
  #   ヘッダは2か所に分かれている: mruby 本体と、ビルド時に生成されるもの（presym）。
  #
  # libmruby.a からは allocf.o（mruby 標準のメモリ確保関数 mrb_basic_alloc_func）を
  # 取り除く。カーネルが自分の mrb_basic_alloc_func を用意するので、
  # 残しておくと名前がぶつかってリンクできない。
  INSTALL_COMMAND
          ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/build/mrbc/default/bin/mrbc ${DEPS_DIR}/picoruby/bin/mrbc
  COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/build/kernel/lib/libmruby.a ${DEPS_DIR}/picoruby/lib/libmruby.a
  COMMAND ar d ${DEPS_DIR}/picoruby/lib/libmruby.a allocf.o
  COMMAND ${CMAKE_COMMAND} -E copy_directory
          <SOURCE_DIR>/mrbgems/picoruby-mruby/lib/mruby/include ${DEPS_DIR}/picoruby/include
  COMMAND ${CMAKE_COMMAND} -E copy_directory
          <SOURCE_DIR>/build/kernel/include ${DEPS_DIR}/picoruby/include
)
