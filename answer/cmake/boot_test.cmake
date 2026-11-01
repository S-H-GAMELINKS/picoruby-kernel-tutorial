# ctest から呼ばれる起動テスト。
#
# QEMU でカーネルを起動し、シリアルポートの出力に "boot ok" と "Hello World" が
# 含まれていれば成功とする。カーネルは Hello World のあと止まったままになるので、
# 数秒で QEMU を打ち切ってから出力を調べる。

execute_process(
  COMMAND ${QEMU} -kernel ${KERNEL} -display none -serial stdio -no-reboot
  TIMEOUT 5
  OUTPUT_VARIABLE output
  ERROR_VARIABLE  errors
)

message("${output}")

foreach(expected "boot ok" "Hello World")
  string(FIND "${output}" "${expected}" found)
  if(found EQUAL -1)
    message(FATAL_ERROR "\"${expected}\" が出力されませんでした\n${errors}")
  endif()
endforeach()
