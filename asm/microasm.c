#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <stdarg.h>
#include "cpu_target.h"

static int target_cpu = CPU_ORIGINAL;

enum {
    NO_ERROR = 0,
    NO_MEMORY_FOR_LABEL,
    CANNOT_RESOLVE_REF,
    NO_MEMORY_FOR_MACRO,
    NO_MEMORY_FOR_PROC,
    INVALID_NUMBER,
    INVALID_HEX_NUMBER,
    INVALID_DECIMAL_NUMBER,
    INVALID_OCTAL_NUMBER,
    INVALID_BINARY_NUMBER,
    MISSED_BRACKET,
    EXPECTED_CLOSE_QUOTE,
    MISSED_OPCODE_PARAM_1,
    LONG_RELATED_OFFSET,
    MISSED_OPCODE_ARG_1,
    EXPECTED_ARG_2,
    MISSED_REGISTER_ARG_2,
    EXPECTED_ARG_3,
    CONSTANT_VALUE_TOO_BIG,
    OUTPUT_BUFFER_OVERFLOW,
    MISSED_NAME_FOR_EQU,
    MISSED_NAME_FOR_PROC,
    NESTED_PROC_UNSUPPORTED,
    ONLY_INSIDE_PROC,
    LABEL_ALREADY_DEFINED,
    MACRO_ALREADY_DEFINED,
    PROC_ALREADY_DEFINED,
    NO_MEMORY_FOR_COND,
    CONDITIONAL_NESTING_TOO_DEEP,
    UNMATCHED_ELSE,
    UNMATCHED_ENDIF,
    DUPLICATE_ELSE,
    UNTERMINATED_IF,
    NO_MEMORY_FOR_RELOC,
    NO_MEMORY_FOR_SYMBOL,
    EXTERN_REDEFINED,
    PUBLIC_NOT_DEFINED,
    ORG_NOT_ALLOWED_IN_OBJECT,
    CHKSUM_NOT_ALLOWED_IN_OBJECT,
    EXTERN_NOT_ALLOWED_HERE,
    INVALID_ENTRY_POINT,
    SYMBOL_NAME_TOO_LONG,
    EXTRA_SYMBOLS,
    SYNTAX_ERROR,
    CANNOT_OPEN_FILE,
    UNSUPPORTED_CPU_OPCODE,
    CPU_MISMATCH,
    INVALID_CONTEXT_INDEX,
    INVALID_LDI8_CONSTANT,
    UNSUPPORTED_PC_DESTINATION,
};

enum {
    op_noargs = 0,
    op_reg_const,
    op_reg_context,
    op_rel,
    op_reg,
    op_reg_reg,
    op_no_reg_reg,
    op_ext_reg_reg,
    op_reg_reg_reg,

    pseudo_db,
    pseudo_dw,
    pseudo_ds,
    pseudo_align,
    pseudo_macro,
    pseudo_equ,
    pseudo_proc,
    pseudo_org,
    pseudo_include,
    pseudo_chksum,
    pseudo_if,
    pseudo_ifdef,
    pseudo_ifndef,
    pseudo_else,
    pseudo_endif,
    pseudo_extern,
    pseudo_public,
    pseudo_entry,
    pseudo_cpu,
};

typedef struct {
    char *name;
    int type;
    int op;
    int ext_op;
    unsigned int cpus;
} OpCode;

static OpCode opcode_table[] = {
    { "ldrl", op_reg_reg_reg, 0x00, 0x0, CPU_ALL },
    { "strl", op_reg_reg_reg, 0x02, 0x0, CPU_ALL },
    { "ldr", op_reg_reg_reg, 0x04, 0x0, CPU_ALL },
    { "str", op_reg_reg_reg, 0x06, 0x0, CPU_ALL },
    { "setl", op_reg_const, 0x08, 0x0, CPU_ALL },
    { "ldi8", op_reg_const, 0x0c, 0x0, CPU_MASK(CPU_UCODE) },
    { "seth", op_reg_const, 0x0a, 0x0, CPU_ALL },
    { "movl", op_reg_reg, 0x0c, 0x0, (CPU_MASK(CPU_ORIGINAL) | CPU_MASK(CPU_J11)) },
    { "movh", op_reg_reg, 0x0e, 0x0, (CPU_MASK(CPU_ORIGINAL) | CPU_MASK(CPU_J11)) },

    { "mov", op_reg_reg, 0x10, 0x0, CPU_ALL },

    { "sws", op_noargs, 0x12, 0x0, CPU_MASK(CPU_ORIGINAL) },
    { "swu", op_noargs, 0x14, 0x0, CPU_MASK(CPU_ORIGINAL) },
    /* J-11 microengine aliases; these opcodes replace SWS/SWU in ucode. */
    { "gget", op_reg_context, 0x12, 0x0, CPU_ENGINES },
    { "gset", op_reg_context, 0x14, 0x0, CPU_ENGINES },
    { "ggetr", op_reg_reg, 0x18, 0x0, CPU_ENGINES },
    { "gsetr", op_reg_reg, 0x1a, 0x0, CPU_ENGINES },
    { "getf", op_reg, 0x1c, 0x0, CPU_ENGINES },

    { "b", op_rel, 0x16, 0x0, CPU_ALL },
    { "setp", op_reg, 0x18, 0x0, CPU_MASK(CPU_ORIGINAL) },
    { "getp", op_reg, 0x1a, 0x0, CPU_MASK(CPU_ORIGINAL) },

    { "eq", op_ext_reg_reg, 0x01, 0x0, CPU_ALL },
    { "ne", op_ext_reg_reg, 0x01, 0x1, CPU_ALL },
    { "mi", op_ext_reg_reg, 0x01, 0x2, CPU_ALL },
    { "vs", op_ext_reg_reg, 0x01, 0x3, CPU_ALL },
    { "lt", op_ext_reg_reg, 0x01, 0x4, CPU_ALL },
    { "ge", op_ext_reg_reg, 0x01, 0x5, CPU_ALL },
    { "ltu", op_ext_reg_reg, 0x01, 0x6, CPU_ALL },
    { "geu", op_ext_reg_reg, 0x01, 0x7, CPU_ALL },

    { "btc", op_ext_reg_reg, 0x03, 0x0, CPU_ALL },
    { "bts", op_ext_reg_reg, 0x03, 0x1, CPU_ALL },

    { "sxt", op_reg_reg, 0x09, 0x0, CPU_ALL },
    { "subb", op_reg_reg_reg, 0x0b, 0x0, CPU_ENGINES },

    { "add", op_reg_reg_reg, 0x11, 0x0, CPU_ALL },
    { "sub", op_reg_reg_reg, 0x13, 0x0, CPU_ALL },
    { "shl", op_reg_reg_reg, 0x15, 0x0, CPU_ALL },
    { "shr", op_reg_reg_reg, 0x17, 0x0, CPU_ALL },
    { "and", op_reg_reg_reg, 0x19, 0x0, CPU_ALL },
    { "or", op_reg_reg_reg, 0x1b, 0x0, CPU_ALL },
    { "inv", op_reg_reg, 0x1d, 0x0, CPU_ALL },
    { "xor", op_reg_reg_reg, 0x1f, 0x0, CPU_ALL },

    /* pseudo ops */
    { "db", pseudo_db, 0x0, 0x0, CPU_ALL },
    { "dw", pseudo_dw, 0x0, 0x0, CPU_ALL },
    { "ds", pseudo_ds, 0x0, 0x0, CPU_ALL },
    { "align", pseudo_align, 0x0, 0x0, CPU_ALL },
    { "macro", pseudo_macro, 0x0, 0x0, CPU_ALL },
    { "endm", pseudo_macro, 0x0, 0x0, CPU_ALL },
    { "equ", pseudo_equ, 0x0, 0x0, CPU_ALL },
    { "proc", pseudo_proc, 0x0, 0x0, CPU_ALL },
    { "endp", pseudo_proc, 0x0, 0x0, CPU_ALL },
    { "global",pseudo_proc, 0x0, 0x0, CPU_ALL },
    { "org", pseudo_org, 0x0, 0x0, CPU_ALL },
    { "include", pseudo_include, 0x0, 0x0, CPU_ALL },
    { "chksum", pseudo_chksum, 0x0, 0x0, CPU_ALL },
    { "if", pseudo_if, 0x0, 0x0, CPU_ALL },
    { "ifdef", pseudo_ifdef, 0x0, 0x0, CPU_ALL },
    { "ifndef", pseudo_ifndef, 0x0, 0x0, CPU_ALL },
    { "else", pseudo_else, 0x0, 0x0, CPU_ALL },
    { "endif", pseudo_endif, 0x0, 0x0, CPU_ALL },
    { "extern", pseudo_extern, 0x0, 0x0, CPU_ALL },
    { "public", pseudo_public, 0x0, 0x0, CPU_ALL },
    { "entry", pseudo_entry, 0x0, 0x0, CPU_ALL },
    { "cpu", pseudo_cpu, 0x0, 0x0, CPU_ALL },
};

typedef struct Register {
    char *name;
    int n;
} Register;

static Register regs_table[] = {
    { "r0",  0 },
    { "r1",  1 },
    { "r2",  2 },
    { "r3",  3 },
    { "r4",  4 },
    { "r5",  5 },
    { "r6",  6 },
    { "r7",  7 },
    { "pc",  0 },
    { "sp",  1 },
    { "lr",  2 },
    { "v0",  3 },
    { "v1",  4 },
    { "v2",  5 },
    { "v3",  6 },
    { "v4",  7 },
};

typedef struct Macro {
    char *name;
    char **line;
    int lines;
    int args;
    struct Macro *prev;
} Macro;

typedef struct Label {
    char *name;
    unsigned int address;
    int line;
    int resolved;
    int external;
    int absolute;
    struct Label *prev;
} Label;

typedef struct Reloc {
    unsigned char type;
    unsigned int offset;
    char *name;
    int external;
    struct Reloc *next;
} Reloc;

typedef struct CondRecord {
    int condition_true;
    int line;
    struct CondRecord *next;
} CondRecord;

typedef struct CondFrame {
    int parent_active;
    int condition_true;
    int active;
    int else_seen;
    int line;
} CondFrame;

typedef struct Proc {
    char *name;
    Label *labels;
    Label *globals;
    Label *equs;
    int line;
    struct Proc *prev;
} Proc;

typedef struct File {
    char *in_file_path;
    FILE *in_file;
    int src_line;
    struct File *prev;
} File;

static char *in_file_path;
static FILE *in_file;

static unsigned char output[65536];
static unsigned int start_addr = 0;
static unsigned int output_addr = 0;

static int use_chksum = 0;
static unsigned int chksum_addr;

static int src_pass = 1;
static int src_line = 1;
static FILE *listing_file = NULL;
static int listing_file_owned = 0;

static Label *labels = NULL;
static Label *equs = NULL;
static Label *refs = NULL;
static Label *externs = NULL;
static Label *publics = NULL;
static Proc *procs = NULL;
static Macro *macros = NULL;
static File *files = NULL;
static Reloc *relocs = NULL;
static Reloc *relocs_tail = NULL;

static int error = 0;
static int to_second_pass = 0;

static int in_macro = 0;
static Proc *in_proc = NULL;
static int out_type = 0;
static int has_entry = 0;
static unsigned int entry_addr = 0;
static Label *expr_reloc_label = NULL;
static int expr_reloc_count = 0;
static int expr_high_byte = 0;

#define OUT_MEM 0
#define OUT_VERILOG 1
#define OUT_BINARY 2
#define OUT_OBJECT 3

#define RELOC_LSB 0x01
#define RELOC_MSB 0x02
#define RELOC_WORD 0x03

#define COND_NESTING_LIMIT 32

static CondFrame cond_stack[COND_NESTING_LIMIT];
static int cond_depth = 0;
static CondRecord *cond_records = NULL;
static CondRecord *cond_records_tail = NULL;
static CondRecord *cond_replay = NULL;

#define SKIP_BLANK(s) { \
    while (*(s) && isblank(*(s))) { \
	(s)++; \
    } \
}

#define SKIP_TOKEN(s) { \
    if (isalpha(*(s)) || *(s) == '_' || *(s) == ':' || *(s) == '.') { \
	(s)++; \
	while (*(s) && (isalnum(*(s)) || *(s) == '_')) { \
	    (s)++; \
	} \
    } \
}

#define REMOVE_ENDLINE(s) { \
    while (*(s)) { \
	if (*(s) == '\n' || *(s) == '\r') *(s) = 0; \
	(s)++; \
    } \
}

#define STRING_TOLOWER(s) { \
    while (*(s)) { \
	*(s) = tolower(*(s)); \
	(s)++; \
    } \
}

static FILE *get_listing_file(void)
{
    return listing_file;
}

static void listing_vprintf(const char *fmt, va_list ap)
{
    FILE *out = get_listing_file();

    if (out) {
        vfprintf(out, fmt, ap);
    }
}

static void listing_printf(const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    listing_vprintf(fmt, ap);
    va_end(ap);
}

static void status_printf(const char *fmt, ...)
{
    va_list ap;
    va_list listing_ap;
    FILE *out = get_listing_file();

    va_start(ap, fmt);
    va_copy(listing_ap, ap);
    vfprintf(stdout, fmt, ap);
    fflush(stdout);
    if (out && out != stdout) {
        vfprintf(out, fmt, listing_ap);
        fflush(out);
    }
    va_end(listing_ap);
    va_end(ap);
}

static void remove_comment(char *str)
{
    int q = 0, dq = 0;
    while (*str) {
        if (*str == '\'') {
            q = !q;
        }
        if (*str == '"') {
            dq = !dq;
        }

        if (*str == ';' && (q == 0 || dq == 0)) {
            *str = 0;
            break;
        }

        if (*str == '/' && *(str + 1) && *(str + 1) == '/'
                && (q == 0 || dq == 0)) {
            *str = 0;
            break;
        }
        str++;
    }
}

static int exp_(char **str);

static Label* find_label(Label **list, char *name)
{
    Label *ptr = *list;

    while (ptr) {
        if (!strcasecmp(ptr->name, name)) {
            return ptr;
        }
        ptr = ptr->prev;
    }

    return NULL;
}

static Label* add_label_ex(Label **list, char *name, unsigned int address,
                           int line, int resolved)
{
    if (find_label(list, name)) {
        error = LABEL_ALREADY_DEFINED;
        return NULL;
    }

    Label *new = malloc(sizeof(Label));
    if (!new) {
        error = NO_MEMORY_FOR_LABEL;
        return NULL;
    }
    new->name = strdup(name);
    if (!new->name) {
        free(new);
        error = NO_MEMORY_FOR_LABEL;
        return NULL;
    }
    new->address = address;
    new->line = line;
    new->resolved = resolved;
    new->external = 0;
    new->absolute = 0;
    new->prev = *list;

    *list = new;

    return new;
}

static Label* add_label(Label **list, char *name, unsigned int address,
                        int line)
{
    return add_label_ex(list, name, address, line, 1);
}

static Label* set_label(Label **list, char *name, unsigned int address,
                        int line, int resolved)
{
    Label *label = find_label(list, name);

    if (label) {
        label->address = address;
        label->line = line;
        label->resolved = resolved;
        return label;
    }

    return add_label_ex(list, name, address, line, resolved);
}

static void delete_label(Label **list, char *name)
{
    Label *ptr = *list;
    Label *prev = NULL;

    while (ptr) {
        if (!strcasecmp(ptr->name, name)) {
            if (prev) {
                prev->prev = ptr->prev;
            } else {
                *list = ptr->prev;
            }
            free(ptr->name);
            free(ptr);
            return;
        }
        prev = ptr;
        ptr = ptr->prev;
    }
}

static Label* find_any_symbol(char *name)
{
    Label *label = NULL;

    if (in_proc) {
        label = find_label(&in_proc->labels, name);

        if (!label) {
            label = find_label(&in_proc->equs, name);
        }
    }

    if (!label) {
        label = find_label(&labels, name);
    }

    if (!label) {
        label = find_label(&equs, name);
    }

    if (!label) {
        label = find_label(&externs, name);
    }

    return label;
}

static int count_labels(Label *list)
{
    int count = 0;

    while (list) {
        count++;
        list = list->prev;
    }

    return count;
}

static int label_index(Label *list, char *name)
{
    int index = 0;

    while (list) {
        if (!strcasecmp(list->name, name)) {
            return index;
        }
        index++;
        list = list->prev;
    }

    return -1;
}

static void reset_expr_reloc(void)
{
    expr_reloc_label = NULL;
    expr_reloc_count = 0;
    expr_high_byte = 0;
}

static void note_expr_reloc(Label *label)
{
    if (out_type != OUT_OBJECT || label->absolute) {
        return;
    }

    if (expr_reloc_label && expr_reloc_label != label) {
        error = SYNTAX_ERROR;
        return;
    }

    expr_reloc_label = label;
    expr_reloc_count++;
}

static int check_expr_reloc(void)
{
    if (expr_reloc_count > 1) {
        error = SYNTAX_ERROR;
        return 1;
    }

    return 0;
}

static int add_reloc(unsigned char type, unsigned int offset, Label *label)
{
    Reloc *record;

    if (out_type != OUT_OBJECT || !label || label->absolute) {
        return 0;
    }

    record = malloc(sizeof(Reloc));
    if (!record) {
        error = NO_MEMORY_FOR_RELOC;
        return 1;
    }

    record->type = type;
    record->offset = offset - start_addr;
    record->name = strdup(label->name);
    if (!record->name) {
        free(record);
        error = NO_MEMORY_FOR_RELOC;
        return 1;
    }
    record->external = label->external;
    record->next = NULL;

    if (relocs_tail) {
        relocs_tail->next = record;
    } else {
        relocs = record;
    }
    relocs_tail = record;

    return 0;
}

static void dump_labels(Label *list)
{
    while (list) {
        listing_printf("[%s] %04X\n", list->name, list->address);
        list = list->prev;
    }
}

static int relink_refs(void)
{
    Label *tmp = refs;

    while (tmp) {
        char *ptr = tmp->name;
        reset_expr_reloc();
        int val = exp_(&ptr);
        if (error == 0 && to_second_pass == 0) {
            output[tmp->address] = val;
        } else {
            status_printf("Can't resolve %s in %s line %d\n", tmp->name, ptr,
                          tmp->line);
            error = CANNOT_RESOLVE_REF;
            return 1;
        }
        tmp = tmp->prev;
    }

    return 0;
}

static OpCode* find_opcode(char *name)
{
    for (int i = 0; i < sizeof(opcode_table) / sizeof(OpCode); i++) {
        if (!strcasecmp(name, opcode_table[i].name)) {
            return &opcode_table[i];
        }
    }

    return NULL;
}

static Register* find_register(char *name)
{
    for (int i = 0; i < sizeof(regs_table) / sizeof(Register); i++) {
        if (!strcasecmp(name, regs_table[i].name)) {
            return &regs_table[i];
        }
    }

    return NULL;
}

static Register* find_register_in_string(char **str)
{
    char tmp[256];
    char *ptr = tmp;
    char *ptr_str = *str;

    SKIP_BLANK(ptr_str);

    while(*ptr_str && isalnum(*ptr_str)) {
        if (ptr - tmp >= 255) {
            break;
        }
        *ptr++ = *ptr_str++;
    }

    *ptr = 0;

    Register *reg = find_register(tmp);

    if (reg) {
        *str = ptr_str;
    }

    return reg;
}

static Macro* find_macro(char *name)
{
    Macro *tmp = macros;
    while (tmp) {
        if (!strcasecmp(tmp->name, name)) {
            return tmp;
        }
        tmp = tmp->prev;
    }
    return NULL;
}

#define LISTING_BYTES_WIDTH 8
#define LISTING_MACRO_WIDTH 12
#define LISTING_LABEL_WIDTH 20
#define LISTING_OPCODE_WIDTH 8

static char *listing_macro_name = NULL;
static int listing_macro_line = 0;

static void print_listing_source(char *line)
{
    char copy[strlen(line ? line : "") + 1];
    char *ptr;
    char *tok1;
    char *tok2;
    char *rest;
    char *label = "";
    char *opcode = "";
    int first_is_opcode;

    if (!line) {
        return;
    }

    strcpy(copy, line);
    ptr = copy;
    SKIP_BLANK(ptr);

    if (!*ptr || *ptr == ';') {
        listing_printf("%s", ptr);
        return;
    }

    tok1 = ptr;
    SKIP_TOKEN(ptr);
    if (ptr == tok1) {
        listing_printf("%s", tok1);
        return;
    }

    if (*ptr) {
        *ptr++ = 0;
    }
    rest = ptr;
    SKIP_BLANK(rest);

    first_is_opcode = (tok1 != copy) || find_opcode(tok1) || find_macro(tok1);
    if (first_is_opcode) {
        opcode = tok1;
    } else {
        label = tok1;
        if (*rest && *rest != ';') {
            tok2 = rest;
            SKIP_TOKEN(rest);
            if (rest != tok2) {
                opcode = tok2;
                if (*rest) {
                    *rest++ = 0;
                }
                SKIP_BLANK(rest);
            }
        }
    }

    listing_printf("%-*s %-*s %s", LISTING_LABEL_WIDTH, label,
                   LISTING_OPCODE_WIDTH, opcode, rest);
}

static void print_listing(unsigned int addr, char *bytes, char *line)
{
    char macro[64] = "";

    if (src_pass != 2) {
        return;
    }

    if (listing_macro_name) {
        snprintf(macro, sizeof(macro), "[%s]:%d", listing_macro_name,
                 listing_macro_line);
    }

    listing_printf("%04X: %-*s %-*s ", addr & 0xffff,
                   LISTING_BYTES_WIDTH, bytes ? bytes : "",
                   LISTING_MACRO_WIDTH, macro);
    print_listing_source(line);
    listing_printf("\n");
}

static void print_listing_line_at(unsigned int addr, char *line)
{
    print_listing(addr, NULL, line);
}

static void print_listing_line(char *line)
{
    print_listing_line_at(output_addr, line);
}

static void print_listing_word(unsigned int addr, unsigned int word, char *line)
{
    char bytes[LISTING_BYTES_WIDTH + 1];

    snprintf(bytes, sizeof(bytes), "%04X", word & 0xffff);
    print_listing(addr, bytes, line);
}

static void print_listing_insn(unsigned int addr, unsigned int lo,
                               unsigned int hi, char *line)
{
    char bytes[LISTING_BYTES_WIDTH + 1];

    snprintf(bytes, sizeof(bytes), "%02X%02X", lo & 0xff, hi & 0xff);
    print_listing(addr, bytes, line);
}

static void print_listing_data(unsigned int addr, char *bytes)
{
    if (src_pass == 2) {
        listing_printf("%04X: %s\n", addr & 0xffff, bytes);
    }
}

static int add_macro(FILE *inf, char *name)
{
    char str[512];
    Macro *mac;

    if (src_pass == 1) {
        if (find_macro(name)) {
            error = MACRO_ALREADY_DEFINED;
            return 1;
        }

        mac = malloc(sizeof(Macro));
        if (!mac) {
            error = NO_MEMORY_FOR_MACRO;
            return 1;
        }

        mac->name = strdup(name);
        if (!mac->name) {
            free(mac);
            error = NO_MEMORY_FOR_MACRO;
            return 1;
        }
        mac->line = NULL;
        mac->lines = 0;
        mac->prev = macros;
    }

    while(fgets(str, sizeof(str), inf)) {
        char tmp[512];
        char *ptr = str;
        REMOVE_ENDLINE(ptr);

        print_listing_line(str);

        strcpy(tmp, str);
        ptr = tmp;
        SKIP_BLANK(ptr);
        char *ptr1 = ptr;
        REMOVE_ENDLINE(ptr1);
        ptr1 = ptr;
        SKIP_TOKEN(ptr1);
        *ptr1 = 0;
        ptr1 = ptr;
        if (!strcasecmp(ptr, "endm")) {
            break;
        }

        if (src_pass == 1) {
            char **new_line = realloc(mac->line, sizeof(char*) * (mac->lines + 1));
            if (!new_line) {
                error = NO_MEMORY_FOR_MACRO;
                return 1;
            }
            mac->line = new_line;
            mac->line[mac->lines] = strdup(str);
            if (!mac->line[mac->lines]) {
                for (int i = 0; i < mac->lines; i++) {
                    free(mac->line[i]);
                }
                free(mac->line);
                free(mac->name);
                free(mac);
                error = NO_MEMORY_FOR_MACRO;
                return 1;
            }
            mac->lines++;
        }

        src_line++;
    }

    src_line += 2;

    if (src_pass == 1) {
        macros = mac;
    }

    return 0;
}

static Proc* find_proc(Proc **list, char *name)
{
    Proc *ptr = *list;

    while (ptr) {
        if (!strcasecmp(ptr->name, name)) {
            return ptr;
        }
        ptr = ptr->prev;
    }

    return NULL;
}

static Proc* add_proc(Proc **list, char *name, int line)
{
    if (find_proc(list, name)) {
        error = PROC_ALREADY_DEFINED;
        return NULL;
    }

    Proc *new = malloc(sizeof(Proc));
    if (!new) {
        error = NO_MEMORY_FOR_PROC;
        return NULL;
    }
    new->name = strdup(name);
    if (!new->name) {
        free(new);
        error = NO_MEMORY_FOR_PROC;
        return NULL;
    }
    new->labels = NULL;
    new->globals = NULL;
    new->equs = NULL;
    new->line = line;
    new->prev = *list;

    *list = new;

    return new;
}

static int match(char **str, char c)
{
    SKIP_BLANK(*str);

    if (*(*str) != c) {
        return 0;
    }

    (*str)++;
    return 1;
}

static int exp2_(char **str);

static int toint(char c)
{
    if (isdigit(c)) {
        return (c - '0');
    } else if (isxdigit(c)) {
        if (isupper(c)) {
            return (c - 'A' + 10);
        } else {
            return (c - 'a' + 10);
        }
    } else {
        error = INVALID_NUMBER;
        return 0;
    }
}

static int hexnum(char **str)
{
    int n;

    if (!isxdigit(*(*str))) {
        error = INVALID_HEX_NUMBER;
        return 0;
    } else {
        n = 0;
        while (isxdigit(*(*str))) {
            n = n * 16 + toint(*(*str)++);
        }
        return n;
    }
}

static int decimal(char **str)
{
    int n;

    if (isdigit(*(*str)) == 0) {
        error = INVALID_DECIMAL_NUMBER;
        return 0;
    } else {
        n = 0;
        while (isdigit(*(*str))) {
            n = n * 10 + *(*str)++ - '0';
        }
        return n;
    }
}

static int octal(char **str)
{
    int n;

    if (*(*str) < '0' || *(*str) > '7') {
        error = INVALID_OCTAL_NUMBER;
        return 0;
    } else {
        n = 0;
        while (*(*str) >= '0' && *(*str) <= '7') {
            n = n * 8 + *(*str)++ - '0';
        }
        return n;
    }
}

static int binary(char **str)
{
    int n;

    if (*(*str) != '0' && *(*str) != '1') {
        error = INVALID_BINARY_NUMBER;
        return 0;
    } else {
        n = 0;
        while (*(*str) == '0' || *(*str) == '1' || *(*str) == '_') {
            if (*(*str) == '_') {
                (*str)++;
            } else {
                n = n * 2 + *(*str)++ - '0';
            }
        }
        return n;
    }
}

static int character(char **str)
{
    char c;

    c = *(*str)++;
    if (*(*str) == '\'') {
        (*str)++;
    }
    return c;
}

static int operand(char **str)
{
    char *ptr = *str;
    char tmp[256];
    char *ptr1 = tmp;

    while (*ptr && (isalnum(*ptr) || *ptr == '_' || *ptr == ':' || *ptr == '.')) {
        if (ptr1 - tmp >= 255) {
            error = SYNTAX_ERROR;
            return 0;
        }
        *ptr1++ = *ptr++;
    }
    *ptr1 = 0;

    Label *label = find_any_symbol(tmp);

    if (label) {
        *str = ptr;
        if (label->external) {
            if (out_type != OUT_OBJECT) {
                error = CANNOT_RESOLVE_REF;
                return 0;
            }
            note_expr_reloc(label);
            return 0;
        }
        if (!label->resolved) {
            if (src_pass == 2) {
                error = CANNOT_RESOLVE_REF;
            } else {
                to_second_pass = 1;
            }
            return 0;
        }
        note_expr_reloc(label);
        return label->address;
    } else if (match(str, '$')) {
        return hexnum(str);
    } else if (match(str, '@')) {
        return octal(str);
    } else if (match(str, '%')) {
        return binary(str);
    } else if (match(str, '\'')) {
        return character(str);
    } else if (match(str, '*')) {
        return output_addr;
    } else if (isdigit(*(*str))) {
        return decimal(str);
    } else {
        *str = ptr;
        if (src_pass == 2) {
            error = CANNOT_RESOLVE_REF;
        } else {
            to_second_pass = 1;
        }
        return 0;
    }
}

static int exp8(char **str)
{
    int n;
    if (match(str, '(')) {
        n = exp2_(str);
        if (match(str, ')')) {
            return n;
        } else {
            error = MISSED_BRACKET;
            return 0;
        }
    }
    return operand(str);
}

static int exp7(char **str)
{
    if (match(str, '~')) {
        return 0xFFFF ^ exp8(str);
    }
    if (match(str, '-')) {
        return -exp8(str);
    }
    return exp8(str);
}

static int exp6(char **str)
{
    int n;
    n = exp7(str);
    while (*(*str)) {
        if (match(str, '*')) {
            n = n * exp7(str);
        } else if (match(str, '/')) {
            int divisor = exp7(str);
            if (divisor == 0) {
                error = SYNTAX_ERROR;
                return 0;
            }
            n = n / divisor;
        } else if (match(str, '%')) {
            int divisor = exp7(str);
            if (divisor == 0) {
                error = SYNTAX_ERROR;
                return 0;
            }
            n = n % divisor;
        } else {
            break;
        }
    }
    return n;
}

static int exp5(char **str)
{
    int n;
    n = exp6(str);
    while (*(*str)) {
        if (match(str, '+')) {
            n = n + exp6(str);
        } else if (match(str, '-')) {
            n = n - exp6(str);
        } else {
            break;
        }
    }
    return n;
}

static int exp4(char **str)
{
    int n;
    n = exp5(str);
    while (*(*str)) {
        if (match(str, '&')) {
            n = n & exp5(str);
        } else {
            break;
        }
    }
    return n;
}

static int exp3(char **str)
{
    int n;
    n = exp4(str);
    while (*(*str)) {
        if (match(str, '^')) {
            n = n ^ exp4(str);
        } else {
            break;
        }
    }
    return n;
}

static int exp2_(char **str)
{
    int n;
    n = exp3(str);
    while (*(*str)) {
        if (match(str, '|')) {
            n = n | exp3(str);
        } else {
            break;
        }
    }
    return n;
}

static int exp_(char **str)
{
    if (match(str, '/')) {
        expr_high_byte = 1;
        return (exp2_(str) >> 8);
    } else {
        return (exp2_(str));
    }
}

static int get_bytes(char *str)
{
    char delim = 0;
    int nbytes = 0;
    int linesize = strlen(str);
    int old_addr = output_addr;

    SKIP_BLANK(str);
    while (nbytes < linesize) {
        if (delim) {
            if (*str == 0 || *str == '\n' || *str == '\r') {
                break;
            }
            if (*str != delim) {
                if (output_addr >= 65536) {
                    error = OUTPUT_BUFFER_OVERFLOW;
                    return 0;
                }
                output[output_addr++] = *str++;
                continue;
            }
            delim = 0;
            str++;
        } else if (*str == '"' || *str == '\'') {
            delim = *str++;
            continue;
        } else {
            char *tmp = str;
            unsigned int reloc_offset = output_addr;
            if (output_addr >= 65536) {
                error = OUTPUT_BUFFER_OVERFLOW;
                return 0;
            }
            reset_expr_reloc();
            output[output_addr++] = exp_(&str) & 0xFF;
            if (check_expr_reloc()) {
                return 0;
            }
            if (src_pass == 2 && expr_reloc_label) {
                add_reloc(expr_high_byte ? RELOC_MSB : RELOC_LSB,
                          reloc_offset, expr_reloc_label);
            }

            if (to_second_pass && src_pass == 2) {
                int len = str - tmp;
                if (len > 255) {
                    len = 255;
                }
                char tmp1[256];
                strncpy(tmp1, tmp, len);
                tmp1[len] = 0;
                char *p = tmp1;
                while (*p && !isblank(*p) && *p != ',') {
                    p++;
                }
                *p = 0;
                add_label(&refs, tmp1, output_addr - 1, src_line);
            }
            to_second_pass = 0;
        }
        if (match(&str, ',') == 0) {
            break;
        }
        SKIP_BLANK(str);
    }
    if (delim) {
        error = EXPECTED_CLOSE_QUOTE;
    }

    return output_addr - old_addr;
}

static int get_words(char *str)
{
    int word;
    int nbytes = 0;
    int linesize = strlen(str);
    int old_addr = output_addr;

    while (nbytes < linesize) {
        char *tmp = str;
        unsigned int reloc_offset = output_addr;
        reset_expr_reloc();
        word = exp_(&str);
        if (check_expr_reloc()) {
            return 0;
        }

        if (src_pass == 2 && expr_reloc_label) {
            add_reloc(RELOC_WORD, reloc_offset, expr_reloc_label);
        }

        if (to_second_pass && src_pass == 2) {
            char tmp1[strlen(tmp) + 1];
            strcpy(tmp1, tmp);
            tmp = tmp1;
            while (*tmp && !isblank(*tmp) && *tmp != ',') {
                tmp++;
            }
            *tmp = 0;
            add_label(&refs, tmp1, output_addr, src_line);
        }
        to_second_pass = 0;

        output[output_addr++] = word & 0xFF;
        output[output_addr++] = word >> 8;
        if (match(&str, ',') == 0) {
            break;
        }

    }

    return output_addr - old_addr;
}

static int do_asm(FILE *inf, char *str);

static int expand_macro(FILE *inf, Macro *mac, char *args)
{
    int i = 0;
    char *arg[10];

    src_line++;

    in_macro++;

    // parse args
    while (args && *args) {
        SKIP_BLANK(args);
        arg[i++] = args;
        while (*args && *args != ',') {
            args++;
        }

        if (*args == ',') {
            *args++ = 0;
            continue;
        }
    }

    arg[i] = NULL;

//	for (i = 0; arg[i]; i++) {
//	    fprintf(stderr, "[%s]\n", arg[i]);
//	}

    for (i = 0; i < mac->lines; i++) {
        char line[1024];
        char *ptr_tmp;
        char *ptr_src = mac->line[i];
        char *ptr_dst = line;

        if (!strchr(ptr_src, '#')) {
            strcpy(line, ptr_src);
        } else {
            while ((ptr_tmp = strchr(ptr_src, '#'))) {
                if (isdigit(*(ptr_tmp + 1))) {
                    int len = (ptr_tmp - ptr_src);
                    int n = *(ptr_tmp + 1) - '0' - 1;

                    strncpy(ptr_dst, ptr_src, len);
                    strcpy(ptr_dst + len, arg[n]);
                    ptr_dst += strlen(ptr_dst);
                    ptr_src = ptr_tmp + 2;
                } else {
                    break;
                }
            }
            if (*ptr_src) {
                strcpy(ptr_dst, ptr_src);
            }
        }

        char *saved_macro_name = listing_macro_name;
        int saved_macro_line = listing_macro_line;
        listing_macro_name = mac->name;
        listing_macro_line = i + 1;
        int ret = do_asm(inf, line);
        listing_macro_name = saved_macro_name;
        listing_macro_line = saved_macro_line;
        if (ret) {
            if (src_pass == 1) {
                status_printf("[%s]:%d %s\n", mac->name, i + 1, line);
            }
            return ret;
        }
    }

    in_macro--;

    return 0;
}

static char *get_file_path(char *name)
{
    char *tmp;
    if ((tmp = strrchr(name, '/'))) {
        *tmp = 0;
    } else {
        strcpy(name, ".");
    }
    return name;
}

static void restore_root_file(void)
{
    while (files) {
        File *tmp;

        fclose(in_file);
        in_file = files->in_file;
        in_file_path = files->in_file_path;
        src_line = files->src_line;
        tmp = files->prev;
        free(files);
        files = tmp;
    }
}

static int is_conditional_opcode(OpCode *opcode)
{
    return opcode &&
           (opcode->type == pseudo_if ||
            opcode->type == pseudo_ifdef ||
            opcode->type == pseudo_ifndef ||
            opcode->type == pseudo_else ||
            opcode->type == pseudo_endif);
}

static int cond_current_active(void)
{
    if (cond_depth == 0) {
        return 1;
    }
    return cond_stack[cond_depth - 1].active;
}

static int add_cond_record(int condition_true)
{
    CondRecord *record = malloc(sizeof(CondRecord));
    if (!record) {
        error = NO_MEMORY_FOR_COND;
        return 1;
    }

    record->condition_true = condition_true;
    record->line = src_line;
    record->next = NULL;

    if (cond_records_tail) {
        cond_records_tail->next = record;
    } else {
        cond_records = record;
    }

    cond_records_tail = record;
    return 0;
}

static int parse_symbol_arg(char **str, char *name, size_t name_size)
{
    char *start;
    size_t len;

    SKIP_BLANK(*str);
    start = *str;
    SKIP_TOKEN(*str);
    len = *str - start;

    if (len == 0 || len >= name_size) {
        error = SYNTAX_ERROR;
        return 1;
    }

    memcpy(name, start, len);
    name[len] = 0;

    SKIP_BLANK(*str);
    if (**str) {
        error = EXTRA_SYMBOLS;
        return 1;
    }

    return 0;
}

static int symbol_defined(char *name)
{
    if (in_proc) {
        if (find_label(&in_proc->labels, name) ||
                find_label(&in_proc->equs, name)) {
            return 1;
        }
    }

    return find_label(&labels, name) ||
           find_label(&equs, name) ||
           find_label(&externs, name) ||
           find_proc(&procs, name) ||
           find_macro(name);
}

static int eval_if_condition(char *str, int parent_active,
                             int *condition_true)
{
    int val;

    *condition_true = 0;
    if (!parent_active) {
        return 0;
    }

    SKIP_BLANK(str);
    if (!*str) {
        error = SYNTAX_ERROR;
        return 1;
    }

    to_second_pass = 0;
    reset_expr_reloc();
    val = exp_(&str);
    if (error != NO_ERROR) {
        to_second_pass = 0;
        return 1;
    }
    if (to_second_pass) {
        to_second_pass = 0;
        error = CANNOT_RESOLVE_REF;
        return 1;
    }

    SKIP_BLANK(str);
    if (*str) {
        error = EXTRA_SYMBOLS;
        return 1;
    }

    *condition_true = val != 0;
    return 0;
}

static int eval_ifdef_condition(char *str, int parent_active, int invert,
                                int *condition_true)
{
    char name[256];

    *condition_true = 0;
    if (!parent_active) {
        return 0;
    }

    if (parse_symbol_arg(&str, name, sizeof(name))) {
        return 1;
    }

    *condition_true = symbol_defined(name);
    if (invert) {
        *condition_true = !*condition_true;
    }

    return 0;
}

static int push_condition(int parent_active, int condition_true)
{
    if (cond_depth >= COND_NESTING_LIMIT) {
        error = CONDITIONAL_NESTING_TOO_DEEP;
        return 1;
    }

    cond_stack[cond_depth].parent_active = parent_active;
    cond_stack[cond_depth].condition_true = condition_true;
    cond_stack[cond_depth].active = parent_active && condition_true;
    cond_stack[cond_depth].else_seen = 0;
    cond_stack[cond_depth].line = src_line;
    cond_depth++;

    return 0;
}

static void finish_asm_line(void)
{
    if (src_pass == 1) {
        status_printf("Line: %d\r", src_line);
    }

    if (!in_macro) {
        src_line++;
    }
}

static int handle_conditional_directive(OpCode *opcode, char *str, char *line)
{
    int parent_active;
    int condition_true = 0;

    if (opcode->type == pseudo_if ||
            opcode->type == pseudo_ifdef ||
            opcode->type == pseudo_ifndef) {
        parent_active = cond_current_active();

        if (src_pass == 1) {
            if (opcode->type == pseudo_if) {
                if (eval_if_condition(str, parent_active, &condition_true)) {
                    return 1;
                }
            } else {
                if (eval_ifdef_condition(str, parent_active,
                                         opcode->type == pseudo_ifndef,
                                         &condition_true)) {
                    return 1;
                }
            }

            if (add_cond_record(condition_true)) {
                return 1;
            }
        } else {
            if (!cond_replay) {
                error = SYNTAX_ERROR;
                return 1;
            }
            condition_true = cond_replay->condition_true;
            cond_replay = cond_replay->next;
        }

        if (push_condition(parent_active, condition_true)) {
            return 1;
        }

        print_listing_line(line);
        finish_asm_line();
        return 0;
    }

    SKIP_BLANK(str);
    if (*str) {
        error = EXTRA_SYMBOLS;
        return 1;
    }

    if (opcode->type == pseudo_else) {
        if (cond_depth == 0) {
            error = UNMATCHED_ELSE;
            return 1;
        }
        if (cond_stack[cond_depth - 1].else_seen) {
            error = DUPLICATE_ELSE;
            return 1;
        }

        cond_stack[cond_depth - 1].else_seen = 1;
        cond_stack[cond_depth - 1].active =
            cond_stack[cond_depth - 1].parent_active &&
            !cond_stack[cond_depth - 1].condition_true;
    } else if (opcode->type == pseudo_endif) {
        if (cond_depth == 0) {
            error = UNMATCHED_ENDIF;
            return 1;
        }
        cond_depth--;
    }

    print_listing_line(line);
    finish_asm_line();
    return 0;
}

static int parse_symbol_list(char *str, int (*handler)(char *name))
{
    int got_name = 0;

    do {
        char *name;
        char last;

        SKIP_BLANK(str);
        name = str;
        SKIP_TOKEN(str);
        if (str == name) {
            error = SYNTAX_ERROR;
            return 1;
        }

        last = *str;
        if (last) {
            *str++ = 0;
        }

        if (handler(name)) {
            return 1;
        }
        got_name = 1;

        if (!last) {
            break;
        }
        if (last != ',') {
            SKIP_BLANK(str);
            if (*str) {
                error = EXTRA_SYMBOLS;
                return 1;
            }
            break;
        }
    } while (*str);

    if (!got_name) {
        error = SYNTAX_ERROR;
        return 1;
    }

    return 0;
}

static int add_extern_symbol(char *name)
{
    Label *label;

    if (find_label(&labels, name) || find_label(&equs, name)) {
        error = EXTERN_REDEFINED;
        return 1;
    }

    if (find_label(&externs, name)) {
        return 0;
    }

    label = add_label_ex(&externs, name, 0, src_line, 0);
    if (!label) {
        return 1;
    }
    label->external = 1;
    label->absolute = 0;

    return 0;
}

static int add_public_symbol(char *name)
{
    if (find_label(&publics, name)) {
        return 0;
    }

    if (!add_label_ex(&publics, name, 0, src_line, 1)) {
        return 1;
    }

    return 0;
}

static int do_asm(FILE *inf, char *line)
{
    char last;
    char *ptr, *ptr1;
    char linetmp[strlen(line) + 1];
    char *str = linetmp;

    strcpy(linetmp, line);

    remove_comment(str);

    SKIP_BLANK(str);

    ptr = str;
    SKIP_TOKEN(str);
    ptr1 = str;

    if ((last = *ptr1)) {
        str++;
    }
    *ptr1 = 0;

    OpCode *first_opcode = NULL;
    if (ptr1 - ptr > 0) {
        first_opcode = find_opcode(ptr);
        if (is_conditional_opcode(first_opcode)) {
            return handle_conditional_directive(first_opcode, str, line);
        }
    }

    if (!cond_current_active()) {
        print_listing_line(line);
        finish_asm_line();
        return 0;
    }

    if (ptr1 - ptr > 0) {
        char *label = NULL;
        char *first_tok = ptr;

        OpCode *opcode = first_opcode;
        Macro *mac = find_macro(first_tok);
        if (!mac && !opcode) {
            opcode = find_opcode(first_tok);
        }

        if (!mac && !opcode) {
            label = first_tok;
            if (last) {
                SKIP_BLANK(str);

                ptr = str;
                SKIP_TOKEN(str);
                ptr1 = str;

                if ((last = *ptr1)) {
                    str++;
                }
                *ptr1 = 0;

                mac = find_macro(ptr);
                if (!mac) {
                    opcode = find_opcode(ptr);
                }
            } else {
                ptr = str;
            }

            if (src_pass == 1 &&
                    (mac || !(opcode && !strcasecmp(opcode->name, "equ")))) {
                if (find_label(&externs, label)) {
                    error = EXTERN_REDEFINED;
                    return 1;
                }
                if (in_proc) {
                    Label *global = find_label(&in_proc->globals, label);
                    if (global) {
                        add_label(&labels, label, output_addr, src_line);
                    } else {
                        add_label(&in_proc->labels, label, output_addr, src_line);
                    }
                } else {
                    add_label(&labels, label, output_addr, src_line);
                }
            }
        }

        if (mac) {
            print_listing_line(line);
            SKIP_BLANK(str);
            return expand_macro(inf, mac, last ? str : NULL);
        }

//fprintf(stderr, ">>>%s\n", line);
//fprintf(stderr, "OPCODE: %s %d %X %X\n", opcode->name, opcode->type, opcode->op, opcode->ext_op);

        if (opcode && !(opcode->cpus & CPU_MASK(target_cpu))) {
            status_printf("Opcode '%s' is not supported by CPU '%s'\n",
                          opcode->name, cpu_name(target_cpu));
            error = UNSUPPORTED_CPU_OPCODE;
            return 1;
        }

        if (opcode && opcode->type == pseudo_cpu) {
            SKIP_BLANK(str);
            char *name = str;
            SKIP_TOKEN(str);
            char tail = *str;
            *str = 0;
            int required_cpu = parse_cpu(name);
            if (label || required_cpu != target_cpu) {
                status_printf("Source requires CPU '%s'; selected CPU is '%s'\n",
                              name, cpu_name(target_cpu));
                error = CPU_MISMATCH;
                return 1;
            }
            if (tail) {
                str++;
                SKIP_BLANK(str);
                if (*str) {
                    error = EXTRA_SYMBOLS;
                    return 1;
                }
            }
            print_listing_line(line);
        } else if (opcode && !strcmp(opcode->name, "include")) {
            char name[512];
            if (label) {
                error = SYNTAX_ERROR;
                return 1;
            }
            File *file = malloc(sizeof(File));
            file->src_line = src_line + 1;
            file->in_file_path = in_file_path;
            file->in_file = in_file;
            file->prev = files;
            files = file;
            src_line = 1;
            SKIP_BLANK(str);
            snprintf(name, sizeof(name), "%s/%s", in_file_path, str);
            status_printf("\r%s\n", name);
            in_file = fopen(name, "rb");
            if (!in_file) {
                error = CANNOT_OPEN_FILE;
                return 1;
            }

            in_file_path = get_file_path(name);
            return 0;
        } else if (opcode && !strcmp(opcode->name, "extern")) {
            if (label) {
                error = SYNTAX_ERROR;
                return 1;
            }
            if (out_type != OUT_OBJECT) {
                error = EXTERN_NOT_ALLOWED_HERE;
                return 1;
            }
            if (src_pass == 1) {
                if (parse_symbol_list(str, add_extern_symbol)) {
                    return 1;
                }
            }
            print_listing_line(line);
        } else if (opcode && !strcmp(opcode->name, "public")) {
            if (label) {
                error = SYNTAX_ERROR;
                return 1;
            }
            if (out_type != OUT_OBJECT) {
                error = EXTERN_NOT_ALLOWED_HERE;
                return 1;
            }
            if (src_pass == 1) {
                if (parse_symbol_list(str, add_public_symbol)) {
                    return 1;
                }
            }
            print_listing_line(line);
        } else if (opcode && !strcmp(opcode->name, "entry")) {
            if (label) {
                error = SYNTAX_ERROR;
                return 1;
            }
            if (out_type != OUT_OBJECT) {
                error = EXTERN_NOT_ALLOWED_HERE;
                return 1;
            }
            SKIP_BLANK(str);
            if (!*str) {
                error = MISSED_OPCODE_PARAM_1;
                return 1;
            }
            reset_expr_reloc();
            entry_addr = exp_(&str);
            if (check_expr_reloc()) {
                return 1;
            }
            if (expr_reloc_label && expr_reloc_label->external) {
                error = INVALID_ENTRY_POINT;
                return 1;
            }
            SKIP_BLANK(str);
            if (*str) {
                error = EXTRA_SYMBOLS;
                return 1;
            }
            has_entry = 1;
            print_listing_line(line);
        } else if (opcode && !strcmp(opcode->name, "equ")) {
            if (!label) {
                error = MISSED_NAME_FOR_EQU;
            } else if (src_pass == 1 && find_label(&externs, label)) {
                error = EXTERN_REDEFINED;
                return 1;
            } else {
                SKIP_BLANK(str);
                reset_expr_reloc();
                unsigned int val = exp_(&str);
                int resolved = !to_second_pass && error == NO_ERROR;

                if (src_pass == 1 && error == NO_ERROR) {
                    Label *equ;
                    if (in_proc) {
                        equ = add_label_ex(&in_proc->equs, label, val,
                                           src_line, resolved);
                    } else {
                        equ = add_label_ex(&equs, label, val, src_line,
                                           resolved);
                    }
                    if (equ) {
                        equ->absolute = 1;
                    }
                } else if (src_pass == 2 && error == NO_ERROR) {
                    Label *equ;
                    if (in_proc) {
                        equ = set_label(&in_proc->equs, label, val,
                                        src_line, 1);
                    } else {
                        equ = set_label(&equs, label, val, src_line, 1);
                    }
                    if (equ) {
                        equ->absolute = 1;
                    }
                }
                to_second_pass = 0;

                print_listing_word(output_addr, val, line);
            }
        } else if (opcode && !strcmp(opcode->name, "proc")) {
            if (!label) {
                error = MISSED_NAME_FOR_PROC;
            } else {
                if (in_proc) {
                    error = NESTED_PROC_UNSUPPORTED;
                } else {
                    in_proc = find_proc(&procs, label);
                    if (!in_proc) {
                        in_proc = add_proc(&procs, label, src_line);
                    }
                }
                print_listing_line(line);
            }
        } else if (opcode && !strcmp(opcode->name, "endp")) {
            in_proc = NULL;

            print_listing_line(line);
        } else if (opcode && !strcmp(opcode->name, "global")) {
            if (!in_proc) {
                error = ONLY_INSIDE_PROC;
            } else if (src_pass == 1) {
                do {
                    SKIP_BLANK(str);
                    char *name = str;
                    SKIP_TOKEN(str);
                    if ((last = *str)) {
                        *str++ = 0;
                    }
                    add_label(&in_proc->globals, name, output_addr, src_line);
                } while (*str && (last == ',' || match(&str, ',') == 1));

                print_listing_line(line);
            }
        } else if (opcode && !strcmp(opcode->name, "macro")) {
            SKIP_BLANK(str);
            char *name = str;
            SKIP_TOKEN(str);
            *str = 0;
            print_listing_line(line);
            return add_macro(inf, name);
        } else if (opcode && !strcmp(opcode->name, "org")) {
            if (out_type == OUT_OBJECT) {
                error = ORG_NOT_ALLOWED_IN_OBJECT;
                return 1;
            }
            SKIP_BLANK(str);
            reset_expr_reloc();
            start_addr = exp_(&str);
            output_addr = start_addr;
            print_listing_line(line);
        } else if (opcode && opcode->type == pseudo_chksum) {
            if (out_type == OUT_OBJECT) {
                error = CHKSUM_NOT_ALLOWED_IN_OBJECT;
                return 1;
            }
            use_chksum = 1;
            chksum_addr = output_addr;
            output[output_addr++] = 0;
            output[output_addr++] = 0;
            print_listing_word(output_addr - 2, 0, line);
        } else if (opcode) {
            unsigned int old_addr = output_addr;
            Register *reg;
            int arg1 = 0;
            int arg2 = 0;
            int arg3 = 0;

            if ((opcode->type != op_noargs ) && last == 0) {
                error = MISSED_OPCODE_PARAM_1;
                return 1;
            }

            if (opcode->type == pseudo_db) {
                get_bytes(str);
            } else if (opcode->type == pseudo_dw) {
                get_words(str);
            } else if (opcode->type == pseudo_ds
                       || opcode->type == pseudo_align) {
                int count, fill;

                fill = 0;
                reset_expr_reloc();
                count = exp_(&str);
                if (expr_reloc_label) {
                    error = SYNTAX_ERROR;
                    return 1;
                }

                if (match(&str, ',')) {
                    reset_expr_reloc();
                    fill = exp_(&str) & 0xFF;
                    if (expr_reloc_label) {
                        error = SYNTAX_ERROR;
                        return 1;
                    }
                }

                if (opcode->type == pseudo_align) {
                    int n = 1 << count;
                    if (n > 1) {
                        n = n - 1;
                    }
                    count = ((output_addr + n) & ~n) - output_addr;
                }

                while (count-- > 0) {
                    output[output_addr++] = fill;
                }
            } else if (opcode->type == op_rel) {
                SKIP_BLANK(str);

                char *tmp = str;

                reset_expr_reloc();
                int val = exp_(&str);
                if (check_expr_reloc()) {
                    return 1;
                }
                if (expr_reloc_label && expr_reloc_label->external) {
                    error = EXTERN_NOT_ALLOWED_HERE;
                    return 1;
                }

                if (to_second_pass && src_pass == 2) {
                    add_label(&refs, tmp, output_addr + 1, src_line);
                } else if (src_pass == 2) {
                    val = val - output_addr;
                }
                to_second_pass = 0;

                if (src_pass == 2) {
                    if (val < -0x7ff || val > 0x7ff) {
                        error = LONG_RELATED_OFFSET;
                        return 1;
                    }
                }

                val = val >> 1;

                arg1 = (val & 0x700) >> 8;
                arg2 = (val & 0xe0) >> 5;
                arg3 =  val & 0x1f;
            } else if (opcode->type == op_reg) {
                SKIP_BLANK(str);

                reg = find_register_in_string(&str);
                if (!reg) {
                    error = MISSED_OPCODE_ARG_1;
                    return 1;
                }
                arg1 = reg->n;
                arg2 = 0;
                arg3 = 0;
            } else if (opcode->type != op_noargs) {
                SKIP_BLANK(str);

                if (opcode->type == op_no_reg_reg) {
                    arg1 = 0;
                } else if (opcode->type == op_ext_reg_reg) {
                    arg1 = opcode->ext_op;
                } else {
                    reg = find_register_in_string(&str);
                    if (!reg) {
                        error = MISSED_OPCODE_ARG_1;
                        return 1;
                    }
                    arg1 = reg->n;

                    if (match(&str, ',') == 0) {
                        error = EXPECTED_ARG_2;
                        return 1;
                    }

                    SKIP_BLANK(str);
                }

                if (opcode->type == op_reg_const || opcode->type == op_reg_context) {
                    char *tmp = str;
                    unsigned int reloc_offset = output_addr + 1;
                    reset_expr_reloc();
                    int val = exp_(&str);
                    if (check_expr_reloc()) {
                        return 1;
                    }

                    int is_context = opcode->type == op_reg_context;
                    int is_ldi8 = !strcmp(opcode->name, "ldi8");
                    if ((is_context || is_ldi8) && expr_reloc_label) {
                        error = EXTERN_NOT_ALLOWED_HERE;
                        return 1;
                    }
                    if (!to_second_pass || src_pass == 2) {
                        int limit = target_cpu == CPU_UCODE ? 63 : 31;
                        if (is_context && (val < 0 || val > limit)) {
                            error = INVALID_CONTEXT_INDEX;
                            return 1;
                        }
                        if (is_ldi8 && (val < 0 || val > 255)) {
                            error = INVALID_LDI8_CONSTANT;
                            return 1;
                        }
                    }
                    if (src_pass == 2 && expr_reloc_label) {
                        add_reloc(expr_high_byte ? RELOC_MSB : RELOC_LSB,
                                  reloc_offset, expr_reloc_label);
                    }

                    if (to_second_pass && src_pass == 2) {
                        add_label(&refs, tmp, output_addr + 1, src_line);
                    }
                    to_second_pass = 0;

                    arg2 = (val & 0xe0) >> 5;
                    arg3 =  val & 0x1f;
                } else {
                    reg = find_register_in_string(&str);
                    if (!reg) {
                        error = MISSED_REGISTER_ARG_2;
                        return 1;
                    }
                    arg2 = reg->n;

                    if (opcode->type != op_reg_reg) {
                        if (match(&str, ',') == 0) {
                            error = EXPECTED_ARG_3;
                            return 1;
                        }

                        SKIP_BLANK(str);
                        if (opcode->type == op_reg_reg_reg || opcode->type == op_no_reg_reg || opcode->type == op_ext_reg_reg) {
                            reg = find_register_in_string(&str);
                            if (reg) {
                                arg3 = reg->n << 2;
                            } else {
                                char *tmp = str;
                                reset_expr_reloc();
                                int val = exp_(&str);

                                if (expr_reloc_label) {
                                    error = SYNTAX_ERROR;
                                    return 1;
                                }

                                if (to_second_pass && src_pass == 2) {
                                    add_label(&refs, tmp, output_addr + 1,
                                              src_line);
                                }
                                if ((!to_second_pass || src_pass == 2) &&
                                        (target_cpu == CPU_UCODE ? (val < 0 || val > 15) : val > 16)) {
                                    error = CONSTANT_VALUE_TOO_BIG;
                                    return 1;
                                }
                                to_second_pass = 0;
                                arg3 = ((val & 0x0f) << 1) | 0x01;
                            }
                        }
                    }
                }

                SKIP_BLANK(str);

                if (strlen(str) > 0) {
                    error = EXTRA_SYMBOLS;
                }
            }

            /* Stores/GSET read PC; comparisons encode a condition, not Rd.
             * The new engine only supports explicit MOV/GGET jumps. */
            if (target_cpu == CPU_UCODE && arg1 == 0 &&
                    (opcode->type == op_reg_const ||
                     opcode->type == op_reg_context ||
                     opcode->type == op_reg ||
                     opcode->type == op_reg_reg ||
                     opcode->type == op_reg_reg_reg) &&
                    opcode->op != 0x10 && opcode->op != 0x12 &&
                    opcode->op != 0x18 && opcode->op != 0x14 &&
                    opcode->op != 0x1a && opcode->op != 0x02 &&
                    opcode->op != 0x06) {
                error = UNSUPPORTED_PC_DESTINATION;
                return 1;
            }

            if (opcode->type == pseudo_db || opcode->type == pseudo_ds
                    || opcode->type == pseudo_align) {
                if (src_pass == 2) {
                    int i;
                    char bytes[3 * 8];
                    char *ptr_bytes = bytes;

                    print_listing_line_at(old_addr, line);
                    for (i = 0; i < output_addr - old_addr; i++) {
                        if ((i % 8) == 0) {
                            ptr_bytes = bytes;
                            *ptr_bytes = 0;
                        }

                        snprintf(ptr_bytes, sizeof(bytes) - (ptr_bytes - bytes),
                                 "%s%02X", (i % 8) ? " " : "",
                                 output[old_addr + i]);
                        ptr_bytes += strlen(ptr_bytes);

                        if ((i % 8) == 7 || i == output_addr - old_addr - 1) {
                            print_listing_data(old_addr + i - (i % 8), bytes);
                        }
                    }
                }
            } else if (opcode->type == pseudo_dw) {
                if (src_pass == 2) {
                    int i;
                    char bytes[5 * 4];
                    char *ptr_bytes = bytes;

                    print_listing_line_at(old_addr, line);
                    for (i = 0; i < output_addr - old_addr; i += 2) {
                        if ((i % 8) == 0) {
                            ptr_bytes = bytes;
                            *ptr_bytes = 0;
                        }

                        snprintf(ptr_bytes, sizeof(bytes) - (ptr_bytes - bytes),
                                 "%s%02X%02X", (i % 8) ? " " : "",
                                 output[old_addr + i],
                                 output[old_addr + i + 1]);
                        ptr_bytes += strlen(ptr_bytes);

                        if ((i % 8) == 6 || i >= output_addr - old_addr - 2) {
                            print_listing_data(old_addr + i - (i % 8), bytes);
                        }
                    }
                }
            } else {
//fprintf(stderr, "%02X %02X %02X %02X\n", opcode->op, arg1, arg2, arg3);
                print_listing_insn(output_addr,
                                   (opcode->op << 3) | (arg1 & 0x07),
                                   ((arg2 << 5) & 0xe0) | (arg3 & 0x1f),
                                   line);

                output[output_addr++] = (opcode->op << 3) | (arg1 & 0x07);
                output[output_addr++] = ((arg2 << 5) & 0xe0) | (arg3 & 0x1f);
            }

        } else {
            if (strlen(ptr)) {
                error = SYNTAX_ERROR;
                return 1;
            } else {
                print_listing_line(line);
            }
        }
    } else {
        print_listing_line(line);
    }

    finish_asm_line();

    return 0;
}

static void output_hex(FILE *outf)
{
    int i;

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

    for (int i = start_addr; i < output_addr; i++) {
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

void output_binary(FILE *outf)
{
    for (unsigned int i = start_addr; i < output_addr; i++) {
        fwrite(&output[i], 1, 1, outf);
    }
}

static void write_u16(FILE *outf, unsigned int val)
{
    fputc(val & 0xff, outf);
    fputc((val >> 8) & 0xff, outf);
}

static void write_u32(FILE *outf, unsigned int val)
{
    write_u16(outf, val & 0xffff);
    write_u16(outf, (val >> 16) & 0xffff);
}

static int write_obj_name(FILE *outf, char *name)
{
    unsigned char buf[16];
    size_t len = strlen(name);

    if (len >= sizeof(buf)) {
        error = SYMBOL_NAME_TOO_LONG;
        return 1;
    }

    memset(buf, 0, sizeof(buf));
    memcpy(buf, name, len);
    fwrite(buf, 1, sizeof(buf), outf);
    return 0;
}

static Label *find_public_target(char *name)
{
    Label *label = find_label(&labels, name);

    if (!label) {
        label = find_label(&equs, name);
    }

    return label;
}

static int validate_publics(void)
{
    Label *pub = publics;

    while (pub) {
        Label *target = find_public_target(pub->name);

        if (!target || target->external) {
            error = PUBLIC_NOT_DEFINED;
            return 1;
        }

        pub = pub->prev;
    }

    return 0;
}

static int output_object(FILE *outf)
{
    unsigned int ent_count = count_labels(publics);
    unsigned int ext_count = count_labels(externs);
    unsigned int code_len = output_addr - start_addr;
    unsigned int code_offset = 0x20 + (ent_count + ext_count) * 20;
    unsigned int entry_offset = 0xffff;
    Label *ptr;
    Reloc *reloc;
    unsigned int reloc_count = 0;

    if (validate_publics()) {
        return 1;
    }

    if (has_entry) {
        if (entry_addr < start_addr || entry_addr > output_addr) {
            error = INVALID_ENTRY_POINT;
            return 1;
        }
        entry_offset = code_offset + (entry_addr - start_addr);
    }

    write_u16(outf, 0x5aa5);
    write_u16(outf, target_cpu == CPU_ORIGINAL ? 0x0001 : 0x0002);
    write_u16(outf, ent_count);
    write_u16(outf, ext_count);
    write_u16(outf, code_len);
    write_u32(outf, code_offset);
    write_u16(outf, entry_offset);
    write_u16(outf, target_cpu);
    for (int i = 0; i < 14; i++) {
        fputc(0, outf);
    }

    ptr = publics;
    while (ptr) {
        Label *target = find_public_target(ptr->name);

        if (write_obj_name(outf, ptr->name)) {
            return 1;
        }
        write_u16(outf, target->address - (target->absolute ? 0 : start_addr));
        write_u16(outf, target->absolute ? 0xffff : 0x0000);
        ptr = ptr->prev;
    }

    ptr = externs;
    while (ptr) {
        if (write_obj_name(outf, ptr->name)) {
            return 1;
        }
        write_u32(outf, 0);
        ptr = ptr->prev;
    }

    for (unsigned int i = start_addr; i < output_addr; i++) {
        fwrite(&output[i], 1, 1, outf);
    }

    reloc = relocs;
    while (reloc) {
        reloc_count++;
        reloc = reloc->next;
    }
    write_u16(outf, reloc_count);

    reloc = relocs;
    while (reloc) {
        unsigned int val = 0;

        if (reloc->external) {
            int index = label_index(externs, reloc->name);
            if (index < 0) {
                error = CANNOT_RESOLVE_REF;
                return 1;
            }
            val = index;
        }

        fputc((reloc->external ? 0x80 : 0x00) | (reloc->type & 0x03), outf);
        write_u16(outf, val);
        write_u16(outf, reloc->offset);
        reloc = reloc->next;
    }

    fputc(0, outf);
    return ferror(outf) ? 1 : 0;
}

void calculate_chksum(void)
{
    unsigned short chksum = 0;
    for (unsigned int i = start_addr; i < output_addr; i += 2) {
        unsigned short tmp = (output[i + 1] << 8) | output[i];
        chksum += tmp;
    }
    chksum ^= 0xffff;
    output[chksum_addr    ] = chksum & 0xff;
    output[chksum_addr + 1] = chksum >> 8;
}

static char *get_error_string(int error)
{
    switch(error) {
    case NO_MEMORY_FOR_LABEL:
        return "No memory for labels";
    case CANNOT_RESOLVE_REF:
        return "Cannot resolve reference";
    case NO_MEMORY_FOR_MACRO:
        return "No memory for macro";
    case NO_MEMORY_FOR_PROC:
        return "No memory for proc";
    case INVALID_NUMBER:
        return "Invalid number";
    case INVALID_HEX_NUMBER:
        return "Invalid hex number";
    case INVALID_DECIMAL_NUMBER:
        return "Invalid decimal number";
    case INVALID_OCTAL_NUMBER:
        return "Invalid octal number";
    case INVALID_BINARY_NUMBER:
        return "Invalid binary number";
    case MISSED_BRACKET:
        return "Missed bracket";
    case EXPECTED_CLOSE_QUOTE:
        return "Expected close quote";
    case MISSED_OPCODE_PARAM_1:
        return "Missed parameter";
    case LONG_RELATED_OFFSET:
        return "Related offset too long";
    case MISSED_OPCODE_ARG_1:
        return "Missed argument 1";
    case EXPECTED_ARG_2:
        return "Expected argument 2";
    case MISSED_REGISTER_ARG_2:
        return "Missed register 2";
    case EXPECTED_ARG_3:
        return "Expected argument 3";
    case CONSTANT_VALUE_TOO_BIG:
        return target_cpu == CPU_UCODE ? "4-bit constant must be in 0..15" :
               "Constant value too big (> 16)";
    case MISSED_NAME_FOR_EQU:
        return "Missed name for equ";
    case MISSED_NAME_FOR_PROC:
        return "Missed name for procedure";
    case NESTED_PROC_UNSUPPORTED:
        return "Nested procedures are not supported";
    case ONLY_INSIDE_PROC:
        return "Only onside procedure";
    case LABEL_ALREADY_DEFINED:
        return "Label name already used";
    case MACRO_ALREADY_DEFINED:
        return "Macro name already used";
    case PROC_ALREADY_DEFINED:
        return "Procedure name already used";
    case NO_MEMORY_FOR_COND:
        return "No memory for conditional assembly";
    case CONDITIONAL_NESTING_TOO_DEEP:
        return "Conditional nesting too deep";
    case UNMATCHED_ELSE:
        return "Unmatched ELSE";
    case UNMATCHED_ENDIF:
        return "Unmatched ENDIF";
    case DUPLICATE_ELSE:
        return "Duplicate ELSE";
    case UNTERMINATED_IF:
        return "Unterminated IF";
    case NO_MEMORY_FOR_RELOC:
        return "No memory for relocation";
    case NO_MEMORY_FOR_SYMBOL:
        return "No memory for symbol";
    case EXTERN_REDEFINED:
        return "External symbol already defined";
    case PUBLIC_NOT_DEFINED:
        return "Public symbol is not defined";
    case ORG_NOT_ALLOWED_IN_OBJECT:
        return "ORG is not allowed in object output";
    case CHKSUM_NOT_ALLOWED_IN_OBJECT:
        return "CHKSUM is not allowed in object output";
    case EXTERN_NOT_ALLOWED_HERE:
        return "External symbols are not allowed here";
    case INVALID_ENTRY_POINT:
        return "Invalid entry point";
    case SYMBOL_NAME_TOO_LONG:
        return "Symbol name too long for object file";
    case EXTRA_SYMBOLS:
        return "Extra symbols";
    case SYNTAX_ERROR:
        return "Syntax error";
    case CANNOT_OPEN_FILE:
        return "Cannot open file";
    case UNSUPPORTED_CPU_OPCODE:
        return "Opcode is not supported by the selected CPU";
    case CPU_MISMATCH:
        return "Source CPU does not match --cpu";
    case INVALID_CONTEXT_INDEX:
        return "Context index out of range (j11: 0..31; ucode: 0..63)";
    case INVALID_LDI8_CONSTANT:
        return "LDI8 constant must be in 0..255";
    case UNSUPPORTED_PC_DESTINATION:
        return "ucode allows PC destinations only with MOV, GGET or GGETR";
    default:
        return "No error";
    }
}

static char *get_out_name(char *in_str, char *ext)
{
    if (!in_str) {
        return NULL;
    }

    char *ptr = strrchr(in_str, '.');
    if (ptr) {
        *ptr = 0;
    }

    char *str = malloc(strlen(in_str) + strlen(ext) + 1);
    strcpy(str, in_str);
    strcat(str, ext);

    return str;
}

static int set_listing_file(char *name)
{
    if (listing_file_owned && listing_file) {
        fclose(listing_file);
    }

    listing_file = NULL;
    listing_file_owned = 0;

    if (!strcmp(name, "-")) {
        listing_file = stdout;
        return 0;
    }

    listing_file = fopen(name, "wb");
    if (!listing_file) {
        status_printf("Cannot create listing file: %s\n", name);
        return 1;
    }
    listing_file_owned = 1;

    return 0;
}

static void print_usage(char *prog)
{
    status_printf(
        "Usage: %s [--cpu original|j11|ucode] [-verilog|-binary|-object] [--list <file|->] "
        "[-D name[=expr]|--define name[=expr]] [-U name|--undef name] "
        "<input_file> [output_file]\n"
        "       %s [--cpu=original|j11|ucode] [-verilog|-binary|-obj] [--list=<file|->] "
        "[-Dname[=expr]|--define=name[=expr]] [-Uname|--undef=name] "
        "<input_file> [output_file]\n",
        prog, prog);
}

static int parse_define_name(char *str, char **expr)
{
    char *ptr = str;
    char *end;
    char last;

    SKIP_BLANK(ptr);
    end = ptr;
    SKIP_TOKEN(end);

    if (end == ptr) {
        error = SYNTAX_ERROR;
        return 1;
    }

    last = *end;
    *end = 0;

    if (last == '=') {
        *expr = end + 1;
    } else {
        char *tail = end + (last ? 1 : 0);

        if (last) {
            SKIP_BLANK(tail);
        }

        if (last && last != 0 && *tail) {
            error = EXTRA_SYMBOLS;
            return 1;
        }
        *expr = NULL;
    }

    return 0;
}

static int add_cmdline_define(char *arg)
{
    char *copy = strdup(arg);
    char *expr = NULL;
    unsigned int val = 1;

    if (!copy) {
        error = NO_MEMORY_FOR_LABEL;
        return 1;
    }

    if (parse_define_name(copy, &expr)) {
        free(copy);
        return 1;
    }

    if (expr && *expr) {
        char *ptr = expr;

        to_second_pass = 0;
        reset_expr_reloc();
        val = exp_(&ptr);
        if (error != NO_ERROR) {
            free(copy);
            return 1;
        }
        if (to_second_pass) {
            to_second_pass = 0;
            error = CANNOT_RESOLVE_REF;
            free(copy);
            return 1;
        }

        SKIP_BLANK(ptr);
        if (*ptr) {
            error = EXTRA_SYMBOLS;
            free(copy);
            return 1;
        }
    }

    Label *label = set_label(&equs, copy, val, 0, 1);
    if (label) {
        label->absolute = 1;
    }
    free(copy);
    return error != NO_ERROR;
}

static int remove_cmdline_define(char *arg)
{
    char *copy = strdup(arg);
    char *expr = NULL;

    if (!copy) {
        error = NO_MEMORY_FOR_LABEL;
        return 1;
    }

    if (parse_define_name(copy, &expr)) {
        free(copy);
        return 1;
    }
    if (expr) {
        error = SYNTAX_ERROR;
        free(copy);
        return 1;
    }

    delete_label(&equs, copy);
    free(copy);
    return 0;
}

int main(int argc, char *argv[])
{
    char *input_name = NULL;
    char *output_name = NULL;

    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            print_usage(argv[0]);
            return 0;
        } else if (!strcmp(argv[i], "--list-cpus")) {
            status_printf("original  rtl/cpu.v (default)\n"
                          "j11       rtl/j11_microengine.v\n"
                          "ucode     rtl/ucode_cpu.v\n");
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
            if (target_cpu < 0) {
                status_printf("Unknown CPU '%s'; choose original, j11 or ucode\n", name);
                return 1;
            }
        } else if (!strcmp(argv[i], "-verilog")) {
            out_type = OUT_VERILOG;
        } else if (!strcmp(argv[i], "-binary")) {
            out_type = OUT_BINARY;
        } else if (!strcmp(argv[i], "-object") || !strcmp(argv[i], "-obj")) {
            out_type = OUT_OBJECT;
        } else if (!strcmp(argv[i], "--list")) {
            if (++i >= argc || set_listing_file(argv[i])) {
                print_usage(argv[0]);
                return 1;
            }
        } else if (!strncmp(argv[i], "--list=", 7)) {
            if (set_listing_file(argv[i] + 7)) {
                print_usage(argv[0]);
                return 1;
            }
        } else if (!strcmp(argv[i], "-D") || !strcmp(argv[i], "--define")) {
            if (++i >= argc || add_cmdline_define(argv[i])) {
                status_printf("Invalid define option: %s\n",
                              (i < argc) ? argv[i] : "");
                status_printf("%s\n", get_error_string(error));
                print_usage(argv[0]);
                return 1;
            }
        } else if (!strncmp(argv[i], "-D", 2) && argv[i][2]) {
            if (add_cmdline_define(argv[i] + 2)) {
                status_printf("Invalid define option: %s\n", argv[i]);
                status_printf("%s\n", get_error_string(error));
                print_usage(argv[0]);
                return 1;
            }
        } else if (!strncmp(argv[i], "--define=", 9)) {
            if (add_cmdline_define(argv[i] + 9)) {
                status_printf("Invalid define option: %s\n", argv[i]);
                status_printf("%s\n", get_error_string(error));
                print_usage(argv[0]);
                return 1;
            }
        } else if (!strcmp(argv[i], "-U") || !strcmp(argv[i], "--undef")) {
            if (++i >= argc || remove_cmdline_define(argv[i])) {
                status_printf("Invalid undef option: %s\n",
                              (i < argc) ? argv[i] : "");
                status_printf("%s\n", get_error_string(error));
                print_usage(argv[0]);
                return 1;
            }
        } else if (!strncmp(argv[i], "-U", 2) && argv[i][2]) {
            if (remove_cmdline_define(argv[i] + 2)) {
                status_printf("Invalid undef option: %s\n", argv[i]);
                status_printf("%s\n", get_error_string(error));
                print_usage(argv[0]);
                return 1;
            }
        } else if (!strncmp(argv[i], "--undef=", 8)) {
            if (remove_cmdline_define(argv[i] + 8)) {
                status_printf("Invalid undef option: %s\n", argv[i]);
                status_printf("%s\n", get_error_string(error));
                print_usage(argv[0]);
                return 1;
            }
        } else if (argv[i][0] == '-') {
            status_printf("Unknown option: %s\n", argv[i]);
            return 1;
        } else if (!input_name) {
            input_name = argv[i];
        } else if (!output_name) {
            output_name = argv[i];
        } else {
            print_usage(argv[0]);
            return 1;
        }
    }

    if (!input_name) {
        print_usage(argv[0]);
        return 1;
    }

    const char *cpu_symbols[] = {
        "__CPU_ORIGINAL__", "__CPU_J11__", "__CPU_UCODE__"
    };
    for (int cpu = 0; cpu < CPU_COUNT; cpu++) {
        char define[64];
        if (find_label(&equs, (char *)cpu_symbols[cpu])) {
            status_printf("Reserved CPU symbol: %s\n", cpu_symbols[cpu]);
            return 1;
        }
        snprintf(define, sizeof(define), "%s=%d",
                 cpu_symbols[cpu], cpu == target_cpu);
        if (add_cmdline_define(define)) return 1;
    }

    start_addr = 0;

    in_file = fopen(input_name, "rb");
    if (in_file) {
        int err;
        char str[512];

        in_file_path = strdup(input_name);
        get_file_path(in_file_path);

        output_addr = start_addr;
        src_pass = 1;
        src_line = 1;
        in_macro = 0;
        in_proc = NULL;
        cond_depth = 0;
        cond_records = NULL;
        cond_records_tail = NULL;
        cond_replay = NULL;
        relocs = NULL;
        relocs_tail = NULL;
        has_entry = 0;

        // Pass 1

        status_printf("\nPass 1\n");

        do {
            if (files) {
                fclose(in_file);
                in_file = files->in_file;
                in_file_path = files->in_file_path;
                src_line = files->src_line;
                File *tmp = files->prev;
                free(files);
                files = tmp;
            }

            while(fgets(str, sizeof(str), in_file)) {
                char *ptr = str;
                REMOVE_ENDLINE(ptr);
                if ((err = do_asm(in_file, str)) || error != NO_ERROR) {
                    status_printf("Line %d: %s\n", src_line, str);
                    status_printf("Compilation failed: %s\n\n",
                                  get_error_string(error));
                    return 1;
                }
            }
        } while(files);

        if (cond_depth != 0) {
            error = UNTERMINATED_IF;
            status_printf("Line %d: unterminated conditional\n",
                          cond_stack[cond_depth - 1].line);
            status_printf("Compilation failed: %s\n\n",
                          get_error_string(error));
            return 1;
        }

        restore_root_file();

        output_addr = start_addr;
        src_pass = 2;
        src_line = 1;
        in_macro = 0;
        in_proc = NULL;
        cond_depth = 0;
        cond_replay = cond_records;
        has_entry = 0;

        if (fseek(in_file, 0, SEEK_SET) != 0) {
            status_printf("Error rewinding file for pass 2\n");
            return 1;
        }

        // Pass 2

        status_printf("\n\nPass 2\n\n");

        do {
            if (files) {
                fclose(in_file);
                in_file = files->in_file;
                in_file_path = files->in_file_path;
                src_line = files->src_line;
                File *tmp = files->prev;
                free(files);
                files = tmp;
            }

            while(fgets(str, sizeof(str), in_file)) {
                char *ptr = str;
                REMOVE_ENDLINE(ptr);
                if ((err = do_asm(in_file, str)) || error != NO_ERROR) {
                    status_printf("Line %d: %s\n", src_line, str);
                    status_printf("Compilation failed: %s\n\n",
                                  get_error_string(error));
                    return 1;
                }
            }
        } while(files);

        if (cond_depth != 0) {
            error = UNTERMINATED_IF;
            status_printf("Line %d: unterminated conditional\n",
                          cond_stack[cond_depth - 1].line);
            status_printf("Compilation failed: %s\n\n",
                          get_error_string(error));
            return 1;
        }
        if (cond_replay) {
            error = SYNTAX_ERROR;
            status_printf("Compilation failed: %s\n\n",
                          get_error_string(error));
            return 1;
        }

        relink_refs();

        if (use_chksum) {
            calculate_chksum();
        }

        listing_printf("\nConstants:\n");
        dump_labels(equs);
        listing_printf("\nLabels:\n");
        dump_labels(labels);
        listing_printf("\nRefs:\n");
        dump_labels(refs);

        status_printf("\nErrors: %s\n\n", get_error_string(error));

        if (error == NO_ERROR) {
            char *name;
            if (output_name) {
                name = strdup(output_name);
            } else {
                name = get_out_name(input_name,
                                    (out_type == OUT_BINARY) ? ".bin" :
                                    (out_type == OUT_VERILOG) ? ".v" :
                                    (out_type == OUT_OBJECT) ? ".obj" :
                                    ".mem");
            }
            FILE *outf = fopen(name, "wb");
            if (outf) {
                if (out_type == OUT_BINARY) {
                    output_binary(outf);
                } else if (out_type == OUT_VERILOG) {
                    output_verilog(outf);
                } else if (out_type == OUT_OBJECT) {
                    output_object(outf);
                } else {
                    output_hex(outf);
                }
                fclose(outf);
            } else {
                error = 1;
                status_printf("Can't create output file!\n");
            }
            free(name);
        }

        fclose(in_file);
    } else {
        status_printf("Cannot open input file!\n");
        return -1;
    }

    return error ? 1 : 0;
}
