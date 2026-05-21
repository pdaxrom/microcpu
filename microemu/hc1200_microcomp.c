#include "hc1200_microcomp.h"

#include <inttypes.h>
#include <string.h>

#define TIMER_STOPPED 0x10000u
#define TIMER_MASK 0x1ffffu

#define UART_BASE 0xffe0u
#define GPIO_BASE 0xffe8u
#define TIMER_BASE 0xfff0u
#define MMAP_BASE 0xfff8u

#define SPI_PIN_MOSI 0x01u
#define SPI_PIN_MISO 0x02u
#define SPI_PIN_SCK 0x04u
#define SPI_PIN_CS 0x08u

#define FRAM_CMD_WREN 0x06u
#define FRAM_CMD_WRDI 0x04u
#define FRAM_CMD_RDSR 0x05u
#define FRAM_CMD_WRSR 0x01u
#define FRAM_CMD_READ 0x03u
#define FRAM_CMD_WRITE 0x02u
#define FRAM_CMD_FSTRD 0x0bu
#define FRAM_CMD_RDID 0x9fu
#define FRAM_CMD_SLEEP 0xb9u

static uint32_t fram_addr(uint32_t addr)
{
    return addr & (HC1200_MICROCOMP_FRAM_SIZE - 1u);
}

static uint8_t fram_status(const hc1200_microcomp_fram_spi_t *spi)
{
    return (uint8_t)((spi->status_reg & (uint8_t)~0x02u) |
        (spi->write_enable ? 0x02u : 0x00u));
}

static void fram_set_output_byte(hc1200_microcomp_fram_spi_t *spi, uint8_t value)
{
    spi->output_byte = value;
    spi->output_bits = 8;
    spi->miso = (value & 0x80u) != 0;
}

static uint8_t fram_read_data_byte(hc1200_microcomp_t *board)
{
    uint8_t value = board->fram[fram_addr(board->fram_spi.address)];

    board->fram_spi.address = fram_addr(board->fram_spi.address + 1u);
    return value;
}

static uint8_t fram_read_id_byte(hc1200_microcomp_fram_spi_t *spi)
{
    static const uint8_t id[] = { 0x04u, 0x7fu, 0x03u };
    uint8_t value = spi->id_pos < sizeof(id) ? id[spi->id_pos] : 0;

    if (spi->id_pos < 0xffu) {
        spi->id_pos++;
    }
    return value;
}

static void fram_prepare_next_output(hc1200_microcomp_t *board)
{
    hc1200_microcomp_fram_spi_t *spi = &board->fram_spi;

    switch (spi->phase) {
    case HC1200_FRAM_PHASE_READ_DATA:
        fram_set_output_byte(spi, fram_read_data_byte(board));
        break;
    case HC1200_FRAM_PHASE_STATUS_READ:
        fram_set_output_byte(spi, fram_status(spi));
        break;
    case HC1200_FRAM_PHASE_ID_READ:
        fram_set_output_byte(spi, fram_read_id_byte(spi));
        break;
    default:
        fram_set_output_byte(spi, 0);
        break;
    }
}

static void fram_advance_output(hc1200_microcomp_t *board)
{
    hc1200_microcomp_fram_spi_t *spi = &board->fram_spi;

    if (spi->output_bits > 1) {
        spi->output_byte <<= 1;
        spi->output_bits--;
        spi->miso = (spi->output_byte & 0x80u) != 0;
        return;
    }
    fram_prepare_next_output(board);
}

static void fram_process_input_byte(hc1200_microcomp_t *board, uint8_t value)
{
    hc1200_microcomp_fram_spi_t *spi = &board->fram_spi;

    switch (spi->phase) {
    case HC1200_FRAM_PHASE_COMMAND:
        spi->command = value;
        spi->address = 0;
        spi->address_bytes = 0;
        switch (value) {
        case FRAM_CMD_WREN:
            spi->write_enable = true;
            spi->phase = HC1200_FRAM_PHASE_IGNORE;
            break;
        case FRAM_CMD_WRDI:
            spi->write_enable = false;
            spi->phase = HC1200_FRAM_PHASE_IGNORE;
            break;
        case FRAM_CMD_RDSR:
            spi->phase = HC1200_FRAM_PHASE_STATUS_READ;
            fram_set_output_byte(spi, fram_status(spi));
            break;
        case FRAM_CMD_WRSR:
            spi->phase = HC1200_FRAM_PHASE_STATUS_WRITE;
            break;
        case FRAM_CMD_READ:
        case FRAM_CMD_WRITE:
        case FRAM_CMD_FSTRD:
            spi->phase = HC1200_FRAM_PHASE_ADDRESS;
            break;
        case FRAM_CMD_RDID:
            spi->phase = HC1200_FRAM_PHASE_ID_READ;
            spi->id_pos = 0;
            fram_set_output_byte(spi, fram_read_id_byte(spi));
            break;
        case FRAM_CMD_SLEEP:
        default:
            spi->phase = HC1200_FRAM_PHASE_IGNORE;
            break;
        }
        break;
    case HC1200_FRAM_PHASE_ADDRESS:
        spi->address = ((spi->address << 8) | value) & 0xffffffu;
        spi->address_bytes++;
        if (spi->address_bytes == 3) {
            spi->address = fram_addr(spi->address);
            if (spi->command == FRAM_CMD_READ) {
                spi->phase = HC1200_FRAM_PHASE_READ_DATA;
                fram_set_output_byte(spi, fram_read_data_byte(board));
            } else if (spi->command == FRAM_CMD_FSTRD) {
                spi->phase = HC1200_FRAM_PHASE_FAST_DUMMY;
            } else {
                spi->phase = HC1200_FRAM_PHASE_WRITE_DATA;
            }
        }
        break;
    case HC1200_FRAM_PHASE_FAST_DUMMY:
        spi->phase = HC1200_FRAM_PHASE_READ_DATA;
        fram_set_output_byte(spi, fram_read_data_byte(board));
        break;
    case HC1200_FRAM_PHASE_WRITE_DATA:
        if (spi->write_enable) {
            board->fram[fram_addr(spi->address)] = value;
            spi->address = fram_addr(spi->address + 1u);
            spi->write_started = true;
        }
        break;
    case HC1200_FRAM_PHASE_STATUS_WRITE:
        if (spi->write_enable) {
            spi->status_reg = (uint8_t)(value & (uint8_t)~0x02u);
            spi->write_started = true;
        }
        spi->phase = HC1200_FRAM_PHASE_IGNORE;
        break;
    default:
        break;
    }
}

static void fram_start_transaction(hc1200_microcomp_t *board)
{
    hc1200_microcomp_fram_spi_t *spi = &board->fram_spi;

    spi->active = true;
    spi->phase = HC1200_FRAM_PHASE_COMMAND;
    spi->command = 0;
    spi->input_byte = 0;
    spi->input_bits = 0;
    spi->output_byte = 0;
    spi->output_bits = 0;
    spi->address = 0;
    spi->address_bytes = 0;
    spi->id_pos = 0;
    spi->write_started = false;
    spi->miso = false;
}

static void fram_end_transaction(hc1200_microcomp_t *board)
{
    hc1200_microcomp_fram_spi_t *spi = &board->fram_spi;

    if (spi->write_started) {
        spi->write_enable = false;
    }
    spi->active = false;
    spi->phase = HC1200_FRAM_PHASE_IDLE;
    spi->input_bits = 0;
    spi->output_bits = 0;
    spi->miso = false;
}

static void fram_gpio_update(hc1200_microcomp_t *board, uint8_t pins)
{
    hc1200_microcomp_fram_spi_t *spi = &board->fram_spi;
    bool new_cs = (pins & SPI_PIN_CS) != 0;
    bool new_sck = (pins & SPI_PIN_SCK) != 0;
    bool new_mosi = (pins & SPI_PIN_MOSI) != 0;

    if (spi->cs && !new_cs) {
        fram_start_transaction(board);
    } else if (!spi->cs && new_cs) {
        fram_end_transaction(board);
    }

    if (spi->active && !spi->cs && !spi->sck && new_sck) {
        if (spi->phase == HC1200_FRAM_PHASE_READ_DATA ||
            spi->phase == HC1200_FRAM_PHASE_STATUS_READ ||
            spi->phase == HC1200_FRAM_PHASE_ID_READ) {
            fram_advance_output(board);
        } else {
            spi->input_byte = (uint8_t)((spi->input_byte << 1) |
                (new_mosi ? 1u : 0u));
            spi->input_bits++;
            if (spi->input_bits == 8) {
                fram_process_input_byte(board, spi->input_byte);
                spi->input_byte = 0;
                spi->input_bits = 0;
            }
        }
    }

    spi->cs = new_cs;
    spi->sck = new_sck;
    spi->mosi = new_mosi;
}

void hc1200_microcomp_init(hc1200_microcomp_t *board)
{
    memset(board, 0, sizeof(*board));
    hc1200_mcu_init(&board->uart);
    board->page[0] = 1;
    board->page[1] = 2;
    board->timer_counter = TIMER_STOPPED;
    board->spi_gpio_out = SPI_PIN_CS;
    board->fram_spi.cs = true;
}

void hc1200_microcomp_destroy(hc1200_microcomp_t *board)
{
    hc1200_mcu_destroy(&board->uart);
}

microcpu_bus_t hc1200_microcomp_bus(hc1200_microcomp_t *board)
{
    microcpu_bus_t bus;

    bus.ctx = board;
    bus.read = hc1200_microcomp_read;
    bus.write = hc1200_microcomp_write;
    bus.intr = hc1200_microcomp_intr;
    return bus;
}

void hc1200_microcomp_set_quiet_uart(hc1200_microcomp_t *board, bool quiet)
{
    hc1200_mcu_set_quiet_uart(&board->uart, quiet);
}

int hc1200_microcomp_set_interactive_uart(hc1200_microcomp_t *board,
    bool interactive)
{
    return hc1200_mcu_set_interactive_uart(&board->uart, interactive);
}

int hc1200_microcomp_uart_rx_append(hc1200_microcomp_t *board,
    const uint8_t *data, size_t len)
{
    return hc1200_mcu_uart_rx_append(&board->uart, data, len);
}

static bool ram_ptr(hc1200_microcomp_t *board, uint16_t addr, uint8_t **ptr,
    unsigned *mapped_page)
{
    uint8_t page = (uint8_t)(addr >> 11);

    if (addr < HC1200_MICROCOMP_SRAM0_SIZE) {
        *ptr = &board->sram0[addr];
        if (mapped_page != NULL) {
            *mapped_page = 0;
        }
        return true;
    }
    if (page == board->page[0]) {
        *ptr = &board->srampages[addr & 0x07ffu];
        if (mapped_page != NULL) {
            *mapped_page = 1;
        }
        return true;
    }
    if (page == board->page[1]) {
        *ptr = &board->srampages[0x0800u | (addr & 0x07ffu)];
        if (mapped_page != NULL) {
            *mapped_page = 2;
        }
        return true;
    }
    return false;
}

void hc1200_microcomp_load_byte(hc1200_microcomp_t *board, uint16_t addr,
    uint8_t value)
{
    uint8_t *ptr;

    if (ram_ptr(board, addr, &ptr, NULL)) {
        *ptr = value;
    }
}

static void memmap_violation(hc1200_microcomp_t *board, uint16_t addr)
{
    board->violation_page = (uint8_t)(addr >> 11);
    board->memmap_intr = true;
}

static uint8_t read_gpio(hc1200_microcomp_t *board, uint16_t addr)
{
    uint8_t ad = (uint8_t)(addr & 7u);

    switch (ad) {
    case 0:
        return (uint8_t)(((board->key_row & 0x0fu) << 4) |
            (board->spi_gpio_out & (SPI_PIN_CS | SPI_PIN_SCK | SPI_PIN_MOSI)) |
            (board->fram_spi.miso ? SPI_PIN_MISO : 0));
    case 1:
        return (uint8_t)(board->display_out & 0x3fu);
    case 4:
        return (uint8_t)(0xf0u |
            (((board->gpio_out & board->gpio_dir) |
              (board->gpio_in & (uint8_t)~board->gpio_dir)) & 0x0fu));
    case 5:
    case 6:
        return (uint8_t)(0xf0u | (board->gpio_dir & 0x0fu));
    default:
        return 0xffu;
    }
}

static void write_gpio(hc1200_microcomp_t *board, uint16_t addr, uint8_t value)
{
    uint8_t ad = (uint8_t)(addr & 7u);

    switch (ad) {
    case 0:
        board->spi_gpio_out = (uint8_t)(value &
            (SPI_PIN_CS | SPI_PIN_SCK | SPI_PIN_MOSI));
        fram_gpio_update(board, board->spi_gpio_out);
        break;
    case 1:
        board->display_out = (uint8_t)(value & 0x3fu);
        break;
    case 4:
        board->gpio_out = (uint8_t)(value & 0x0fu);
        break;
    case 5:
    case 6:
        board->gpio_dir = (uint8_t)(value & 0x0fu);
        break;
    default:
        break;
    }
}

static uint8_t read_timer(hc1200_microcomp_t *board, uint16_t addr)
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
        value = (uint8_t)(((board->timer_counter & TIMER_STOPPED) ? 0x02u : 0) |
            (board->timer_intr ? 0x01u : 0));
        board->timer_intr = false;
        break;
    }
    return value;
}

static void write_timer(hc1200_microcomp_t *board, uint16_t addr, uint8_t value)
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

static uint8_t read_memmap(const hc1200_microcomp_t *board, uint16_t addr)
{
    if (addr & 2u) {
        return (uint8_t)((board->violation_page & 0x1fu) << 3);
    }
    if (addr & 1u) {
        return (uint8_t)(((board->page[1] & 0x1fu) << 3) |
            (board->page_dirty[1] ? 1u : 0));
    }
    return (uint8_t)(((board->page[0] & 0x1fu) << 3) |
        (board->page_dirty[0] ? 1u : 0));
}

static void write_memmap(hc1200_microcomp_t *board, uint16_t addr, uint8_t value)
{
    unsigned index = (addr & 1u) ? 1u : 0u;

    board->page[index] = (uint8_t)((value >> 3) & 0x1fu);
    board->page_dirty[index] = false;
    board->memmap_intr = false;
}

uint8_t hc1200_microcomp_read(void *ctx, uint16_t addr)
{
    hc1200_microcomp_t *board = ctx;
    uint8_t *ptr;

    if ((addr & 0xffe0u) == 0xffe0u) {
        switch ((addr >> 3) & 3u) {
        case 0:
            return hc1200_mcu_read(&board->uart, addr);
        case 1:
            return read_gpio(board, addr);
        case 2:
            return read_timer(board, addr);
        default:
            return read_memmap(board, addr);
        }
    }
    if (ram_ptr(board, addr, &ptr, NULL)) {
        return *ptr;
    }
    memmap_violation(board, addr);
    return 0;
}

void hc1200_microcomp_write(void *ctx, uint16_t addr, uint8_t value)
{
    hc1200_microcomp_t *board = ctx;
    uint8_t *ptr;
    unsigned mapped_page = 0;

    if ((addr & 0xffe0u) == 0xffe0u) {
        switch ((addr >> 3) & 3u) {
        case 0:
            hc1200_mcu_write(&board->uart, addr, value);
            return;
        case 1:
            write_gpio(board, addr, value);
            return;
        case 2:
            write_timer(board, addr, value);
            return;
        default:
            write_memmap(board, addr, value);
            return;
        }
    }
    if (ram_ptr(board, addr, &ptr, &mapped_page)) {
        *ptr = value;
        if (mapped_page == 1 || mapped_page == 2) {
            board->page_dirty[mapped_page - 1u] = true;
        }
        return;
    }
    memmap_violation(board, addr);
}

bool hc1200_microcomp_intr(void *ctx)
{
    const hc1200_microcomp_t *board = ctx;

    return board->timer_intr || board->memmap_intr;
}

void hc1200_microcomp_tick(hc1200_microcomp_t *board, unsigned cycles)
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

void hc1200_microcomp_dump(const hc1200_microcomp_t *board, FILE *out)
{
    if (out == NULL) {
        out = stderr;
    }
    fprintf(out,
        "page1=%02x dirty=%u page2=%02x dirty=%u violation=%02x "
        "mem_intr=%u timer=%05x timer_intr=%u ticks=%" PRIu64 "\n",
        (unsigned)(board->page[0] << 3),
        board->page_dirty[0] ? 1u : 0u,
        (unsigned)(board->page[1] << 3),
        board->page_dirty[1] ? 1u : 0u,
        (unsigned)(board->violation_page << 3),
        board->memmap_intr ? 1u : 0u,
        (unsigned)(board->timer_counter & TIMER_MASK),
        board->timer_intr ? 1u : 0u,
        board->ticks);
}
