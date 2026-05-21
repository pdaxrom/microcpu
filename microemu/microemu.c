#include "hc1200_mcu.h"
#include "microcpu_core.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *board_name;
    const char *format;
    const char *program;
    uint16_t load_addr;
    uint64_t max_steps;
    bool trace;
    bool dump_regs;
    bool stop_on_self_branch;
    bool stdin_rx;
} config_t;

static void usage(FILE *out)
{
    fprintf(out,
        "usage: microemu [options] <program>\n"
        "\n"
        "Options:\n"
        "  --board hc1200-mcu          board model (default)\n"
        "  --format auto|bin|hex       input format (default: auto)\n"
        "  --load-addr ADDR            binary load address (default: 0)\n"
        "  --max-steps N               instruction limit, 0 means unlimited (default: 1000000)\n"
        "  --stop-on-self-branch       stop successfully on a 'b *' idle loop\n"
        "  --trace                     print executed instructions to stderr\n"
        "  --dump-regs                 print CPU registers at exit\n"
        "  --uart-rx TEXT              preload UART RX bytes from text\n"
        "  --uart-rx-hex HEX           preload UART RX bytes from hex bytes\n"
        "  --stdin-rx                  read all stdin bytes into UART RX before running\n"
        "  --quiet-uart                discard UART TX instead of writing it to stdout\n"
        "  --help                      show this help\n");
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

static int append_uart_rx_text(hc1200_mcu_t *board, const char *text)
{
    return hc1200_mcu_uart_rx_append(board, (const uint8_t *)text, strlen(text));
}

static int append_uart_rx_hex(hc1200_mcu_t *board, const char *value)
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
            if (hc1200_mcu_uart_rx_push(board, (uint8_t)byte) < 0) {
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
        if (hc1200_mcu_uart_rx_push(board, (uint8_t)byte) < 0) {
            return -1;
        }
    }
    return 0;
}

static int parse_args(int argc, char **argv, config_t *cfg, hc1200_mcu_t *board)
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
        } else if (strcmp(arg, "--trace") == 0) {
            cfg->trace = true;
        } else if (strcmp(arg, "--dump-regs") == 0) {
            cfg->dump_regs = true;
        } else if (strcmp(arg, "--stop-on-self-branch") == 0) {
            cfg->stop_on_self_branch = true;
        } else if (strcmp(arg, "--stdin-rx") == 0) {
            cfg->stdin_rx = true;
        } else if (strcmp(arg, "--quiet-uart") == 0) {
            hc1200_mcu_set_quiet_uart(board, true);
        } else if (strcmp(arg, "--uart-rx") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            if (append_uart_rx_text(board, value) < 0) {
                return -1;
            }
        } else if (strcmp(arg, "--uart-rx-hex") == 0) {
            if (require_arg(argc, argv, &i, arg, &value) < 0) {
                return -1;
            }
            if (append_uart_rx_hex(board, value) < 0) {
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
    if (strcmp(cfg->board_name, "hc1200-mcu") != 0) {
        fprintf(stderr, "microemu: unsupported board '%s' (only hc1200-mcu)\n",
            cfg->board_name);
        return -1;
    }
    if (strcmp(cfg->format, "auto") != 0 &&
        strcmp(cfg->format, "bin") != 0 &&
        strcmp(cfg->format, "hex") != 0) {
        fprintf(stderr, "microemu: unsupported format '%s'\n", cfg->format);
        return -1;
    }
    return 0;
}

static bool buffer_looks_like_hex(const uint8_t *data, size_t len)
{
    bool has_hex = false;
    size_t i;

    for (i = 0; i < len; i++) {
        unsigned char ch = data[i];

        if (isxdigit(ch)) {
            has_hex = true;
        } else if (isspace(ch) || ch == '@' || ch == '_' || ch == '/' ||
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

static int load_hex_image(hc1200_mcu_t *board, const uint8_t *data, size_t len)
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
        if (parse_hex_token(token, &value) < 0 || value > 0xffu) {
            fprintf(stderr, "microemu: invalid hex byte '%s'\n", token);
            return -1;
        }
        hc1200_mcu_load_byte(board, (uint16_t)addr, (uint8_t)value);
        addr = (addr + 1u) & 0xffffu;
    }
    return 0;
}

static int load_binary_image(hc1200_mcu_t *board, const uint8_t *data, size_t len,
    uint16_t load_addr)
{
    size_t i;
    uint32_t addr = load_addr;

    for (i = 0; i < len; i++) {
        hc1200_mcu_load_byte(board, (uint16_t)addr, data[i]);
        addr = (addr + 1u) & 0xffffu;
    }
    return 0;
}

static int load_image(hc1200_mcu_t *board, const config_t *cfg)
{
    uint8_t *data = NULL;
    size_t len = 0;
    int rc;
    bool use_hex;

    if (read_file(cfg->program, &data, &len) < 0) {
        return -1;
    }

    if (strcmp(cfg->format, "hex") == 0) {
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
    hc1200_mcu_t board;
    microcpu_t cpu;
    microcpu_step_options_t step_options;
    config_t cfg;
    uint64_t step = 0;
    int exit_code = 0;
    bool stopped_on_self_branch = false;

    hc1200_mcu_init(&board);
    memset(&cfg, 0, sizeof(cfg));
    if (parse_args(argc, argv, &cfg, &board) < 0) {
        hc1200_mcu_destroy(&board);
        return 2;
    }
    if (cfg.stdin_rx && hc1200_mcu_uart_rx_read_stdin(&board) < 0) {
        hc1200_mcu_destroy(&board);
        return 1;
    }
    if (load_image(&board, &cfg) < 0) {
        hc1200_mcu_destroy(&board);
        return 1;
    }

    microcpu_init(&cpu, hc1200_mcu_bus(&board));
    memset(&step_options, 0, sizeof(step_options));
    step_options.trace = cfg.trace;
    step_options.stop_on_self_branch = cfg.stop_on_self_branch;
    step_options.trace_file = stderr;

    while (cfg.max_steps == 0 || step < cfg.max_steps) {
        unsigned cycles = 0;
        microcpu_step_result_t result = microcpu_step(&cpu, step, &step_options, &cycles);

        if (result == MICROCPU_STEP_ERROR) {
            exit_code = 1;
            break;
        }
        hc1200_mcu_tick(&board, cycles);
        step++;
        if (result == MICROCPU_STEP_SELF_BRANCH) {
            fprintf(stderr, "\nmicroemu: stopped on self-branch at %04x after %" PRIu64 " steps\n",
                cpu.r[0], step);
            stopped_on_self_branch = true;
            exit_code = 0;
            break;
        }
    }

    if (!stopped_on_self_branch && (cfg.max_steps != 0 && step >= cfg.max_steps) &&
        exit_code == 0) {
        fprintf(stderr, "\nmicroemu: max steps reached (%" PRIu64 ")\n", cfg.max_steps);
        exit_code = 124;
    }

    if (cfg.dump_regs || exit_code != 0) {
        microcpu_dump_regs(&cpu, stderr);
        hc1200_mcu_dump(&board, stderr);
    }
    hc1200_mcu_destroy(&board);
    return exit_code;
}
