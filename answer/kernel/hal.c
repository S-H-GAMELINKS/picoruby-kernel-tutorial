/* libmruby.a がカーネルに用意してほしい関数。
 *
 * どれも中身はほぼ空だが、定義がないとリンクできない。
 * Hello World ではここに書いた機能は使わない。 */

#include <mruby.h>

/* ---------------------------------------------------------------- タスク
 *
 * PicoRuby の VM には、複数の Ruby のコードを切り替えながら動かす仕組み
 * （mruby-task）が入っている。その仕組みはタイマーや割り込みの操作を
 * 次の関数でカーネルに頼むが、このカーネルにはタイマーも割り込みもないので、
 * 何もしない関数を置いておく。 */

void mrb_hal_task_init(mrb_state *mrb) { (void)mrb; }
void mrb_hal_task_final(mrb_state *mrb) { (void)mrb; }
void mrb_hal_task_idle_cpu(mrb_state *mrb) { (void)mrb; }
void mrb_hal_task_sleep_us(mrb_state *mrb, mrb_int usec) { (void)mrb; (void)usec; }
void mrb_task_enable_irq(void) {}
void mrb_task_disable_irq(void) {}

/* ---------------------------------------------------------------- その他
 *
 * 次の 2 つは libmruby.a の中から参照されているが、Hello World では呼ばれない。 */

/* IO オブジェクトのファイル番号を返す。このカーネルにはファイルがない。 */
int
mrb_io_fileno(mrb_state *mrb, mrb_value io)
{
    (void)mrb;
    (void)io;
    return -1;
}

/* Ruby のパーサ（Prism）の関数。カーネルにはパーサを入れていない。 */
void *
pm_constant_pool_id_to_constant(const void *pool, unsigned int id)
{
    (void)pool;
    (void)id;
    return NULL;
}
