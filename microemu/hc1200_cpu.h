#ifndef HC1200_CPU_H
#define HC1200_CPU_H

#include "hc1200_mcu.h"
#include "microcpu_core.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define HC1200_CPU_RAM_SIZE 65536u

typedef struct {
    uint8_t ram[HC1200_CPU_RAM_SIZE];
    hc1200_mcu_t periph;
} hc1200_cpu_t;

void hc1200_cpu_init(hc1200_cpu_t *board);
void hc1200_cpu_destroy(hc1200_cpu_t *board);
microcpu_bus_t hc1200_cpu_bus(hc1200_cpu_t *board);

void hc1200_cpu_set_quiet_uart(hc1200_cpu_t *board, bool quiet);
int hc1200_cpu_set_interactive_uart(hc1200_cpu_t *board, bool interactive);
int hc1200_cpu_uart_rx_append(hc1200_cpu_t *board, const uint8_t *data, size_t len);
int hc1200_cpu_uart_rx_read_stdin(hc1200_cpu_t *board);

void hc1200_cpu_load_byte(hc1200_cpu_t *board, uint16_t addr, uint8_t value);
uint8_t hc1200_cpu_read(void *ctx, uint16_t addr);
void hc1200_cpu_write(void *ctx, uint16_t addr, uint8_t value);
bool hc1200_cpu_intr(void *ctx);
void hc1200_cpu_tick(hc1200_cpu_t *board, unsigned cycles);
void hc1200_cpu_dump(const hc1200_cpu_t *board, FILE *out);

#endif
