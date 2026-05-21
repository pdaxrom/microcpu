#include "hc1200_mcu.h"

#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

#define TIMER_STOPPED 0x10000u
#define TIMER_MASK 0x1ffffu

void hc1200_mcu_init(hc1200_mcu_t *board)
{
    memset(board, 0, sizeof(*board));
    board->timer_counter = TIMER_STOPPED;
}

void hc1200_mcu_destroy(hc1200_mcu_t *board)
{
    free(board->uart_rx.data);
    board->uart_rx.data = NULL;
    board->uart_rx.len = 0;
    board->uart_rx.pos = 0;
    board->uart_rx.cap = 0;
}

microcpu_bus_t hc1200_mcu_bus(hc1200_mcu_t *board)
{
    microcpu_bus_t bus;

    bus.ctx = board;
    bus.read = hc1200_mcu_read;
    bus.write = hc1200_mcu_write;
    bus.intr = hc1200_mcu_intr;
    return bus;
}

void hc1200_mcu_set_quiet_uart(hc1200_mcu_t *board, bool quiet)
{
    board->quiet_uart = quiet;
}

static int queue_reserve(hc1200_byte_queue_t *queue, size_t len)
{
    if (queue->len + len > queue->cap) {
        size_t new_cap = queue->cap ? queue->cap : 256;
        uint8_t *new_data;

        while (new_cap < queue->len + len) {
            new_cap *= 2;
        }
        new_data = realloc(queue->data, new_cap);
        if (new_data == NULL) {
            perror("realloc");
            return -1;
        }
        queue->data = new_data;
        queue->cap = new_cap;
    }
    return 0;
}

int hc1200_mcu_uart_rx_push(hc1200_mcu_t *board, uint8_t value)
{
    if (queue_reserve(&board->uart_rx, 1) < 0) {
        return -1;
    }
    board->uart_rx.data[board->uart_rx.len++] = value;
    return 0;
}

int hc1200_mcu_uart_rx_append(hc1200_mcu_t *board, const uint8_t *data, size_t len)
{
    if (len == 0) {
        return 0;
    }
    if (queue_reserve(&board->uart_rx, len) < 0) {
        return -1;
    }
    memcpy(board->uart_rx.data + board->uart_rx.len, data, len);
    board->uart_rx.len += len;
    return 0;
}

int hc1200_mcu_uart_rx_read_stdin(hc1200_mcu_t *board)
{
    int ch;

    while ((ch = getchar()) != EOF) {
        if (hc1200_mcu_uart_rx_push(board, (uint8_t)ch) < 0) {
            return -1;
        }
    }
    return 0;
}

static bool ram_ptr(hc1200_mcu_t *board, uint16_t addr, uint8_t **ptr)
{
    if (addr < HC1200_MCU_SRAM0_SIZE) {
        *ptr = &board->sram0[addr];
        return true;
    }
    if (addr >= 0x0800u && addr < 0x1800u) {
        *ptr = &board->srampages[addr - 0x0800u];
        return true;
    }
    return false;
}

void hc1200_mcu_load_byte(hc1200_mcu_t *board, uint16_t addr, uint8_t value)
{
    uint8_t *ptr;

    if (ram_ptr(board, addr, &ptr)) {
        *ptr = value;
    }
}

static uint16_t gpio_effective(const hc1200_mcu_t *board)
{
    return (uint16_t)((board->gpio_out & board->gpio_dir) |
        (board->gpio_in & ~board->gpio_dir)) & 0x7fffu;
}

static uint8_t read_uart(hc1200_mcu_t *board, uint16_t addr)
{
    bool a0 = (addr & 1u) != 0;

    if (!a0) {
        bool rx_full = board->uart_rx.pos < board->uart_rx.len;
        return rx_full ? 0x01u : 0x00u;
    }

    if (board->uart_rx.pos < board->uart_rx.len) {
        return board->uart_rx.data[board->uart_rx.pos++];
    }
    return 0;
}

static uint8_t read_gpio(const hc1200_mcu_t *board, uint16_t addr)
{
    uint16_t gpio_in = gpio_effective(board);

    switch (addr & 3u) {
    case 0:
        return (uint8_t)(0x80u | ((gpio_in >> 8) & 0x7fu));
    case 1:
        return (uint8_t)(gpio_in & 0xffu);
    case 2:
        return (uint8_t)(0x80u | ((board->gpio_dir >> 8) & 0x7fu));
    default:
        return (uint8_t)(board->gpio_dir & 0xffu);
    }
}

static uint8_t read_timer(hc1200_mcu_t *board, uint16_t addr)
{
    uint8_t value;

    switch (addr & 3u) {
    case 0:
        value = (uint8_t)(board->timer_counter & 0xffu);
        break;
    case 1:
        value = (uint8_t)((board->timer_counter >> 8) & 0xffu);
        break;
    default:
        value = (uint8_t)(((board->timer_counter >> 14) & 0x04u) |
            (board->timer_intr ? 0x01u : 0x00u));
        break;
    }
    if (addr & 2u) {
        board->timer_intr = false;
    }
    return value;
}

uint8_t hc1200_mcu_read(void *ctx, uint16_t addr)
{
    hc1200_mcu_t *board = ctx;
    uint8_t *ptr;

    if ((addr & 0xffe0u) == 0xffe0u) {
        switch ((addr >> 3) & 3u) {
        case 0:
            return read_uart(board, addr);
        case 1:
            return read_gpio(board, addr);
        case 2:
            return read_timer(board, addr);
        default:
            return 0;
        }
    }
    if (ram_ptr(board, addr, &ptr)) {
        return *ptr;
    }
    return 0;
}

static void write_uart(hc1200_mcu_t *board, uint16_t addr, uint8_t value)
{
    bool a0 = (addr & 1u) != 0;

    if (a0 && !board->quiet_uart) {
        fputc(value, stdout);
        fflush(stdout);
    }
}

static void write_gpio(hc1200_mcu_t *board, uint16_t addr, uint8_t value)
{
    switch (addr & 3u) {
    case 0:
        board->gpio_out = (uint16_t)((board->gpio_out & 0x00ffu) |
            ((uint16_t)(value & 0x7fu) << 8));
        break;
    case 1:
        board->gpio_out = (uint16_t)((board->gpio_out & 0x7f00u) | value);
        break;
    case 2:
        board->gpio_dir = (uint16_t)((board->gpio_dir & 0x00ffu) |
            ((uint16_t)(value & 0x7fu) << 8));
        break;
    default:
        board->gpio_dir = (uint16_t)((board->gpio_dir & 0x7f00u) | value);
        break;
    }
}

static void write_timer(hc1200_mcu_t *board, uint16_t addr, uint8_t value)
{
    if ((addr & 2u) == 0) {
        if ((addr & 1u) == 0) {
            board->timer_counter = (board->timer_counter & 0x1ff00u) | value;
        } else {
            board->timer_counter = ((uint32_t)value << 8) |
                (board->timer_counter & 0xffu);
        }
    } else {
        board->timer_intr = false;
    }
}

void hc1200_mcu_write(void *ctx, uint16_t addr, uint8_t value)
{
    hc1200_mcu_t *board = ctx;
    uint8_t *ptr;

    if ((addr & 0xffe0u) == 0xffe0u) {
        switch ((addr >> 3) & 3u) {
        case 0:
            write_uart(board, addr, value);
            return;
        case 1:
            write_gpio(board, addr, value);
            return;
        case 2:
            write_timer(board, addr, value);
            return;
        default:
            return;
        }
    }
    if (ram_ptr(board, addr, &ptr)) {
        *ptr = value;
    }
}

bool hc1200_mcu_intr(void *ctx)
{
    const hc1200_mcu_t *board = ctx;

    return board->timer_intr;
}

void hc1200_mcu_tick(hc1200_mcu_t *board, unsigned cycles)
{
    unsigned i;

    for (i = 0; i < cycles; i++) {
        if ((board->timer_counter & TIMER_STOPPED) == 0) {
            if (board->timer_counter == 1u) {
                board->timer_intr = !board->timer_intr;
            }
            board->timer_counter = (board->timer_counter - 1u) & TIMER_MASK;
        }
        board->ticks++;
    }
}

void hc1200_mcu_dump(const hc1200_mcu_t *board, FILE *out)
{
    if (out == NULL) {
        out = stderr;
    }
    fprintf(out, "timer=%05x timer_intr=%u ticks=%" PRIu64 "\n",
        (unsigned)(board->timer_counter & TIMER_MASK),
        board->timer_intr ? 1u : 0u,
        board->ticks);
}
