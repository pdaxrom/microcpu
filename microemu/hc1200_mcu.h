#ifndef HC1200_MCU_H
#define HC1200_MCU_H

#include "microcpu_core.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <termios.h>

#define HC1200_MCU_SRAM0_SIZE 2048u
#define HC1200_MCU_SRAMPAGES_SIZE 4096u
#define HC1200_MCU_UART_BASE 0xffe0u
#define HC1200_MCU_GPIO_BASE 0xffe8u
#define HC1200_MCU_TIMER_BASE 0xfff0u

typedef struct {
    uint8_t *data;
    size_t len;
    size_t pos;
    size_t cap;
} hc1200_byte_queue_t;

typedef struct {
    uint8_t sram0[HC1200_MCU_SRAM0_SIZE];
    uint8_t srampages[HC1200_MCU_SRAMPAGES_SIZE];

    uint16_t gpio_dir;
    uint16_t gpio_out;
    uint16_t gpio_in;

    uint32_t timer_counter;
    bool timer_intr;

    hc1200_byte_queue_t uart_rx;
    bool quiet_uart;
    bool interactive_uart;
    bool interactive_uart_stdio;
    bool uart_stdin_eof;
    int uart_stdin_fd;
    int uart_stdin_flags;
    bool uart_stdin_flags_saved;
    struct termios uart_stdin_termios;
    bool uart_stdin_termios_saved;
    uint64_t ticks;
} hc1200_mcu_t;

void hc1200_mcu_init(hc1200_mcu_t *board);
void hc1200_mcu_destroy(hc1200_mcu_t *board);
microcpu_bus_t hc1200_mcu_bus(hc1200_mcu_t *board);

void hc1200_mcu_set_quiet_uart(hc1200_mcu_t *board, bool quiet);
int hc1200_mcu_set_interactive_uart(hc1200_mcu_t *board, bool interactive);
int hc1200_mcu_uart_rx_push(hc1200_mcu_t *board, uint8_t value);
int hc1200_mcu_uart_rx_append(hc1200_mcu_t *board, const uint8_t *data, size_t len);
int hc1200_mcu_uart_rx_read_stdin(hc1200_mcu_t *board);

void hc1200_mcu_load_byte(hc1200_mcu_t *board, uint16_t addr, uint8_t value);
uint8_t hc1200_mcu_read(void *ctx, uint16_t addr);
void hc1200_mcu_write(void *ctx, uint16_t addr, uint8_t value);
bool hc1200_mcu_intr(void *ctx);
void hc1200_mcu_tick(hc1200_mcu_t *board, unsigned cycles);
void hc1200_mcu_dump(const hc1200_mcu_t *board, FILE *out);

#endif
