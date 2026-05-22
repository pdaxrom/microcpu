#include "hc1200_cpu.h"
#include "hc1200_microcomp.h"
#include "hc1200_mcu.h"
#include "microcpu_core.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t *data;
    size_t len;
    size_t cap;
} byte_buffer_t;

typedef struct {
    const char *board_name;
    const char *format;
    const char *program;
    uint16_t load_addr;
    uint64_t max_steps;
    bool trace;
    bool dump_regs;
    bool stats;
    bool stop_on_self_branch;
    bool max_steps_set;
    bool stdin_rx;
    bool quiet_uart;
    bool interactive_uart;
    byte_buffer_t uart_rx;
} config_t;

typedef struct {
    const char *name;
    void *ctx;
    microcpu_bus_t bus;
    void (*load_byte)(void *ctx, uint16_t addr, uint8_t value);
    void (*tick)(void *ctx, unsigned cycles);
    void (*dump)(const void *ctx, FILE *out);
    void (*set_quiet_uart)(void *ctx, bool quiet);
    int (*set_interactive_uart)(void *ctx, bool interactive);
    int (*uart_rx_append)(void *ctx, const uint8_t *data, size_t len);
} board_model_t;

static volatile sig_atomic_t stop_requested;

static void usage(FILE *out)
{
    fprintf(out,
        "usage: microemu [options] <program>\n"
        "\n"
        "Options:\n"
        "  --board hc1200-mcu|hc1200-cpu|hc1200-microcomp\n"
        "                              board model (default: hc1200-mcu)\n"
        "  --format auto|bin|hex|mem   input format (default: auto)\n"
        "  --load-addr ADDR            binary load address (default: 0)\n"
        "  --max-steps N               instruction limit, 0 means unlimited (default: 1000000)\n"
        "  --stop-on-self-branch       stop successfully on a 'b *' idle loop\n"
        "  --trace                     print executed instructions to stderr\n"
        "  --dump-regs                 print CPU registers at exit\n"
        "  --stats                     print executed instruction and cycle counts\n"
        "  --uart-rx TEXT              preload UART RX text (supports \\n, \\r, \\t, \\\\, \\xHH)\n"
        "  --uart-rx-hex HEX           preload UART RX bytes from hex bytes\n"
        "  --uart-rx-file FILE         preload UART RX bytes from a binary file\n"
        "  --stdin-rx                  read all stdin bytes into UART RX before running\n"
        "  --interactive-uart          switch UART stdin/stdout on after preloaded RX drains\n"
        "  --quiet-uart                discard UART TX instead of writing it to stdout\n"
        "  --help                      show this help\n");
}

static void handle_stop_signal(int signum)
{
    (void)signum;
    stop_requested = 1;
}

static bool parse_u64(const char *text, uint64_t *value)
{
    char *end = NULL;
    int base = 0;

    errno = 0;
    if (text[0] == '$') {
        text++;
        base = 16;
    }
    *value = strtoull(text, &end, base);
    return errno == 0 && end != text && *end == '\0';
}

static bool parse_u16(const char *text, uint16_t *value)
{
    uint64_t parsed;

    if (!parse_u64(text, &parsed) || parsed > 0xffffu) {
        return false;
    }
    *value = (uint16_t)parsed;
    return true;
}

static int require_arg(int argc, char **argv, int *index, const char *option,
    const char **value)
{
    if (*index + 1 >= argc) {
        fprintf(stderr, "microemu: %s requires an argument\n", option);
        return -1;
    }
    *index += 1;
    *value = argv[*index];
    return 0;
}

static int hex_digit(unsigned char ch)
{
    if (ch >= '0' && ch <= '9') {
        return ch - '0';
    }
    if (ch >= 'a' && ch <= 'f') {
        return ch - 'a' + 10;
    }
    if (ch >= 'A' && ch <= 'F') {
        return ch - 'A' + 10;
    }
    return -1;
}

static void byte_buffer_destroy(byte_buffer_t *buffer)
{
    free(buffer->data);
    buffer->data = NULL;
    buffer->len = 0;
    buffer->cap = 0;
}

static int byte_buffer_reserve(byte_buffer_t *buffer, size_t len)
{
    if (buffer->len + len > buffer->cap) {
        size_t new_cap = buffer->cap ? buffer->cap : 256;
        uint8_t *new_data;

        while (new_cap < buffer->len + len) {
            new_cap *= 2;
        }
        new_data = realloc(buffer->data, new_cap);
        if (new_data == NULL) {
            perror("realloc");
            return -1;
        }
        buffer->data = new_data;
        buffer->cap = new_cap;
    }
    return 0;
}

static int byte_buffer_append_byte(byte_buffer_t *buffer, uint8_t value)
{
    if (byte_buffer_reserve(buffer, 1) < 0) {
        return -1;
    }
    buffer->data[buffer->len++] = value;
    return 0;
}

static int read_stdin_bytes(byte_buffer_t *buffer)
{
    int ch;

    while ((ch = getchar()) != EOF) {
        if (byte_buffer_append_byte(buffer, (uint8_t)ch) < 0) {
            return -1;
        }
    }
    return 0;
}

static int append_uart_rx_file(byte_buffer_t *buffer, const char *path)
{
    FILE *fp = fopen(path, "rb");
    uint8_t chunk[4096];

    if (fp == NULL) {
        perror(path);
        return -1;
    }
    for (;;) {
        size_t got = fread(chunk, 1, sizeof(chunk), fp);

        if (got != 0) {
            if (byte_buffer_reserve(buffer, got) < 0) {
                fclose(fp);
                return -1;
            }
            memcpy(buffer->data + buffer->len, chunk, got);
            buffer->len += got;
        }
        if (got < sizeof(chunk)) {
            if (ferror(fp)) {
                perror(path);
                fclose(fp);
                return -1;
            }
            break;
        }
    }
    fclose(fp);
    return 0;
}

static int append_uart_rx_text(byte_buffer_t *buffer, const char *text)
{
    const char *p = text;

    while (*p != '\0') {
        uint8_t value;

        if (*p != '\\') {
            value = (uint8_t)*p++;
        } else {
            p++;
            switch (*p) {
            case '\0':
                fprintf(stderr, "microemu: --uart-rx ends with an incomplete escape\n");
                return -1;
            case 'n':
                value = '\n';
                p++;
                break;
            case 'r':
                value = '\r';
                p++;
                break;
            case 't':
                value = '\t';
                p++;
                break;
            case '0':
                value = '\0';
                p++;
                break;
            case '\\':
                value = '\\';
                p++;
                break;
            case '"':
                value = '"';
                p++;
                break;
            case 'x': {
                int hi;
                int lo;

                p++;
                hi = hex_digit((unsigned char)p[0]);
                lo = hex_digit((unsigned char)p[1]);
                if (hi < 0 || lo < 0) {
                    fprintf(stderr, "microemu: invalid --uart-rx hex escape near '\\x%s'\n", p);
                    return -1;
                }
                value = (uint8_t)((hi << 4) | lo);
                p += 2;
                break;
            }
            default:
                fprintf(stderr, "microemu: unsupported --uart-rx escape '\\%c'\n", *p);
                return -1;
            }
        }
        if (byte_buffer_append_byte(buffer, value) < 0) {
            return -1;
        }
    }
    return 0;
}

static int append_uart_rx_hex(byte_buffer_t *buffer, const char *value)
{
    const char *p;
    bool separated = false;

    for (p = value; *p != '\0'; p++) {
        if (isspace((unsigned char)*p) || *p == ',' || *p == ':' || *p == '-') {
            separated = true;
            break;
        }
    }

    if (separated) {
        p = value;
        while (*p != '\0') {
            char *end = NULL;
            unsigned long byte;

            while (isspace((unsigned char)*p) || *p == ',' || *p == ':' || *p == '-') {
                p++;
            }
            if (*p == '\0') {
                break;
            }
            errno = 0;
            byte = strtoul(p, &end, 16);
            if (errno != 0 || end == p || byte > 0xffu) {
                fprintf(stderr, "microemu: invalid --uart-rx-hex near '%s'\n", p);
                return -1;
            }
            if (byte_buffer_append_byte(buffer, (uint8_t)byte) < 0) {
                return -1;
            }
            p = end;
        }
        return 0;
    }

    if ((strlen(value) & 1u) != 0) {
        fprintf(stderr, "microemu: --uart-rx-hex without separators needs an even digit count\n");
        return -1;
    }
    for (p = value; *p != '\0'; p += 2) {
        char token[3];
        char *end = NULL;
        unsigned long byte;

        token[0] = p[0];
        token[1] = p[1];
        token[2] = '\0';
        errno = 0;
        byte = strtoul(token, &end, 16);
        if (errno != 0 || end == token || *end != '\0' || byte > 0xffu) {
            fprintf(stderr, "microemu: invalid --uart-rx-hex byte '%s'\n", token);
            return -1;
        }
        if (byte_buffer_append_byte(buffer, (uint8_t)byte) < 0) {
            return -1;
        }
    }
    return 0;
}

static int parse_args(int argc, char **argv, config_t *cfg)
{
    int i;

    cfg->board_name = "hc1200-mcu";
    cfg->format = "auto";
    cfg->load_addr = 0;
    cfg->max_steps = 1000000u;

    for (i = 1; i < argc; i++) {
        const char *arg = argv[i];
        const char *value;

        if (strcmp(arg, "--help") == 0) {
            usage(stdout);
            exit(0);
        } else if (strcmp(arg, "--board") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            cfg->board_name = value;
        } else if (strcmp(arg, "--format") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            cfg->format = value;
        } else if (strcmp(arg, "--load-addr") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            if (!parse_u16(value, &cfg->load_addr)) {
                fprintf(stderr, "microemu: invalid --load-addr '%s'\n", value);
                return -1;
            }
        } else if (strcmp(arg, "--max-steps") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            if (!parse_u64(value, &cfg->max_steps)) {
                fprintf(stderr, "microemu: invalid --max-steps '%s'\n", value);
                return -1;
            }
            cfg->max_steps_set = true;
        } else if (strcmp(arg, "--trace") == 0) {
            cfg->trace = true;
        } else if (strcmp(arg, "--dump-regs") == 0) {
            cfg->dump_regs = true;
        } else if (strcmp(arg, "--stats") == 0) {
            cfg->stats = true;
        } else if (strcmp(arg, "--stop-on-self-branch") == 0) {
            cfg->stop_on_self_branch = true;
        } else if (strcmp(arg, "--stdin-rx") == 0) {
            cfg->stdin_rx = true;
        } else if (strcmp(arg, "--interactive-uart") == 0) {
            cfg->interactive_uart = true;
        } else if (strcmp(arg, "--quiet-uart") == 0) {
            cfg->quiet_uart = true;
        } else if (strcmp(arg, "--uart-rx") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            if (append_uart_rx_text(&cfg->uart_rx, value) < 0) {
                return -1;
            }
        } else if (strcmp(arg, "--uart-rx-hex") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            if (append_uart_rx_hex(&cfg->uart_rx, value) < 0) {
                return -1;
            }
        } else if (strcmp(arg, "--uart-rx-file") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            if (append_uart_rx_file(&cfg->uart_rx, value) < 0) {
                return -1;
            }
        } else if (arg[0] == '-') {
            fprintf(stderr, "microemu: unknown option '%s'\n", arg);
            return -1;
        } else if (cfg->program == NULL) {
            cfg->program = arg;
        } else {
            fprintf(stderr, "microemu: unexpected extra argument '%s'\n", arg);
            return -1;
        }
    }

    if (cfg->program == NULL) {
        usage(stderr);
        return -1;
    }
    if (strcmp(cfg->board_name, "hc1200-mcu") != 0 &&
        strcmp(cfg->board_name, "hc1200-cpu") != 0 &&
        strcmp(cfg->board_name, "hc1200-microcomp") != 0) {
        fprintf(stderr, "microemu: unsupported board '%s' (supported: hc1200-mcu, hc1200-cpu, hc1200-microcomp)\n",
            cfg->board_name);
        return -1;
    }
    if (strcmp(cfg->format, "auto") != 0 &&
        strcmp(cfg->format, "bin") != 0 &&
        strcmp(cfg->format, "hex") != 0 &&
        strcmp(cfg->format, "mem") != 0) {
        fprintf(stderr, "microemu: unsupported format '%s'\n", cfg->format);
        return -1;
    }
    if (cfg->interactive_uart && cfg->stdin_rx) {
        fprintf(stderr, "microemu: --interactive-uart cannot be used with --stdin-rx; use --uart-rx-file for the preload stream\n");
        return -1;
    }
    if (cfg->interactive_uart && cfg->quiet_uart) {
        fprintf(stderr, "microemu: --interactive-uart cannot be used with --quiet-uart\n");
        return -1;
    }
    if (cfg->interactive_uart && !cfg->max_steps_set) {
        cfg->max_steps = 0;
    }
    return 0;
}

static void mcu_load_byte_cb(void *ctx, uint16_t addr, uint8_t value)
{
    hc1200_mcu_load_byte(ctx, addr, value);
}

static void mcu_tick_cb(void *ctx, unsigned cycles)
{
    hc1200_mcu_tick(ctx, cycles);
}

static void mcu_dump_cb(const void *ctx, FILE *out)
{
    hc1200_mcu_dump(ctx, out);
}

static void mcu_set_quiet_uart_cb(void *ctx, bool quiet)
{
    hc1200_mcu_set_quiet_uart(ctx, quiet);
}

static int mcu_set_interactive_uart_cb(void *ctx, bool interactive)
{
    return hc1200_mcu_set_interactive_uart(ctx, interactive);
}

static int mcu_uart_rx_append_cb(void *ctx, const uint8_t *data, size_t len)
{
    return hc1200_mcu_uart_rx_append(ctx, data, len);
}

static void cpu_load_byte_cb(void *ctx, uint16_t addr, uint8_t value)
{
    hc1200_cpu_load_byte(ctx, addr, value);
}

static void cpu_tick_cb(void *ctx, unsigned cycles)
{
    hc1200_cpu_tick(ctx, cycles);
}

static void cpu_dump_cb(const void *ctx, FILE *out)
{
    hc1200_cpu_dump(ctx, out);
}

static void cpu_set_quiet_uart_cb(void *ctx, bool quiet)
{
    hc1200_cpu_set_quiet_uart(ctx, quiet);
}

static int cpu_set_interactive_uart_cb(void *ctx, bool interactive)
{
    return hc1200_cpu_set_interactive_uart(ctx, interactive);
}

static int cpu_uart_rx_append_cb(void *ctx, const uint8_t *data, size_t len)
{
    return hc1200_cpu_uart_rx_append(ctx, data, len);
}

static void microcomp_load_byte_cb(void *ctx, uint16_t addr, uint8_t value)
{
    hc1200_microcomp_load_byte(ctx, addr, value);
}

static void microcomp_tick_cb(void *ctx, unsigned cycles)
{
    hc1200_microcomp_tick(ctx, cycles);
}

static void microcomp_dump_cb(const void *ctx, FILE *out)
{
    hc1200_microcomp_dump(ctx, out);
}

static void microcomp_set_quiet_uart_cb(void *ctx, bool quiet)
{
    hc1200_microcomp_set_quiet_uart(ctx, quiet);
}

static int microcomp_set_interactive_uart_cb(void *ctx, bool interactive)
{
    return hc1200_microcomp_set_interactive_uart(ctx, interactive);
}

static int microcomp_uart_rx_append_cb(void *ctx, const uint8_t *data, size_t len)
{
    return hc1200_microcomp_uart_rx_append(ctx, data, len);
}

static int select_board(const config_t *cfg, hc1200_mcu_t *mcu_board,
    hc1200_cpu_t *cpu_board, hc1200_microcomp_t *microcomp_board,
    board_model_t *board)
{
    memset(board, 0, sizeof(*board));
    board->name = cfg->board_name;

    if (strcmp(cfg->board_name, "hc1200-mcu") == 0) {
        board->ctx = mcu_board;
        board->bus = hc1200_mcu_bus(mcu_board);
        board->load_byte = mcu_load_byte_cb;
        board->tick = mcu_tick_cb;
        board->dump = mcu_dump_cb;
        board->set_quiet_uart = mcu_set_quiet_uart_cb;
        board->set_interactive_uart = mcu_set_interactive_uart_cb;
        board->uart_rx_append = mcu_uart_rx_append_cb;
        return 0;
    }
    if (strcmp(cfg->board_name, "hc1200-cpu") == 0) {
        board->ctx = cpu_board;
        board->bus = hc1200_cpu_bus(cpu_board);
        board->load_byte = cpu_load_byte_cb;
        board->tick = cpu_tick_cb;
        board->dump = cpu_dump_cb;
        board->set_quiet_uart = cpu_set_quiet_uart_cb;
        board->set_interactive_uart = cpu_set_interactive_uart_cb;
        board->uart_rx_append = cpu_uart_rx_append_cb;
        return 0;
    }
    if (strcmp(cfg->board_name, "hc1200-microcomp") == 0) {
        board->ctx = microcomp_board;
        board->bus = hc1200_microcomp_bus(microcomp_board);
        board->load_byte = microcomp_load_byte_cb;
        board->tick = microcomp_tick_cb;
        board->dump = microcomp_dump_cb;
        board->set_quiet_uart = microcomp_set_quiet_uart_cb;
        board->set_interactive_uart = microcomp_set_interactive_uart_cb;
        board->uart_rx_append = microcomp_uart_rx_append_cb;
        return 0;
    }

    fprintf(stderr, "microemu: unsupported board '%s'\n", cfg->board_name);
    return -1;
}

static bool buffer_looks_like_hex(const uint8_t *data, size_t len)
{
    bool has_hex = false;
    size_t i;

    for (i = 0; i < len; i++) {
        unsigned char ch = data[i];

        if (isxdigit(ch)) {
            has_hex = true;
        } else if (isspace(ch) || ch == '@' || ch == ':' || ch == '_' || ch == '/' ||
                   ch == '*' || ch == '#') {
            continue;
        } else {
            return false;
        }
    }
    return has_hex;
}

static int read_file(const char *path, uint8_t **data, size_t *len)
{
    FILE *fp = fopen(path, "rb");
    long size;
    size_t got;

    if (fp == NULL) {
        perror(path);
        return -1;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        perror(path);
        fclose(fp);
        return -1;
    }
    size = ftell(fp);
    if (size < 0) {
        perror(path);
        fclose(fp);
        return -1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        perror(path);
        fclose(fp);
        return -1;
    }
    *data = malloc((size_t)size + 1u);
    if (*data == NULL) {
        perror("malloc");
        fclose(fp);
        return -1;
    }
    got = fread(*data, 1, (size_t)size, fp);
    if (got != (size_t)size) {
        fprintf(stderr, "microemu: short read from %s\n", path);
        free(*data);
        fclose(fp);
        return -1;
    }
    fclose(fp);
    (*data)[got] = 0;
    *len = got;
    return 0;
}

static void skip_hex_space_and_comments(const uint8_t *data, size_t len, size_t *pos)
{
    for (;;) {
        while (*pos < len && isspace((unsigned char)data[*pos])) {
            *pos += 1;
        }
        if (*pos + 1 < len && data[*pos] == '/' && data[*pos + 1] == '/') {
            *pos += 2;
            while (*pos < len && data[*pos] != '\n') {
                *pos += 1;
            }
            continue;
        }
        if (*pos < len && data[*pos] == '#') {
            while (*pos < len && data[*pos] != '\n') {
                *pos += 1;
            }
            continue;
        }
        break;
    }
}

static int parse_hex_token(const char *token, unsigned long *value)
{
    char compact[128];
    size_t i;
    size_t j = 0;
    char *end = NULL;

    for (i = 0; token[i] != '\0'; i++) {
        if (token[i] != '_') {
            if (j + 1 >= sizeof(compact)) {
                return -1;
            }
            compact[j++] = token[i];
        }
    }
    compact[j] = '\0';

    errno = 0;
    *value = strtoul(compact, &end, 16);
    if (errno != 0 || end == compact || *end != '\0') {
        return -1;
    }
    return 0;
}

static int load_hex_image(const board_model_t *board, const uint8_t *data, size_t len)
{
    uint32_t addr = 0;
    size_t pos = 0;

    while (pos < len) {
        char token[128];
        size_t tlen = 0;
        unsigned long value;

        skip_hex_space_and_comments(data, len, &pos);
        if (pos >= len) {
            break;
        }
        while (pos < len && !isspace((unsigned char)data[pos])) {
            if (tlen + 1 >= sizeof(token)) {
                fprintf(stderr, "microemu: hex token is too long\n");
                return -1;
            }
            token[tlen++] = (char)data[pos++];
        }
        token[tlen] = '\0';
        if (token[0] == '\0') {
            continue;
        }
        if (token[0] == '@') {
            if (parse_hex_token(token + 1, &value) < 0 || value > 0xffffu) {
                fprintf(stderr, "microemu: invalid hex address '%s'\n", token);
                return -1;
            }
            addr = (uint32_t)value;
            continue;
        }
        if (tlen > 1 && token[tlen - 1] == ':') {
            token[tlen - 1] = '\0';
            if (parse_hex_token(token, &value) < 0 || value > 0xffffu) {
                fprintf(stderr, "microemu: invalid hex address '%s:'\n", token);
                return -1;
            }
            addr = (uint32_t)value;
            continue;
        }
        if (parse_hex_token(token, &value) < 0 || value > 0xffu) {
            fprintf(stderr, "microemu: invalid hex byte '%s'\n", token);
            return -1;
        }
        board->load_byte(board->ctx, (uint16_t)addr, (uint8_t)value);
        addr = (addr + 1u) & 0xffffu;
    }
    return 0;
}

static int load_binary_image(const board_model_t *board, const uint8_t *data, size_t len,
    uint16_t load_addr)
{
    size_t i;
    uint32_t addr = load_addr;

    for (i = 0; i < len; i++) {
        board->load_byte(board->ctx, (uint16_t)addr, data[i]);
        addr = (addr + 1u) & 0xffffu;
    }
    return 0;
}

static int load_image(const board_model_t *board, const config_t *cfg)
{
    uint8_t *data = NULL;
    size_t len = 0;
    int rc;
    bool use_hex;

    if (read_file(cfg->program, &data, &len) < 0) {
        return -1;
    }

    if (strcmp(cfg->format, "hex") == 0 || strcmp(cfg->format, "mem") == 0) {
        use_hex = true;
    } else if (strcmp(cfg->format, "bin") == 0) {
        use_hex = false;
    } else {
        use_hex = buffer_looks_like_hex(data, len);
    }

    rc = use_hex ? load_hex_image(board, data, len)
                 : load_binary_image(board, data, len, cfg->load_addr);
    free(data);
    return rc;
}

int main(int argc, char **argv)
{
    hc1200_mcu_t mcu_board;
    hc1200_cpu_t cpu_board;
    hc1200_microcomp_t microcomp_board;
    board_model_t board;
    microcpu_t cpu;
    microcpu_step_options_t step_options;
    config_t cfg;
    uint64_t step = 0;
    uint64_t cycle_count = 0;
    int exit_code = 0;
    bool stopped_on_self_branch = false;
    bool interrupted = false;

    hc1200_mcu_init(&mcu_board);
    hc1200_cpu_init(&cpu_board);
    hc1200_microcomp_init(&microcomp_board);
    memset(&cfg, 0, sizeof(cfg));
    if (parse_args(argc, argv, &cfg) < 0) {
        byte_buffer_destroy(&cfg.uart_rx);
        hc1200_microcomp_destroy(&microcomp_board);
        hc1200_cpu_destroy(&cpu_board);
        hc1200_mcu_destroy(&mcu_board);
        return 2;
    }
    if (select_board(&cfg, &mcu_board, &cpu_board, &microcomp_board, &board) < 0) {
        byte_buffer_destroy(&cfg.uart_rx);
        hc1200_microcomp_destroy(&microcomp_board);
        hc1200_cpu_destroy(&cpu_board);
        hc1200_mcu_destroy(&mcu_board);
        return 2;
    }
    if (cfg.stdin_rx && read_stdin_bytes(&cfg.uart_rx) < 0) {
        byte_buffer_destroy(&cfg.uart_rx);
        hc1200_microcomp_destroy(&microcomp_board);
        hc1200_cpu_destroy(&cpu_board);
        hc1200_mcu_destroy(&mcu_board);
        return 1;
    }
    if (cfg.quiet_uart) {
        board.set_quiet_uart(board.ctx, true);
    }
    if (cfg.uart_rx.len != 0 &&
        board.uart_rx_append(board.ctx, cfg.uart_rx.data, cfg.uart_rx.len) < 0) {
        byte_buffer_destroy(&cfg.uart_rx);
        hc1200_microcomp_destroy(&microcomp_board);
        hc1200_cpu_destroy(&cpu_board);
        hc1200_mcu_destroy(&mcu_board);
        return 1;
    }
    if (load_image(&board, &cfg) < 0) {
        byte_buffer_destroy(&cfg.uart_rx);
        hc1200_microcomp_destroy(&microcomp_board);
        hc1200_cpu_destroy(&cpu_board);
        hc1200_mcu_destroy(&mcu_board);
        return 1;
    }
    if (cfg.interactive_uart) {
        stop_requested = 0;
        if (signal(SIGINT, handle_stop_signal) == SIG_ERR ||
            signal(SIGTERM, handle_stop_signal) == SIG_ERR) {
            perror("signal");
            byte_buffer_destroy(&cfg.uart_rx);
            hc1200_microcomp_destroy(&microcomp_board);
            hc1200_cpu_destroy(&cpu_board);
            hc1200_mcu_destroy(&mcu_board);
            return 1;
        }
#ifdef SIGHUP
        if (signal(SIGHUP, handle_stop_signal) == SIG_ERR) {
            perror("signal");
            byte_buffer_destroy(&cfg.uart_rx);
            hc1200_microcomp_destroy(&microcomp_board);
            hc1200_cpu_destroy(&cpu_board);
            hc1200_mcu_destroy(&mcu_board);
            return 1;
        }
#endif
        if (board.set_interactive_uart(board.ctx, true) < 0) {
            byte_buffer_destroy(&cfg.uart_rx);
            hc1200_microcomp_destroy(&microcomp_board);
            hc1200_cpu_destroy(&cpu_board);
            hc1200_mcu_destroy(&mcu_board);
            return 1;
        }
    }

    microcpu_init(&cpu, board.bus);
    memset(&step_options, 0, sizeof(step_options));
    step_options.trace = cfg.trace;
    step_options.stop_on_self_branch = cfg.stop_on_self_branch;
    step_options.trace_file = stderr;

    while (!stop_requested && (cfg.max_steps == 0 || step < cfg.max_steps)) {
        unsigned cycles = 0;
        microcpu_step_result_t result = microcpu_step(&cpu, step, &step_options, &cycles);

        if (result == MICROCPU_STEP_ERROR) {
            exit_code = 1;
            break;
        }
        board.tick(board.ctx, cycles);
        cycle_count += cycles;
        step++;
        if (result == MICROCPU_STEP_SELF_BRANCH) {
            fprintf(stderr, "\nmicroemu: stopped on self-branch at %04x after %" PRIu64 " steps\n",
                cpu.r[0], step);
            stopped_on_self_branch = true;
            exit_code = 0;
            break;
        }
    }

    if (stop_requested && exit_code == 0) {
        fprintf(stderr, "\nmicroemu: interrupted\n");
        exit_code = 130;
        interrupted = true;
    }

    if (!stopped_on_self_branch && (cfg.max_steps != 0 && step >= cfg.max_steps) &&
        exit_code == 0) {
        fprintf(stderr, "\nmicroemu: max steps reached (%" PRIu64 ")\n", cfg.max_steps);
        exit_code = 124;
    }

    if (cfg.stats) {
        fprintf(stderr, "microemu: stats: steps=%" PRIu64 " cycles=%" PRIu64 "\n",
            step, cycle_count);
    }

    if (cfg.dump_regs || (exit_code != 0 && !interrupted)) {
        microcpu_dump_regs(&cpu, stderr);
        board.dump(board.ctx, stderr);
    }
    byte_buffer_destroy(&cfg.uart_rx);
    hc1200_microcomp_destroy(&microcomp_board);
    hc1200_cpu_destroy(&cpu_board);
    hc1200_mcu_destroy(&mcu_board);
    return exit_code;
}
