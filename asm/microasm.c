#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

enum {
    noargs = 0,
    reg_const,
    reg_reg,
    reg_reg_off,
    reg_reg_reg,
};

typedef struct {
    char *name;
    int type;
    int op;
} OpCode;

static OpCode opcode_table[] = {
    { "nop"	, noargs	, 0x0	},
    { "load"	, reg_reg_off	, 0x1	},
    { "store"	, reg_reg_off	, 0x2	},
    { "set"	, reg_const	, 0x3	},
    { "lt"	, reg_reg_reg	, 0x4	},
    { "eq"	, reg_reg_reg	, 0x5	},
    { "beq"	, reg_const	, 0x6	},
    { "bneq"	, reg_const	, 0x7	},
    { "add"	, reg_reg_reg	, 0x8	},
    { "sub"	, reg_reg_reg	, 0x9	},
    { "shl"	, reg_reg_reg	, 0xa	},
    { "shr"	, reg_reg_reg	, 0xb	},
    { "and"	, reg_reg_reg	, 0xc	},
    { "or"	, reg_reg_reg	, 0xd	},
    { "inv"	, reg_reg	, 0xe	},
    { "xor"	, reg_reg_reg	, 0xf	},
};

typedef struct Register {
    char *name;
    int n;
} Register;

static Register regs_table[] = {
    { "r0"	, 0 },
    { "r1"	, 1 },
    { "r2"	, 2 },
    { "r3"	, 3 },
    { "r4"	, 4 },
    { "r5"	, 5 },
    { "r6"	, 6 },
    { "r7"	, 7 },
    { "r8"	, 8 },
    { "r9"	, 9 },
    { "r10"	, 10 },
    { "r11"	, 11 },
    { "r12"	, 12 },
    { "r13"	, 13 },
    { "r14"	, 14 },
    { "r15"	, 15 },
    { "lr"	, 13 },
    { "sp"	, 14 },
    { "pc"	, 15 },
};

typedef struct Label {
    char	*name;
    unsigned int address;
    int		line;
    struct Label *prev;
} Label;

static int output[65536];
static unsigned int output_addr = 0;
static int src_line = 1;

static Label *labels = NULL;
static Label *refs = NULL;

static int error = 0;
static int to_second_pass = 0;

#define SKIP_BLANK(s) { \
    while (*(s) && isblank(*(s))) { \
	(s)++; \
    } \
}

#define SKIP_TOKEN(s) { \
    while (*(s) && (isalnum(*(s)) || *s == '_')) { \
	(s)++; \
    } \
}

#define REMOVE_ENDLINE(s) { \
    while (*(s)) { \
	if (*(s) == '\n' || *(s) == '\r') *(s) = 0; \
	(s)++; \
    } \
}

static int exp_(char **str);

static Label *add_label(Label **list, char *name, unsigned int address, int line)
{
    Label *new = malloc(sizeof(Label));
    if (!new) {
	fprintf(stderr, "Cannot allocate memory for label entry!\n");
	error = 1;
	return NULL;
    }
    new->name = strdup(name);
    new->address = address;
    new->line = line;
    new->prev = *list;

    *list = new;

    return new;
}

static Label *find_label(Label **list, char *name)
{
    Label *ptr = *list;

    while (ptr) {
	if (!strcmp(ptr->name, name)) {
	    return ptr;
	}
	ptr = ptr->prev;
    }

    return NULL;
}

static void dump_labels(Label *list)
{
    while (list) {
	fprintf(stderr, "[%s] %04X\n", list->name, list->address);
	list = list->prev;
    }
}

static int relink_refs()
{
    Label *tmp = refs;

    while (tmp) {
	char *ptr = tmp->name;
	int val = exp_(&ptr);
	if (error == 0 && to_second_pass == 0) {
	    output[tmp->address] = val;
	} else {
	    fprintf(stderr, "Can't resolve %s in %s line %d\n", tmp->name, ptr, tmp->line);
	    return 1;
	}
	tmp = tmp->prev;
    }

    return 0;
}

static OpCode *find_opcode(char *name)
{
    for (int i = 0; i < sizeof(opcode_table) / sizeof(OpCode); i++) {
	if (!strcmp(name, opcode_table[i].name)) {
	    return &opcode_table[i];
	}
    }

    return NULL;
}

static Register *find_register(char *name)
{
    for (int i = 0; i < sizeof(regs_table) / sizeof(Register); i++) {
	if (!strcmp(name, regs_table[i].name)) {
	    return &regs_table[i];
	}
    }

    return NULL;
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
		return(c - '0');
	} else if (isxdigit(c)) {
		if (isupper(c)) {
			return(c - 'A' + 10);
		} else {
			return(c - 'a' + 10);
		}
	} else {
		fprintf(stderr, "Invalid number!\n");
		error = 1;
		return 0;
	}
}

static int hexnum(char **str)
{
	int n;

	if (!isxdigit(*(*str))) {
		fprintf(stderr, "Invalid hex number!\n");
		error = 1;
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
		fprintf(stderr, "Invalid number!\n");
		error = 1;
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
		fprintf(stderr, "Invalid octal number!\n");
		error = 1;
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
		fprintf(stderr, "Invalid binary number!\n");
		error = 1;
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
	if (*(*str) == '\\') {
		(*str)++;
	}
	return c;
}

static int operand(char **str)
{
    char *ptr = *str;
    char tmp[strlen(*str) + 1];
    char *ptr1 = tmp;

    while (*ptr && !isblank(*ptr)) {
	*ptr1++ = *ptr++;
    }
    *ptr1 = 0;

    Label *label = find_label(&labels, tmp);

    if (label) {
	*str = ptr;
	return(label->address);
    } else if (match(str, '$')) {
	return(hexnum(str));
    } else if (match(str, '@')) {
	return(octal(str));
    } else if (match(str, '%')) {
	return(binary(str));
    } else if (match(str, '\'')) {
	return(character(str));
    } else if (isdigit(*(*str))) {
	return(decimal(str));
    } else {
	if (label) {
	    fprintf(stderr, "Illegal expression!\n");
	    error = 1;
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
	if (match(str, ')'))
	    return n;
	else {
	    fprintf(stderr, "Missing bracket!");
	    error = 1;
	    return 0;
	}
    }
    return operand(str);
}

static int exp7(char **str)
{
    if (match(str, '~'))
	return 0xFFFF ^ exp8(str);
    if (match(str, '-'))
	return -exp8(str);
    return exp8(str);
}

static int exp6(char **str)
{
    int n;
    n = exp7(str);
    while (*(*str)) {
	if (match(str, '*'))
	    n = n * exp7(str);
	else if (match(str, '/'))
	    n = n / exp7(str);
	else if (match(str, '%'))
	    n = n % exp7(str);
	else
	    break;
    }
    return n;
}

static int exp5(char **str)
{
    int n;
    n = exp6(str);
    while (*(*str)) {
	if (match(str, '+'))
	    n = n + exp6(str);
	else if (match(str, '-'))
	    n = n - exp6(str);
	else
	    break;
    }
    return n;
}

static int exp4(char **str)
{
    int n;
    n = exp5(str);
    while (*(*str)) {
	if (match(str, '&'))
	    n = n & exp5(str);
	else
	    break;
    }
    return n;
}

static int exp3(char **str)
{
    int n;
    n = exp4(str);
    while (*(*str)) {
	if (match(str, '^'))
	    n = n ^ exp4(str);
	else
	    break;
    }
    return n;
}

static int exp2_(char **str)
{
    int n;
    n = exp3(str);
    while (*(*str)) {
	if (match(str, '|'))
	    n = n | exp3(str);
	else
	    break;
    }
    return n;
}

static int exp_(char **str)
{
	if (match(str, '/'))
		return(exp2_(str) >> 8);
	else
		return(exp2_(str));
}

static int do_asm(char *str)
{
    char *ptr, *ptr1;
    char strtmp[strlen(str) + 1];

    ptr = str;
    REMOVE_ENDLINE(ptr);

    strcpy(strtmp, str);

    SKIP_BLANK(str);
    ptr = str;
    SKIP_TOKEN(str);
    ptr1 = str;
    str++;

    if (*ptr1 == ':') {
	*ptr1 = 0;
	add_label(&labels, ptr, output_addr, src_line);
    } else {
	char last = *ptr1;
	*ptr1 = 0;

	OpCode *opcode = find_opcode(ptr);

	if (opcode) {
	    Register *reg;
	    int arg1 = 0;
	    int arg2 = 0;
	    int arg3 = 0;

	    if (opcode->type != noargs && last == 0) {
		fprintf(stderr, "Missed opcode parameters!\n");
		return 1;
	    }

	    if (opcode->type != noargs) {
		SKIP_BLANK(str);
		ptr = str;
		SKIP_TOKEN(str);
		ptr1 = str;
		str++;

		last = *ptr1;
		*ptr1 = 0;

		reg = find_register(ptr);
		if (!reg) {
		    fprintf(stderr, "Missed register arg1!\n");
		    return 1;
		}
		arg1 = reg->n;

		SKIP_BLANK(str);
		ptr = str;
		SKIP_TOKEN(str);
		ptr1 = str;
		str++;

		if (opcode->type == reg_const) {
		    char *tmp = ptr;
		    int val = exp_(&ptr);
		    if (to_second_pass) {
			add_label(&refs, tmp, output_addr + 1, src_line);
			to_second_pass = 0;
		    }
		    arg2 = (val & 0xf0) >> 4;
		    arg3 = val & 0x0f;
		} else {
		    last = *ptr1;
		    *ptr1 = 0;

		    if (last == 0) {
			fprintf(stderr, "Missed opcode parameters!\n");
			return 1;
		    }

		    reg = find_register(ptr);
		    if (!reg) {
			fprintf(stderr, "Missed register arg2!\n");
			return 1;
		    }
		    arg2 = reg->n;

		    if (opcode->type != reg_reg) {
			SKIP_BLANK(str);
			ptr = str;
			SKIP_TOKEN(str);
			ptr1 = str;
			str++;

			if (opcode->type == reg_reg_off) {
			    char *tmp = ptr;
			    int val = exp_(&ptr);
			    if (to_second_pass) {
				add_label(&refs, tmp, output_addr + 1, src_line);
				to_second_pass = 0;
			    }
			    arg3 = val & 0x0f;
			} else {
			    last = *ptr1;
			    *ptr1 = 0;

			    reg = find_register(ptr);
			    if (!reg) {
				fprintf(stderr, "Missed register arg2!\n");
				return 1;
			    }
			    arg3 = reg->n;
			}
		    }
		}
	    }

	    fprintf(stderr, "%04X: %X%X%X%X\t%s\n", output_addr, opcode->op & 0x0f, arg1 & 0x0f, arg2 & 0x0f, arg3 & 0x0f, strtmp);

	    output[output_addr++] = (opcode->op << 4) | (arg1 & 0x0f);
	    output[output_addr++] = (arg2 << 4) | (arg3 & 0x0f);

	} else {
	    fprintf(stderr, "Syntax error '%s'!\n", ptr);
	}
    }

    src_line++;

    return 0;
}

static void output_hex()
{
    for (int i = 0; i < output_addr; i++) {
	if ((i % 16) == 0) {
	    printf("%04X:", i);
	}

	printf(" %02X", output[i]);

	if ((i % 16) == 15) {
	    printf("\n");
	}
    }
}

int main(int argc, char *argv[])
{
    FILE *inf;

    inf = fopen(argv[1], "rb");
    if (inf) {
	int err;
	char str[512];

	while (fgets(str, sizeof(str), inf)) {
	    if ((err = do_asm(str))) {
		break;
	    }
	}

	relink_refs();

	fprintf(stderr, "Labels:\n");
	dump_labels(labels);
	fprintf(stderr, "Refs:\n");
	dump_labels(refs);

	output_hex();

	fclose(inf);
    } else {
	fprintf(stderr, "Cannot open input file!\n");
	return -1;
    }

    return 0;
}
