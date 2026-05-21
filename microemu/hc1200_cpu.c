#include "hc1200_cpu.h"

#include <string.h>

#define HC1200_CPU_MMIO_BASE 0xffe0u
#define HC1200_CPU_MMIO_MASK 0xffe0u

static bool is_mmio_addr(uint16_t addr)
{
    return (addr & HC1200_CPU_MMIO_MASK) == HC1200_CPU_MMIO_BASE;
}

void hc1200_cpu_init(hc1200_cpu_t *board)
{
    memset(board, 0, sizeof(*board));
    hc1200_mcu_init(&board->periph);
}

void hc1200_cpu_destroy(hc1200_cpu_t *board)
{
    hc1200_mcu_destroy(&board->periph);
}

microcpu_bus_t hc1200_cpu_bus(hc1200_cpu_t *board)
{
    microcpu_bus_t bus;

    bus.ctx = board;
    bus.read = hc1200_cpu_read;
    bus.write = hc1200_cpu_write;
    bus.intr = hc1200_cpu_intr;
    return bus;
}

void hc1200_cpu_set_quiet_uart(hc1200_cpu_t *board, bool quiet)
{
    hc1200_mcu_set_quiet_uart(&board->periph, quiet);
}

int hc1200_cpu_set_interactive_uart(hc1200_cpu_t *board, bool interactive)
{
    return hc1200_mcu_set_interactive_uart(&board->periph, interactive);
}

int hc1200_cpu_uart_rx_append(hc1200_cpu_t *board, const uint8_t *data, size_t len)
{
    return hc1200_mcu_uart_rx_append(&board->periph, data, len);
}

int hc1200_cpu_uart_rx_read_stdin(hc1200_cpu_t *board)
{
    return hc1200_mcu_uart_rx_read_stdin(&board->periph);
}

void hc1200_cpu_load_byte(hc1200_cpu_t *board, uint16_t addr, uint8_t value)
{
    board->ram[addr] = value;
}

uint8_t hc1200_cpu_read(void *ctx, uint16_t addr)
{
    hc1200_cpu_t *board = ctx;

    if (is_mmio_addr(addr)) {
        return hc1200_mcu_read(&board->periph, addr);
    }
    return board->ram[addr];
}

void hc1200_cpu_write(void *ctx, uint16_t addr, uint8_t value)
{
    hc1200_cpu_t *board = ctx;

    if (is_mmio_addr(addr)) {
        hc1200_mcu_write(&board->periph, addr, value);
        return;
    }
    board->ram[addr] = value;
}

bool hc1200_cpu_intr(void *ctx)
{
    hc1200_cpu_t *board = ctx;

    return hc1200_mcu_intr(&board->periph);
}

void hc1200_cpu_tick(hc1200_cpu_t *board, unsigned cycles)
{
    hc1200_mcu_tick(&board->periph, cycles);
}

void hc1200_cpu_dump(const hc1200_cpu_t *board, FILE *out)
{
    if (out == NULL) {
        out = stderr;
    }
    fprintf(out, "ram=%u mmio=ffe0-ffff ", HC1200_CPU_RAM_SIZE);
    hc1200_mcu_dump(&board->periph, out);
}
