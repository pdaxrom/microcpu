#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "cpu_target.h"

enum {
    OUT_MEM = 0,
    OUT_VERILOG,
    OUT_BINARY,
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
    char *path;
    int cpu;
    Symbol *entries;
    unsigned int entry_count;
    Symbol *externs;
    unsigned int extern_count;
    Reloc *relocs;
    unsigned int reloc_count;
    unsigned char *code;
    unsigned int code_len;
    unsigned int code_base;
    unsigned int entry_offset;
    unsigned int code_file_offset;
} Object;

typedef struct Global {
    char name[16];
    unsigned int value;
    struct Global *next;
} Global;

static unsigned char output[65536];
static unsigned int start_addr = 0;
static unsigned int output_addr = 0;
static Global *globals = NULL;

static unsigned int read_u16(unsigned char *buf)
{
    return buf[0] | (buf[1] << 8);
}

static unsigned int read_u32(unsigned char *buf)
{
    return read_u16(buf) | (read_u16(buf + 2) << 16);
}

static void write_u16_mem(unsigned int addr, unsigned int val)
{
    output[addr] = val & 0xff;
    output[addr + 1] = (val >> 8) & 0xff;
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
        fprintf(stderr, "Cannot open object file: %s\n", path);
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

static int parse_object(char *path, Object *obj)
{
    unsigned char *buf;
    size_t size;
    unsigned int ent_count;
    unsigned int ext_count;
    unsigned int code_len;
    unsigned int code_offset;
    unsigned int pos;

    memset(obj, 0, sizeof(*obj));
    obj->path = path;

    if (read_file(path, &buf, &size)) {
        return 1;
    }
    if (size < 0x20 || read_u16(buf) != 0x5aa5 || read_u16(buf + 2) < 1 || read_u16(buf + 2) > 3) {
        fprintf(stderr, "Invalid object file: %s\n", path);
        free(buf);
        return 1;
    }

    ent_count = read_u16(buf + 4);
    ext_count = read_u16(buf + 6);
    code_len = read_u16(buf + 8);
    code_offset = read_u32(buf + 0x0a);

    if (code_offset > size || code_len > size - code_offset ||
            code_offset < 0x20 + (ent_count + ext_count) * 20) {
        fprintf(stderr, "Invalid object layout: %s\n", path);
        free(buf);
        return 1;
    }

    obj->cpu = read_u16(buf + 2) == 1 ? CPU_ORIGINAL : read_u16(buf + 0x10);
    if (!cpu_object_supported(read_u16(buf + 2), obj->cpu)) {
        fprintf(stderr, "Unsupported object version %u for CPU %s in %s; rebuild object\n",
                read_u16(buf + 2), cpu_name(obj->cpu), path);
        free(buf);
        return 1;
    }
    obj->entry_count = ent_count;
    obj->extern_count = ext_count;
    obj->code_len = code_len;
    obj->entry_offset = read_u16(buf + 0x0e);
    obj->code_file_offset = code_offset;

    obj->entries = calloc(ent_count ? ent_count : 1, sizeof(Symbol));
    obj->externs = calloc(ext_count ? ext_count : 1, sizeof(Symbol));
    obj->code = malloc(code_len ? code_len : 1);
    if (!obj->entries || !obj->externs || !obj->code) {
        fprintf(stderr, "Out of memory\n");
        free(buf);
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
        fprintf(stderr, "Missing relocation table: %s\n", path);
        free(buf);
        return 1;
    }

    obj->reloc_count = read_u16(buf + pos);
    pos += 2;
    if (pos + obj->reloc_count * 5 > size) {
        fprintf(stderr, "Invalid relocation table: %s\n", path);
        free(buf);
        return 1;
    }

    obj->relocs = calloc(obj->reloc_count ? obj->reloc_count : 1,
                         sizeof(Reloc));
    if (!obj->relocs) {
        fprintf(stderr, "Out of memory\n");
        free(buf);
        return 1;
    }

    for (unsigned int i = 0; i < obj->reloc_count; i++) {
        unsigned char raw_type = buf[pos++];

        obj->relocs[i].external = (raw_type & 0x80) != 0;
        obj->relocs[i].type = raw_type & 0x7f;
        obj->relocs[i].value = read_u16(buf + pos);
        obj->relocs[i].offset = read_u16(buf + pos + 2);
        pos += 4;
        if (obj->relocs[i].type == 0 || obj->relocs[i].type > RELOC_UADDR12 ||
                (obj->relocs[i].type == RELOC_UADDR12 && obj->cpu != CPU_UCODE) ||
                obj->relocs[i].offset >= code_len ||
                ((obj->relocs[i].type == RELOC_WORD || obj->relocs[i].type == RELOC_UADDR12) &&
                 obj->relocs[i].offset + 1 >= code_len)) {
            fprintf(stderr, "Invalid relocation record: %s\n", path);
            free(buf);
            return 1;
        }
    }

    free(buf);
    return 0;
}

static Global *find_global(char *name)
{
    Global *ptr = globals;

    while (ptr) {
        if (!strcasecmp(ptr->name, name)) {
            return ptr;
        }
        ptr = ptr->next;
    }

    return NULL;
}

static int add_global(char *name, unsigned int value)
{
    Global *item;

    if (find_global(name)) {
        fprintf(stderr, "Duplicate public symbol: %s\n", name);
        return 1;
    }

    item = malloc(sizeof(Global));
    if (!item) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }

    strncpy(item->name, name, sizeof(item->name));
    item->name[sizeof(item->name) - 1] = 0;
    item->value = value;
    item->next = globals;
    globals = item;
    return 0;
}

static int build_globals(Object *objects, int object_count)
{
    for (int i = 0; i < object_count; i++) {
        Object *obj = &objects[i];

        for (unsigned int j = 0; j < obj->entry_count; j++) {
            unsigned int value = obj->entries[j].value;

            if (!obj->entries[j].absolute) {
                value += obj->code_base;
            }
            if (add_global(obj->entries[j].name, value)) {
                return 1;
            }
        }
    }

    return 0;
}

static int count_globals(void)
{
    int count = 0;
    Global *ptr = globals;

    while (ptr) {
        count++;
        ptr = ptr->next;
    }

    return count;
}

static int compare_globals(const void *a, const void *b)
{
    const Global *ga = *(const Global * const *)a;
    const Global *gb = *(const Global * const *)b;

    if (ga->value < gb->value) {
        return -1;
    }
    if (ga->value > gb->value) {
        return 1;
    }
    return strcasecmp(ga->name, gb->name);
}

static int print_symbol_table(void)
{
    int count = count_globals();
    Global **items;
    Global *ptr = globals;

    items = calloc(count ? count : 1, sizeof(Global*));
    if (!items) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }

    for (int i = 0; i < count; i++) {
        items[i] = ptr;
        ptr = ptr->next;
    }
    qsort(items, count, sizeof(Global*), compare_globals);

    printf("Symbols:\n");
    for (int i = 0; i < count; i++) {
        printf("%04X %s\n", items[i]->value & 0xffff, items[i]->name);
    }

    free(items);
    return 0;
}

static int resolve_external(Object *obj, unsigned int index,
                            unsigned int *value)
{
    Global *global;

    if (index >= obj->extern_count) {
        fprintf(stderr, "External symbol index out of range: %s\n", obj->path);
        return 1;
    }

    global = find_global(obj->externs[index].name);
    if (!global) {
        fprintf(stderr, "Unresolved external symbol: %s\n",
                obj->externs[index].name);
        return 1;
    }

    *value = global->value;
    return 0;
}

static int apply_reloc(Object *obj, Reloc *reloc)
{
    unsigned int addr = obj->code_base + reloc->offset;
    unsigned int value = obj->code_base;

    if (reloc->external &&
            resolve_external(obj, reloc->value, &value)) {
        return 1;
    }

    if (reloc->type == RELOC_UADDR12) {
        unsigned int target = (((output[addr] & 15) << 8) | output[addr + 1]) * 2 + value;
        if (target > 8190 || (target & 1)) {
            fprintf(stderr, "Microcode target out of range or odd: %s\n", obj->path);
            return 1;
        }
        output[addr] = (output[addr] & 0xf0) | (target >> 9);
        output[addr + 1] = (target >> 1) & 255;
    } else if (reloc->type == RELOC_WORD) {
        unsigned int word = output[addr] | (output[addr + 1] << 8);

        word = (word + value) & 0xffff;
        write_u16_mem(addr, word);
    } else if (reloc->type == RELOC_LSB) {
        output[addr] = (output[addr] + (value & 0xff)) & 0xff;
    } else if (reloc->type == RELOC_MSB) {
        output[addr] = (output[addr] + ((value >> 8) & 0xff)) & 0xff;
    } else {
        fprintf(stderr, "Unknown relocation type: %s\n", obj->path);
        return 1;
    }

    return 0;
}

static int link_objects(Object *objects, int object_count)
{
    unsigned int addr = start_addr;

    for (int i = 0; i < object_count; i++) {
        if (addr + objects[i].code_len > sizeof(output)) {
            fprintf(stderr, "Output buffer overflow\n");
            return 1;
        }
        objects[i].code_base = addr;
        memcpy(output + addr, objects[i].code, objects[i].code_len);
        addr += objects[i].code_len;
    }
    output_addr = addr;

    if (build_globals(objects, object_count)) {
        return 1;
    }

    for (int i = 0; i < object_count; i++) {
        for (unsigned int j = 0; j < objects[i].reloc_count; j++) {
            if (apply_reloc(&objects[i], &objects[i].relocs[j])) {
                return 1;
            }
        }
    }

    return 0;
}

static void output_hex(FILE *outf)
{
    unsigned int i;

    for (i = start_addr; i < output_addr; i++) {
        if ((i % 16) == 0) {
            fprintf(outf, "%04X:", i);
        }

        fprintf(outf, " %02X", output[i]);

        if ((i % 16) == 15) {
            fprintf(outf, "\n");
        }
    }

    if ((i % 16) != 0) {
        fprintf(outf, "\n");
    }
}

static void output_binary(FILE *outf)
{
    for (unsigned int i = start_addr; i < output_addr; i++) {
        fwrite(&output[i], 1, 1, outf);
    }
}

static void output_verilog(FILE *outf)
{
    fprintf(outf, "module sram(\n"											\
            "    input  [7:0] ADDR,\n"									\
            "    input  [7:0] DI,\n"									\
            "    output [7:0] DO,\n"									\
            "    input        RW,\n"									\
            "    input        CS\n"										\
            ");\n"														\
            "    parameter  AddressSize = 8;\n"							\
            "    reg        [7:0]    Mem[(1 << AddressSize) - 1:0];\n"	\
            "\n"														\
            "    initial begin\n");

    for (unsigned int i = start_addr; i < output_addr; i++) {
        fprintf(outf, "        Mem[%d] = 8'h%02x;\n", i, output[i]);
    }

    fprintf(outf, "    end\n"													\
            "\n"														\
            "    assign DO = RW ? Mem[ADDR] : 8'hFF;\n"					\
            "\n"														\
            "    always @(CS || RW) begin\n"							\
            "        if (~CS && ~RW) begin\n"							\
            "            Mem[ADDR] <= DI;\n"							\
            "        end\n"												\
            "    end\n"													\
            "\n"														\
            "endmodule\n");
}

static char *get_out_name(char *in_str, char *ext)
{
    char *copy = strdup(in_str);
    char *ptr;
    char *str;

    if (!copy) {
        return NULL;
    }

    ptr = strrchr(copy, '.');
    if (ptr) {
        *ptr = 0;
    }

    str = malloc(strlen(copy) + strlen(ext) + 1);
    if (!str) {
        free(copy);
        return NULL;
    }
    strcpy(str, copy);
    strcat(str, ext);
    free(copy);

    return str;
}

static void print_usage(char *prog)
{
    fprintf(stderr,
            "Usage: %s [-verilog|-binary] [-symbols] [-org address] [-o output] "
            "<input.obj>...\n",
            prog);
}

int main(int argc, char *argv[])
{
    int out_type = OUT_MEM;
    char *output_name = NULL;
    char **input_names = NULL;
    int input_count = 0;
    Object *objects;
    int ret = 1;
    int print_symbols = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-verilog")) {
            out_type = OUT_VERILOG;
        } else if (!strcmp(argv[i], "-binary")) {
            out_type = OUT_BINARY;
        } else if (!strcmp(argv[i], "-org")) {
            if (++i >= argc || parse_number(argv[i], &start_addr)) {
                print_usage(argv[0]);
                return 1;
            }
        } else if (!strcmp(argv[i], "-o")) {
            if (++i >= argc) {
                print_usage(argv[0]);
                return 1;
            }
            output_name = argv[i];
        } else if (!strcmp(argv[i], "-symbols") ||
                  !strcmp(argv[i], "--symbols")) {
            print_symbols = 1;
        } else {
            char **new_inputs = realloc(input_names,
                                        sizeof(char*) * (input_count + 1));
            if (!new_inputs) {
                fprintf(stderr, "Out of memory\n");
                free(input_names);
                return 1;
            }
            input_names = new_inputs;
            input_names[input_count++] = argv[i];
        }
    }

    if (input_count == 0) {
        print_usage(argv[0]);
        free(input_names);
        return 1;
    }

    objects = calloc(input_count, sizeof(Object));
    if (!objects) {
        fprintf(stderr, "Out of memory\n");
        free(input_names);
        return 1;
    }

    for (int i = 0; i < input_count; i++) {
        if (parse_object(input_names[i], &objects[i])) {
            goto done;
        }
        if (i && objects[i].cpu != objects[0].cpu) {
            fprintf(stderr, "Cannot link CPU '%s' (%s) with CPU '%s' (%s)\n",
                    cpu_name(objects[i].cpu), input_names[i],
                    cpu_name(objects[0].cpu), input_names[0]);
            goto done;
        }
    }

    if (link_objects(objects, input_count)) {
        goto done;
    }

    if (print_symbols && print_symbol_table()) {
        goto done;
    }

    if (!output_name) {
        output_name = get_out_name(input_names[0],
                                  (out_type == OUT_BINARY) ? ".bin" :
                                  (out_type == OUT_VERILOG) ? ".v" :
                                  ".mem");
    } else {
        output_name = strdup(output_name);
    }
    if (!output_name) {
        fprintf(stderr, "Out of memory\n");
        goto done;
    }

    FILE *outf = fopen(output_name, "wb");
    if (!outf) {
        fprintf(stderr, "Cannot create output file: %s\n", output_name);
        free(output_name);
        goto done;
    }

    if (out_type == OUT_BINARY) {
        output_binary(outf);
    } else if (out_type == OUT_VERILOG) {
        output_verilog(outf);
    } else {
        output_hex(outf);
    }
    fclose(outf);
    free(output_name);
    ret = 0;

done:
    for (int i = 0; i < input_count; i++) {
        free(objects[i].entries);
        free(objects[i].externs);
        free(objects[i].relocs);
        free(objects[i].code);
    }
    free(objects);
    free(input_names);
    return ret;
}
