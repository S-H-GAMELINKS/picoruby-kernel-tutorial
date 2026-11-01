# ANCHOR: all
cmake_minimum_required(VERSION 3.25)
project(picoruby_kernel_tutorial LANGUAGES C ASM)

# ANCHOR: tools
find_program(OBJCOPY objcopy REQUIRED)
find_program(LD      ld      REQUIRED)
find_program(QEMU    qemu-system-x86_64 REQUIRED)
# ANCHOR_END: tools

# ANCHOR: bytecode
set(DEPS_DIR /opt/deps CACHE PATH "musl と PicoRuby の場所")
set(MRBC ${DEPS_DIR}/picoruby/bin/mrbc)

# ---------------------------------------------------------------- Ruby のコード → C の配列
# ruby/hello.rb をバイトコードに変換し、hello_bytecode という名前の C の配列にする。
add_custom_command(
  OUTPUT  hello_bytecode.c
  COMMAND ${MRBC} -B hello_bytecode -o hello_bytecode.c ${CMAKE_SOURCE_DIR}/ruby/hello.rb
  DEPENDS ${CMAKE_SOURCE_DIR}/ruby/hello.rb
)
# ANCHOR_END: bytecode

# ---------------------------------------------------------------- 64 ビットのカーネル本体
# ANCHOR: kernel64
add_executable(kernel64
  kernel/entry64.S
  kernel/kernel.c
  kernel/serial.c
  kernel/hal.c
  ${CMAKE_CURRENT_BINARY_DIR}/hello_bytecode.c
)
# ANCHOR_END: kernel64

# ANCHOR: mruby
# libmruby.a をビルドしたときと同じ mruby の設定（deps/build_config.rb）。
# 食い違うと mrb_value などの形が変わり、正しく動かない。
set(MRUBY_DEFINES
  MRB_INT64
  MRB_NO_BOXING
  MRB_UTF8_STRING
  MRB_CONSTRAINED_BASELINE_PROFILE=1
  MRB_USE_TASK_SCHEDULER
  PICORB_VM_MRUBY
)
target_compile_definitions(kernel64 PRIVATE ${MRUBY_DEFINES})

# ヘッダはコンテナの /usr/include ではなく、musl と PicoRuby のものを使う。
execute_process(COMMAND ${CMAKE_C_COMPILER} -print-file-name=include
                OUTPUT_VARIABLE GCC_INCLUDE_DIR OUTPUT_STRIP_TRAILING_WHITESPACE)
target_compile_options(kernel64 PRIVATE $<$<COMPILE_LANGUAGE:C>:-nostdinc>)
target_include_directories(kernel64 SYSTEM PRIVATE
  ${DEPS_DIR}/picoruby/include
  ${DEPS_DIR}/musl/include
  ${GCC_INCLUDE_DIR}
)

# PicoRuby の VM と、それが使う C 標準ライブラリ（musl）をリンクする。
target_link_libraries(kernel64 PRIVATE
  ${DEPS_DIR}/picoruby/lib/libmruby.a
  ${DEPS_DIR}/musl/lib/libc.a
)
# ANCHOR_END: mruby

# ANCHOR: link
set_target_properties(kernel64 PROPERTIES SUFFIX ".elf")
# -z noexecstack・--no-warn-rwx-segments・--build-id=none は、OS の上で動くプログラム向けの
# 警告や情報を出さないようにするため。
target_link_options(kernel64 PRIVATE
  -T ${CMAKE_SOURCE_DIR}/kernel/kernel64.ld
  -Wl,-z,noexecstack -Wl,--no-warn-rwx-segments -Wl,--build-id=none
)
set_property(TARGET kernel64 APPEND PROPERTY LINK_DEPENDS ${CMAKE_SOURCE_DIR}/kernel/kernel64.ld)

# ELF から中身だけを取り出した、ただのバイト列にする。
add_custom_command(
  OUTPUT  kernel64.bin
  COMMAND ${OBJCOPY} -O binary $<TARGET_FILE:kernel64> kernel64.bin
  DEPENDS kernel64
)

# ---------------------------------------------------------------- 起動用スタブ
# boot.S は 32 ビットのコードなので、-m32 でアセンブルする。
# kernel64.bin を .incbin で埋め込むので、そのディレクトリを -I で渡す。
add_custom_command(
  OUTPUT  boot.o
  COMMAND ${CMAKE_C_COMPILER} -m32 -c
          -I ${CMAKE_CURRENT_BINARY_DIR}
          ${CMAKE_SOURCE_DIR}/boot/boot.S -o boot.o
  DEPENDS ${CMAKE_SOURCE_DIR}/boot/boot.S ${CMAKE_CURRENT_BINARY_DIR}/kernel64.bin
)

add_custom_command(
  OUTPUT  kernel.elf
  COMMAND ${LD} -m elf_i386 -T ${CMAKE_SOURCE_DIR}/boot/multiboot.ld
          -z noexecstack boot.o -o kernel.elf
  DEPENDS boot.o ${CMAKE_SOURCE_DIR}/boot/multiboot.ld
)

add_custom_target(kernel ALL DEPENDS kernel.elf)

# ---------------------------------------------------------------- 実行
# ninja run で QEMU を起動する。終了は Ctrl-A を押してから X。
#   -display none        画面のウィンドウを出さない
#   -serial mon:stdio    シリアルポートをターミナルにつなぐ（Ctrl-A で QEMU の操作もできる）
#   -no-reboot           CPU 例外で落ちたら、再起動せずに QEMU を終了する
add_custom_target(run
  COMMAND ${QEMU} -kernel kernel.elf -display none -serial mon:stdio -no-reboot
  DEPENDS kernel
  USES_TERMINAL
)
# ANCHOR_END: link

# ---------------------------------------------------------------- テスト
# ctest で、QEMU で起動して "boot ok" と "Hello World" が出るかを確かめる。
enable_testing()
add_test(NAME boot
  COMMAND ${CMAKE_COMMAND}
          -DQEMU=${QEMU} -DKERNEL=${CMAKE_CURRENT_BINARY_DIR}/kernel.elf
          -P ${CMAKE_SOURCE_DIR}/cmake/boot_test.cmake
)
# ANCHOR_END: all
