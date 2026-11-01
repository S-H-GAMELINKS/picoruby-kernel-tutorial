/* ANCHOR: all */
#include <string.h>

#include <mruby.h>
#include <mruby/irep.h>
#include <mruby/string.h>

#include "kernel.h"

/* ANCHOR: check */
/* カーネルと libmruby.a で mruby の設定が食い違っていないかを、コンパイル時に確かめる。
 * 食い違っていても、コンパイルもリンクも通ってしまうため。 */
_Static_assert(sizeof(mrb_int) == 8, "MRB_INT64 must match libmruby.a");
_Static_assert(sizeof(mrb_value) == 16, "MRB_NO_BOXING must match libmruby.a");
/* ANCHOR_END: check */

/* ANCHOR: bytecode */
/* ruby/hello.rb をビルド時にバイトコードに変換したもの（build/hello_bytecode.c）。 */
extern const uint8_t hello_bytecode[];
/* ANCHOR_END: bytecode */

/* ANCHOR: alloc */
/* ---------------------------------------------------------------- メモリの確保
 *
 * PicoRuby の VM は、メモリが必要になると mrb_basic_alloc_func を呼ぶ。
 *
 *   mrb_basic_alloc_func(NULL, size)  新しく size バイト確保する
 *   mrb_basic_alloc_func(ptr,  size)  ptr の大きさを size バイトに変える
 *   mrb_basic_alloc_func(ptr,  0)     ptr を解放する
 *
 * ここでは大きな配列 heap の先頭から順に切り出すだけにする。解放されても
 * 再利用はしない。Hello World を表示して終わるだけなら、これで足りる
 * （実際に使うのは 60KB ほど）。 */

#define HEAP_SIZE (256 * 1024)
static uint8_t heap[HEAP_SIZE];
static size_t heap_used;

/* 確保した領域の直前に、その大きさを記録しておく（大きさを変えるときに使う）。 */
struct header {
    size_t size;
    size_t padding;  /* 返すアドレスを 16 バイト境界にそろえるため */
};

void *
mrb_basic_alloc_func(void *ptr, size_t size)
{
    if (size == 0) return NULL;  /* 解放：何もしない */

    size_t total = sizeof(struct header) + ((size + 15) & ~(size_t)15);
    if (heap_used + total > HEAP_SIZE) return NULL;  /* もう空きがない */

    struct header *h = (struct header *)&heap[heap_used];
    heap_used += total;
    h->size = size;
    void *new_ptr = h + 1;

    /* 大きさを変える場合は、元の中身を新しい場所に写す。 */
    if (ptr) {
        struct header *old = (struct header *)ptr - 1;
        memcpy(new_ptr, ptr, old->size < size ? old->size : size);
    }
    return new_ptr;
}
/* ANCHOR_END: alloc */

/* ANCHOR: puts */
/* ---------------------------------------------------------------- puts
 *
 * Ruby の puts を C で定義する。引数を文字列にして、シリアルポートに書く。 */
static mrb_value
kernel_puts(mrb_state *mrb, mrb_value self)
{
    mrb_value *argv;
    mrb_int argc;
    mrb_get_args(mrb, "*", &argv, &argc);

    for (mrb_int i = 0; i < argc; i++) {
        mrb_value s = mrb_obj_as_string(mrb, argv[i]);
        serial_write(RSTRING_PTR(s), RSTRING_LEN(s));
        serial_putc('\n');
    }
    return mrb_nil_value();
}
/* ANCHOR_END: puts */

/* ANCHOR: main */
void
kernel_main(void)
{
    serial_init();
    serial_puts("boot ok\n");

    /* PicoRuby の VM を作る。 */
    mrb_state *mrb = mrb_open();
    if (!mrb) {
        serial_puts("mrb_open failed\n");
        return;
    }

    /* Kernel モジュールに puts を定義する。これで Ruby のどこからでも puts が呼べる。 */
    mrb_define_method(mrb, mrb->kernel_module, "puts", kernel_puts, MRB_ARGS_ANY());

    /* 埋め込んだバイトコードを実行する。 */
    mrb_load_irep(mrb, hello_bytecode);

    /* Ruby のコードで例外が起きたら、その内容を表示する。 */
    if (mrb->exc) {
        mrb_value s = mrb_inspect(mrb, mrb_obj_value(mrb->exc));
        serial_write(RSTRING_PTR(s), RSTRING_LEN(s));
        serial_putc('\n');
    }

    mrb_close(mrb);
}
/* ANCHOR_END: main */
/* ANCHOR_END: all */
