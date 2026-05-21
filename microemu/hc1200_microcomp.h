#ifndef HC1200_MICROCOMP_H
#define HC1200_MICROCOMP_H

#include "hc1200_mcu.h"
#include "microcpu_core.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define HC1200_MICROCOMP_SRAM0_SIZE 2048u
#define HC1200_MICROCOMP_SRAMPAGES_SIZE 4096u
#define HC1200_MICROCOMP_FRAM_SIZE 131072u

typedef struct {
    uint8_t command;
    uint8_t input_byte;
    uint8_t input_bits;
    uint8_t output_byte;
    uint8_t output_bits;
    uint8_t address_bytes;
    uint8_t id_pos;
    uint8_t status_reg;
    uint32_t address;
    bool active;
    bool cs;
    bool sck;
    bool mosi;
    bool miso;
    bool write_enable;
    bool write_started;
    enum {
        HC1200_FRAM_PHASE_IDLE,
        HC1200_FRAM_PHASE_COMMAND,
        HC1200_FRAM_PHASE_ADDRESS,
        HC1200_FRAM_PHASE_WRITE_DATA,
        HC1200_FRAM_PHASE_READ_DATA,
        HC1200_FRAM_PHASE_FAST_DUMMY,
        HC1200_FRAM_PHASE_STATUS_READ,
        HC1200_FRAM_PHASE_STATUS_WRITE,
        HC1200_FRAM_PHASE_ID_READ,
        HC1200_FRAM_PHASE_IGNORE
    } phase;
} hc1200_microcomp_fram_spi_t;

typedef struct {
    uint8_t sram0[HC1200_MICROCOMP_SRAM0_SIZE];
    uint8_t srampages[HC1200_MICROCOMP_SRAMPAGES_SIZE];
    uint8_t fram[HC1200_MICROCOMP_FRAM_SIZE];

    hc1200_mcu_t uart;
    hc1200_microcomp_fram_spi_t fram_spi;

    uint8_t page[2];
    bool page_dirty[2];
    uint8_t violation_page;
    bool memmap_intr;

    uint8_t spi_gpio_out;
    uint8_t display_out;
    uint8_t gpio_out;
    uint8_t gpio_dir;
    uint8_t gpio_in;
    uint8_t key_row;

    uint32_t timer_counter;
    bool timer_intr;
    uint64_t ticks;
} hc1200_microcomp_t;

void hc1200_microcomp_init(hc1200_microcomp_t *board);
void hc1200_microcomp_destroy(hc1200_microcomp_t *board);
microcpu_bus_t hc1200_microcomp_bus(hc1200_microcomp_t *board);

void hc1200_microcomp_set_quiet_uart(hc1200_microcomp_t *board, bool quiet);
int hc1200_microcomp_set_interactive_uart(hc1200_microcomp_t *board,
    bool interactive);
int hc1200_microcomp_uart_rx_append(hc1200_microcomp_t *board,
    const uint8_t *data, size_t len);

void hc1200_microcomp_load_byte(hc1200_microcomp_t *board, uint16_t addr,
    uint8_t value);
uint8_t hc1200_microcomp_read(void *ctx, uint16_t addr);
void hc1200_microcomp_write(void *ctx, uint16_t addr, uint8_t value);
bool hc1200_microcomp_intr(void *ctx);
void hc1200_microcomp_tick(hc1200_microcomp_t *board, unsigned cycles);
void hc1200_microcomp_dump(const hc1200_microcomp_t *board, FILE *out);

#endif
