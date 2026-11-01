#ifndef KERNEL_H
#define KERNEL_H

#include <stddef.h>
#include <stdint.h>

/* シリアルポート（COM1）への出力。kernel/serial.c */
void serial_init(void);
void serial_putc(char c);
void serial_puts(const char *s);
void serial_write(const char *buf, size_t len);

/* entry64.S から呼ばれる、C で書いたカーネルの入り口。kernel/kernel.c */
void kernel_main(void);

/* I/O ポートへの書き込みと読み込み。x86 の out 命令・in 命令そのもの。 */
static inline void outb(uint16_t port, uint8_t value)
{
    __asm__ volatile ("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline uint8_t inb(uint16_t port)
{
    uint8_t value;
    __asm__ volatile ("inb %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}

#endif
