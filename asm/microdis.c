#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "cpu_target.h"

enum {
    INPUT_AUTO = 0,
    INPUT_BINARY,
    INPUT_OBJECT,
};

enum {
    RELOC_LSB = 0x01,
    RELOC_MSB = 0x02,
    RELOC_WORD = 0x03,
    RELOC_UADDR12 = 0x04,
};

typedef struct {
    char name[16];
    unsigned int value;
    int absolute;
} Symbol;

typedef struct {
    unsigned char type;
    unsigned int value;
    unsigned int offset;
    int external;
} Reloc;

typedef struct {
    int cpu;
    Symbol *entries;
    unsigned int entry_count;
    Symbol *externs;
    unsigned int extern_count;
    Reloc *relocs;
    unsigned int reloc_count;
    unsigned char *code;
    unsigned int code_len;
    unsigned int code_file_offset;
    unsigned int entry_offset;
} Object;

typedef struct {
    unsigned int offset;
    char text[128];
} RelocNote;

static const char *regs[] = {
    "pc", "sp", "lr", "v0", "v1", "v2", "v3", "v4"
};

static unsigned int origin = 0;
static int target_cpu = CPU_ORIGINAL;
static int cpu_explicit = 0;

static unsigned int read_u16(unsigned char *buf)
{
    return buf[0] | (buf[1] << 8);
}

static unsigned int read_u32(unsigned char *buf)
{
    return read_u16(buf) | (read_u16(buf + 2) << 16);
}

static int parse_number(char *str, unsigned int *value)
{
    int base = 10;
    char *end;

    if (*str == '$') {
        base = 16;
        str++;
    } else if (*str == '%') {
        unsigned int val = 0;

        str++;
        if (*str != '0' && *str != '1') {
            return 1;
        }
        while (*str == '0' || *str == '1' || *str == '_') {
            if (*str != '_') {
                val = (val << 1) | (*str - '0');
            }
            str++;
        }
        if (*str) {
            return 1;
        }
        *value = val;
        return 0;
    } else if (str[0] == '0' && tolower(str[1]) == 'x') {
        base = 16;
    }

    *value = strtoul(str, &end, base);
    return *end != 0;
}

static int read_file(char *path, unsigned char **buf, size_t *size)
{
    FILE *fp = fopen(path, "rb");
    long len;

    if (!fp) {
        fprintf(stderr, "Cannot open input file: %s\n", path);
        return 1;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return 1;
    }
    len = ftell(fp);
    if (len < 0) {
        fclose(fp);
        return 1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return 1;
    }

    *buf = malloc(len ? (size_t)len : 1);
    if (!*buf) {
        fclose(fp);
        fprintf(stderr, "Out of memory\n");
        return 1;
    }
    if (fread(*buf, 1, len, fp) != (size_t)len) {
        free(*buf);
        fclose(fp);
        return 1;
    }

    fclose(fp);
    *size = len;
    return 0;
}

static void read_name(char *dst, unsigned char *src)
{
    memcpy(dst, src, 15);
    dst[15] = 0;
}

static int looks_like_object(unsigned char *buf, size_t size)
{
    unsigned int ent_count;
    unsigned int ext_count;
    unsigned int code_len;
    unsigned int code_offset;

    if (size < 0x20 || read_u16(buf) != 0x5aa5 || read_u16(buf + 2) < 1 || read_u16(buf + 2) > 4) {
        return 0;
    }

    ent_count = read_u16(buf + 4);
    ext_count = read_u16(buf + 6);
    code_len = read_u16(buf + 8);
    code_offset = read_u32(buf + 0x0a);

    return code_offset >= 0x20 + (ent_count + ext_count) * 20 &&
           code_offset <= size &&
           code_len <= size - code_offset;
}

static int parse_object(unsigned char *buf, size_t size, Object *obj)
{
    unsigned int ent_count, ext_count, code_len, code_offset;
    unsigned int pos;

    if (!looks_like_object(buf, size)) {
        fprintf(stderr, "Invalid object file\n");
        return 1;
    }

    ent_count = read_u16(buf + 4);
    ext_count = read_u16(buf + 6);
    code_len = read_u16(buf + 8);
    code_offset = read_u32(buf + 0x0a);
    int object_cpu = read_u16(buf + 2) == 1 ? CPU_ORIGINAL : read_u16(buf + 0x10);
    if (!cpu_object_supported(read_u16(buf + 2), object_cpu)) {
        fprintf(stderr, "Unsupported object version %u for CPU %s; rebuild object\n",
                read_u16(buf + 2), cpu_name(object_cpu));
        return 1;
    }
    if (cpu_explicit && target_cpu != object_cpu) {
        fprintf(stderr, "Object CPU '%s' does not match selected CPU '%s'\n",
                cpu_name(object_cpu), cpu_name(target_cpu));
        return 1;
    }
    target_cpu = object_cpu;

    memset(obj, 0, sizeof(*obj));
    obj->cpu = object_cpu;
    obj->entry_count = ent_count;
    obj->extern_count = ext_count;
    obj->code_len = code_len;
    obj->code_file_offset = code_offset;
    obj->entry_offset = read_u16(buf + 0x0e);

    obj->entries = calloc(ent_count ? ent_count : 1, sizeof(Symbol));
    obj->externs = calloc(ext_count ? ext_count : 1, sizeof(Symbol));
    obj->code = malloc(code_len ? code_len : 1);
    if (!obj->entries || !obj->externs || !obj->code) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }

    pos = 0x20;
    for (unsigned int i = 0; i < ent_count; i++) {
        read_name(obj->entries[i].name, buf + pos);
        obj->entries[i].value = read_u16(buf + pos + 0x10);
        obj->entries[i].absolute = (short)read_u16(buf + pos + 0x12) < 0;
        pos += 20;
    }
    for (unsigned int i = 0; i < ext_count; i++) {
        read_name(obj->externs[i].name, buf + pos);
        pos += 20;
    }

    memcpy(obj->code, buf + code_offset, code_len);
    pos = code_offset + code_len;
    if (pos + 2 > size) {
        fprintf(stderr, "Missing relocation table\n");
        return 1;
    }

    obj->reloc_count = read_u16(buf + pos);
    pos += 2;
    if (pos + obj->reloc_count * 5 > size) {
        fprintf(stderr, "Invalid relocation table\n");
        return 1;
    }

    obj->relocs = calloc(obj->reloc_count ? obj->reloc_count : 1,
                         sizeof(Reloc));
    if (!obj->relocs) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }

    for (unsigned int i = 0; i < obj->reloc_count; i++) {
        unsigned char raw_type = buf[pos++];

        obj->relocs[i].external = (raw_type & 0x80) != 0;
        obj->relocs[i].type = raw_type & 0x7f;
        obj->relocs[i].value = read_u16(buf + pos);
        obj->relocs[i].offset = read_u16(buf + pos + 2);
        pos += 4;
    }

    return 0;
}

static const char *reg_or_imm(unsigned int arg3, char *buf, size_t size)
{
    if (arg3 & 1) {
        snprintf(buf, size, "%u", (arg3 >> 1) & 0x0f);
        return buf;
    }
    return regs[(arg3 >> 2) & 0x07];
}

static void decode_instruction(unsigned int addr, unsigned char lo,
                               unsigned char hi, char *buf, size_t size)
{
    unsigned int op = lo >> 3;
    unsigned int arg1 = lo & 0x07;
    unsigned int arg2 = hi >> 5;
    unsigned int arg3 = hi & 0x1f;
    unsigned int imm8 = hi;
    char tmp[16];

    /* Unknown encodings remain data instead of borrowing another CPU's ISA. */
    if (target_cpu == CPU_UCODE && ((lo & 0xf0) == 0x70 || (lo & 0xf0) == 0xf0)) {
        snprintf(buf, size, "%s $%04X", (lo & 0xf0) == 0x70 ? "call" : "jmp",
                 (((lo & 15) << 8) | hi) * 2);
        return;
    }
    if (target_cpu == CPU_ORIGINAL && (op == 0x0b || op == 0x1c)) {
        snprintf(buf, size, "dw $%02X%02X", hi, lo);
        return;
    }

    if (op == 0x1c && hi != 0) {
        if (target_cpu == CPU_UCODE && ((hi >> 6) == 1 || (hi >> 6) == 2)) {
            int rel = hi & 63;
            if (rel & 32) rel -= 64;
            snprintf(buf, size, "%s %s, $%04X", hi & 128 ? "cbnz" : "cbz",
                     regs[arg1], (addr + rel * 2) & 8191);
        } else {
            snprintf(buf, size, "dw $%02X%02X", hi, lo);
        }
        return;
    }

    if (target_cpu == CPU_UCODE && arg1 == 0 &&
            (op == 0x00 || op == 0x04 || op == 0x08 || op == 0x0a ||
             op == 0x0c || op == 0x1c || ((op & 1) && op != 0x01 && op != 0x03))) {
        snprintf(buf, size, "dw $%02X%02X", hi, lo);
        return;
    }

    switch (op) {
    case 0x07:
    case 0x0d:
        if (target_cpu == CPU_UCODE)
            snprintf(buf, size, "%s %s, %s, %s", op == 0x07 ? "adc" : "sbc",
                     regs[arg1], regs[arg2], reg_or_imm(arg3, tmp, sizeof(tmp)));
        else snprintf(buf, size, "dw $%02X%02X", hi, lo);
        break;
    case 0x05:
        if (target_cpu == CPU_UCODE)
            snprintf(buf, size, "xor %s, %s, %s", regs[arg1], regs[arg2],
                     reg_or_imm(arg3, tmp, sizeof(tmp)));
        else snprintf(buf, size, "dw $%02X%02X", hi, lo);
        break;
    case 0x00:
        snprintf(buf, size, "ldrl %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x02:
        snprintf(buf, size, "strl %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x04:
        snprintf(buf, size, "ldr %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x06:
        snprintf(buf, size, "str %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x08:
        snprintf(buf, size, "setl %s, $%02X", regs[arg1], imm8);
        break;
    case 0x0a:
        snprintf(buf, size, "seth %s, $%02X", regs[arg1], imm8);
        break;
    case 0x0c:
        if (target_cpu == CPU_UCODE)
            snprintf(buf, size, "ldi8 %s, $%02X", regs[arg1], imm8);
        else
            snprintf(buf, size, "movl %s, %s", regs[arg1], regs[arg2]);
        break;
    case 0x0e:
        snprintf(buf, size, "movh %s, %s", regs[arg1], regs[arg2]);
        break;
    case 0x10:
        if (target_cpu == CPU_UCODE && lo == 0x80 && hi == 0x40)
            snprintf(buf, size, "ret");
        else snprintf(buf, size, "mov %s, %s", regs[arg1], regs[arg2]);
        break;
    case 0x12:
        if (target_cpu == CPU_ORIGINAL) {
            snprintf(buf, size, "sws");
        } else {
            snprintf(buf, size, "gget %s, $%X", regs[arg1], hi & (target_cpu == CPU_UCODE ? 0x3f : 0x1f));
        }
        break;
    case 0x14:
        if (target_cpu == CPU_ORIGINAL) {
            snprintf(buf, size, "swu");
        } else {
            snprintf(buf, size, "gset %s, $%X", regs[arg1], hi & (target_cpu == CPU_UCODE ? 0x3f : 0x1f));
        }
        break;
    case 0x16: {
        int rel = (arg1 << 8) | (arg2 << 5) | arg3;
        if (rel & 0x400) {
            rel |= ~0x7ff;
        }
        snprintf(buf, size, "b $%04X", (addr + (rel << 1)) & 0xffff);
        break;
    }
    case 0x18:
        if (target_cpu == CPU_ORIGINAL) {
            snprintf(buf, size, "setp %s", regs[arg1]);
        } else {
            snprintf(buf, size, "ggetr %s, %s", regs[arg1], regs[arg2]);
        }
        break;
    case 0x1a:
        if (target_cpu == CPU_ORIGINAL) {
            snprintf(buf, size, "getp %s", regs[arg1]);
        } else {
            snprintf(buf, size, "gsetr %s, %s", regs[arg1], regs[arg2]);
        }
        break;
    case 0x1c:
        snprintf(buf, size, "getf %s", regs[arg1]);
        break;
    case 0x01: {
        static const char *ext[] = {
            "eq", "ne", "mi", "vs", "lt", "ge", "ltu", "geu"
        };
        snprintf(buf, size, "%s %s, %s", ext[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    }
    case 0x03:
        if (arg1 > 1) {
            snprintf(buf, size, "dw $%02X%02X", hi, lo);
        } else {
            snprintf(buf, size, "%s %s, %s", arg1 ? "bts" : "btc",
                     regs[arg2], reg_or_imm(arg3, tmp, sizeof(tmp)));
        }
        break;
    case 0x09:
        snprintf(buf, size, "sxt %s, %s", regs[arg1], regs[arg2]);
        break;
    case 0x0b:
        snprintf(buf, size, "subb %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x11:
        snprintf(buf, size, "add %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x13:
        snprintf(buf, size, "sub %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x15:
        snprintf(buf, size, "shl %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x17:
        snprintf(buf, size, "shr %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x19:
        snprintf(buf, size, "and %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x1b:
        snprintf(buf, size, "or %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    case 0x1d:
        snprintf(buf, size, "inv %s, %s", regs[arg1], regs[arg2]);
        break;
    case 0x1f:
        snprintf(buf, size, "xor %s, %s, %s", regs[arg1], regs[arg2],
                 reg_or_imm(arg3, tmp, sizeof(tmp)));
        break;
    default:
        snprintf(buf, size, "dw $%02X%02X", hi, lo);
        break;
    }
}

static void print_matching_labels(Object *obj, unsigned int offset)
{
    for (unsigned int i = 0; i < obj->entry_count; i++) {
        if (!obj->entries[i].absolute && obj->entries[i].value == offset) {
            printf("%s:\n", obj->entries[i].name);
        }
    }
}

static void append_reloc_note(char *dst, size_t size, Object *obj,
                              unsigned int off)
{
    for (unsigned int i = 0; i < obj->reloc_count; i++) {
        Reloc *reloc = &obj->relocs[i];
        const char *kind = NULL;
        char sym[32];

        if (reloc->offset != off && reloc->offset != off + 1) {
            continue;
        }

        if (reloc->type == RELOC_UADDR12) {
            kind = "uaddr12";
        } else if (reloc->type == RELOC_WORD) {
            kind = "word";
        } else if (reloc->type == RELOC_LSB) {
            kind = "lsb";
        } else if (reloc->type == RELOC_MSB) {
            kind = "msb";
        } else {
            kind = "?";
        }

        if (reloc->external && reloc->value < obj->extern_count) {
            snprintf(sym, sizeof(sym), "%s", obj->externs[reloc->value].name);
        } else {
            snprintf(sym, sizeof(sym), "code_base");
        }

        if (dst[0]) {
            strncat(dst, ", ", size - strlen(dst) - 1);
        }
        snprintf(dst + strlen(dst), size - strlen(dst), "reloc %s %s",
                 kind, sym);
    }
}

static void disassemble(unsigned char *code, unsigned int code_len,
                        Object *obj)
{
    for (unsigned int off = 0; off < code_len; off += 2) {
        unsigned int addr = (origin + off) & 0xffff;
        char inst[128];
        char note[256] = "";

        if (obj) {
            print_matching_labels(obj, off);
            append_reloc_note(note, sizeof(note), obj, off);
        }

        if (off + 1 >= code_len) {
            printf("%04X: %02X      db $%02X", addr, code[off], code[off]);
        } else {
            decode_instruction(addr, code[off], code[off + 1], inst,
                               sizeof(inst));
            printf("%04X: %02X%02X    %s", addr, code[off], code[off + 1],
                   inst);
        }

        if (note[0]) {
            printf(" ; %s", note);
        }
        printf("\n");
    }
}

static void print_object_header(Object *obj)
{
    printf("; object file\n");
    if (obj->cpu != CPU_ORIGINAL) printf("; cpu %s\n", cpu_name(obj->cpu));
    for (unsigned int i = 0; i < obj->extern_count; i++) {
        printf("extern %s\n", obj->externs[i].name);
    }
    for (unsigned int i = 0; i < obj->entry_count; i++) {
        printf("public %s\n", obj->entries[i].name);
    }
    for (unsigned int i = 0; i < obj->entry_count; i++) {
        if (obj->entries[i].absolute) {
            printf("%s equ $%04X\n", obj->entries[i].name,
                   obj->entries[i].value & 0xffff);
        }
    }
    if (obj->entry_offset != 0xffff &&
            obj->entry_offset >= obj->code_file_offset &&
            obj->entry_offset < obj->code_file_offset + obj->code_len) {
        printf("; entry $%04X\n",
               (origin + obj->entry_offset - obj->code_file_offset) & 0xffff);
    } else {
        printf("; entry none\n");
    }
    printf("\n");
}

static void free_object(Object *obj)
{
    free(obj->entries);
    free(obj->externs);
    free(obj->relocs);
    free(obj->code);
}

static void print_usage(char *prog)
{
    fprintf(stderr,
            "Usage: %s [--cpu original|j11|ucode] [-binary|-object] [-org address] <input.bin|input.obj>\n",
            prog);
}

int main(int argc, char *argv[])
{
    int input_type = INPUT_AUTO;
    char *input_name = NULL;
    unsigned char *buf = NULL;
    size_t size = 0;
    int ret = 1;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            print_usage(argv[0]);
            return 0;
        } else if (!strcmp(argv[i], "--cpu") || !strncmp(argv[i], "--cpu=", 6)) {
            const char *name;
            if (!strcmp(argv[i], "--cpu")) {
                if (++i >= argc) {
                    print_usage(argv[0]);
                    return 1;
                }
                name = argv[i];
            } else {
                name = argv[i] + 6;
            }
            target_cpu = parse_cpu(name);
            cpu_explicit = 1;
            if (target_cpu < 0) {
                fprintf(stderr, "Unknown CPU: %s\n", name);
                return 1;
            }
        } else if (!strcmp(argv[i], "-binary")) {
            input_type = INPUT_BINARY;
        } else if (!strcmp(argv[i], "-object") || !strcmp(argv[i], "-obj")) {
            input_type = INPUT_OBJECT;
        } else if (!strcmp(argv[i], "-org")) {
            if (++i >= argc || parse_number(argv[i], &origin)) {
                print_usage(argv[0]);
                return 1;
            }
        } else if (!input_name) {
            input_name = argv[i];
        } else {
            print_usage(argv[0]);
            return 1;
        }
    }

    if (!input_name) {
        print_usage(argv[0]);
        return 1;
    }

    if (read_file(input_name, &buf, &size)) {
        return 1;
    }

    if (input_type == INPUT_AUTO) {
        input_type = looks_like_object(buf, size) ? INPUT_OBJECT : INPUT_BINARY;
    }

    if (input_type == INPUT_OBJECT) {
        Object obj;

        if (parse_object(buf, size, &obj)) {
            goto done;
        }
        print_object_header(&obj);
        disassemble(obj.code, obj.code_len, &obj);
        free_object(&obj);
    } else {
        disassemble(buf, size, NULL);
    }

    ret = 0;

done:
    free(buf);
    return ret;
}
