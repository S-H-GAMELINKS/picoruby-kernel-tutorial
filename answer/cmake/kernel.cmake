# カーネルをビルドするためのツールチェーンファイル。
#
# CMakePresets.json の "toolchainFile" から読み込まれる。普通の CMake は
# 「いま動いている OS 向けのプログラム」を作ろうとするので、ここで
# 「OS のない x86_64 向け」にビルドすることを CMake に教える。

# OS なし（Generic）の x86_64。
set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# C もアセンブリも gcc でコンパイルする。
set(CMAKE_C_COMPILER   gcc)
set(CMAKE_ASM_COMPILER gcc)

# -ffreestanding       標準ライブラリがあることを前提にしない
# -fno-stack-protector スタック保護の仕組み（OS の支援が要る）を使わない
# -fno-pie             決まったアドレス（2MB）に置くので位置独立コードにしない
set(CMAKE_C_FLAGS_INIT   "-ffreestanding -fno-stack-protector -fno-pie")
set(CMAKE_ASM_FLAGS_INIT "-fno-pie")

# -nostdlib  OS 向けのスタートアップコード（crt1.o など）や libc をリンクしない
# -static    共有ライブラリを使わない
# -no-pie    位置独立実行ファイルにしない
set(CMAKE_EXE_LINKER_FLAGS_INIT "-nostdlib -static -no-pie")

# CMake は最初にコンパイラの動作確認として小さなプログラムを作るが、
# OS のない環境向けの実行ファイルは普通の方法ではリンクできないので、
# 確認はライブラリ（リンクしない）として行わせる。
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
