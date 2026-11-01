/* シリアルポート（COM1）への出力。
 *
 * QEMU を -serial mon:stdio で起動すると、COM1 に書いた文字がそのまま
 * ターミナルに表示される。画面を描くよりずっと簡単なので、
 * このカーネルの出力先はシリアルポートだけにする。 */

#include "kernel.h"

/* COM1 の I/O ポート番号。ここから 8 個のポートがシリアルの各レジスタになる。 */
#define COM1 0x3F8

#define COM_DATA         0   /* 送受信データ */
#define COM_INT_ENABLE   1   /* 割り込みの有効化 */
#define COM_FIFO_CTRL    2   /* FIFO の制御 */
#define COM_LINE_CTRL    3   /* 通信形式（データ長など） */
#define COM_MODEM_CTRL   4   /* モデム制御 */
#define COM_LINE_STATUS  5   /* 状態 */

#define LINE_CTRL_DLAB        0x80  /* 1 にすると、DATA と INT_ENABLE で速度を設定できる */
#define LINE_CTRL_8N1         0x03  /* 8 ビット、パリティなし、ストップビット 1 */
#define LINE_STATUS_TX_EMPTY  0x20  /* 送信バッファが空いている */

void
serial_init(void)
{
    outb(COM1 + COM_INT_ENABLE, 0x00);            /* 割り込みは使わない */
    outb(COM1 + COM_LINE_CTRL,  LINE_CTRL_DLAB);  /* 速度の設定を始める */
    outb(COM1 + COM_DATA,       0x03);            /* 115200 / 3 = 38400 bps（下位バイト） */
    outb(COM1 + COM_INT_ENABLE, 0x00);            /*                       （上位バイト） */
    outb(COM1 + COM_LINE_CTRL,  LINE_CTRL_8N1);   /* 速度の設定を終え、通信形式を決める */
    outb(COM1 + COM_FIFO_CTRL,  0xC7);            /* FIFO を有効にして中身を消す */
    outb(COM1 + COM_MODEM_CTRL, 0x03);            /* DTR と RTS を立てる */
}

static void
write_byte(uint8_t byte)
{
    /* 前の文字を送り終えるまで待ってから書く。 */
    while ((inb(COM1 + COM_LINE_STATUS) & LINE_STATUS_TX_EMPTY) == 0)
        ;
    outb(COM1 + COM_DATA, byte);
}

void
serial_putc(char c)
{
    /* ターミナルは改行に CR LF を期待するので、\n の前に \r を送る。 */
    if (c == '\n') write_byte('\r');
    write_byte((uint8_t)c);
}

void
serial_puts(const char *s)
{
    while (*s) serial_putc(*s++);
}

void
serial_write(const char *buf, size_t len)
{
    for (size_t i = 0; i < len; i++) serial_putc(buf[i]);
}
