# 依存ライブラリのバージョン。
#
# どれもタグ名ではなくコミットの SHA で固定する。タグは後から付け替えられる
# ことがあるが、SHA は変わらないので、誰がいつビルドしても同じソースになる。

# musl libc v1.2.5
# 本家は https://git.musl-libc.org/git/musl 。GitHub のミラーの方が速く取得できる。
set(MUSL_URL     https://github.com/kraj/musl.git)
set(MUSL_REF     0784374d561435f7c787a555aeab8ede699ed298)  # v1.2.5

# PicoRuby 4.0.5
set(PICORUBY_URL https://github.com/picoruby/picoruby.git)
set(PICORUBY_REF 604666ec366bd9c597756e3d671bfa4c378f165d)  # 4.0.5
