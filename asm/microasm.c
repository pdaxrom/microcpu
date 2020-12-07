#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

enum {
	op_noargs = 0,
	op_reg_const,
	op_rel,
	op_reg_reg,
	op_no_reg_reg,
	op_reg_reg_reg,

	pseudo_db,
	pseudo_dw,
	pseudo_ds,
	pseudo_align,
	pseudo_macro,
};

typedef struct {
	char *name;
	int type;
	int op;
	int ext_op;
} OpCode;

static OpCode opcode_table[] = {
		{ "ldrl" , op_reg_reg_reg  , 0x00, 0x0  },
		{ "strl" , op_reg_reg_reg  , 0x02, 0x0  },
		{ "ldrh" , op_reg_reg_reg  , 0x04, 0x0  },
		{ "strh" , op_reg_reg_reg  , 0x06, 0x0  },
		{ "setl" , op_reg_const    , 0x08, 0x0  },
		{ "seth" , op_reg_const    , 0x0a, 0x0  },
		{ "movl" , op_reg_reg      , 0x0c, 0x0  },
		{ "movh" , op_reg_reg      , 0x0e, 0x0  },

		{ "mov"  , op_reg_reg      , 0x10, 0x0  },

		{ "b"    , op_rel          , 0x16, 0x0  },
		{ "ble"  , op_rel          , 0x18, 0x0  },
		{ "bge"  , op_rel          , 0x1a, 0x0  },
		{ "beq"  , op_rel          , 0x1c, 0x0  },
		{ "bcs"  , op_rel          , 0x1e, 0x0  },

		{ "cmp"  , op_no_reg_reg   , 0x01, 0x0  },

//		{ "addc" , op_reg_reg_reg  , 0x09, 0x0  },
//		{ "subc" , op_reg_reg_reg  , 0x0b, 0x0  },

		{ "add"  , op_reg_reg_reg  , 0x11, 0x0  },
		{ "sub"  , op_reg_reg_reg  , 0x13, 0x0  },
		{ "shl"  , op_reg_reg_reg  , 0x15, 0x0  },
		{ "shr"  , op_reg_reg_reg  , 0x17, 0x0  },
		{ "and"  , op_reg_reg_reg  , 0x19, 0x0  },
		{ "or"   , op_reg_reg_reg  , 0x1b, 0x0  },
		{ "inv"  , op_reg_reg      , 0x1d, 0x0  },
		{ "xor"  , op_reg_reg_reg  , 0x1f, 0x0  },

		/* pseudo ops */
		{ "db"   , pseudo_db    , 0x0, 0x0  },
		{ "dw"   , pseudo_dw    , 0x0, 0x0  },
		{ "ds"   , pseudo_ds    , 0x0, 0x0  },
		{ "align", pseudo_align , 0x0, 0x0  },
		{ "macro", pseudo_macro , 0x0, 0x0  },
		{ "endm" , pseudo_macro , 0x0, 0x0  },
};

typedef struct Register {
	char *name;
	int n;
} Register;

static Register regs_table[] = {
		{ "r0" ,  0 },
		{ "r1" ,  1 },
		{ "r2" ,  2 },
		{ "r3" ,  3 },
		{ "r4" ,  4 },
		{ "r5" ,  5 },
		{ "r6" ,  6 },
		{ "r7" ,  7 },
		{ "pc" ,  0 },
		{ "sp" ,  1 },
		{ "lr" ,  2 },
		{ "v0" ,  3 },
		{ "v1" ,  4 },
		{ "v2" ,  5 },
		{ "v3" ,  6 },
		{ "v4" ,  7 },
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
	struct Label *prev;
} Label;

static int output[65536];
static unsigned int output_addr = 0;

static int src_pass = 1;
static int src_line = 1;

static Label *labels = NULL;
static Label *refs = NULL;

static Macro *macros = NULL;

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

#define STRING_TOLOWER(s) { \
    while (*(s)) { \
	*(s) = tolower(*(s)); \
	(s)++; \
    } \
}

static void remove_comment(char *str) {
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

static Label* add_label(Label **list, char *name, unsigned int address,
		int line) {
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

static Label* find_label(Label **list, char *name) {
	Label *ptr = *list;

	while (ptr) {
		if (!strcmp(ptr->name, name)) {
			return ptr;
		}
		ptr = ptr->prev;
	}

	return NULL;
}

static void dump_labels(Label *list) {
	while (list) {
		fprintf(stderr, "[%s] %04X\n", list->name, list->address);
		list = list->prev;
	}
}

static int relink_refs() {
	Label *tmp = refs;

	while (tmp) {
		char *ptr = tmp->name;
		int val = exp_(&ptr);
		if (error == 0 && to_second_pass == 0) {
			output[tmp->address] = val;
		} else {
			fprintf(stderr, "Can't resolve %s in %s line %d\n", tmp->name, ptr,
					tmp->line);
			error++;
		}
		tmp = tmp->prev;
	}

	return 0;
}

static OpCode* find_opcode(char *name) {
	for (int i = 0; i < sizeof(opcode_table) / sizeof(OpCode); i++) {
		if (!strcmp(name, opcode_table[i].name)) {
			return &opcode_table[i];
		}
	}

	return NULL;
}

static Register* find_register(char *name) {
	for (int i = 0; i < sizeof(regs_table) / sizeof(Register); i++) {
		if (!strcmp(name, regs_table[i].name)) {
			return &regs_table[i];
		}
	}

	return NULL;
}

static OpCode* find_opcode_in_string(char **str) {
	char tmp[strlen(*str) + 1];
	char *ptr = tmp;
	char *ptr_str = *str;

	SKIP_BLANK(ptr_str);

	while(*ptr_str && isalnum(*ptr_str)) {
	    *ptr++ = *ptr_str++;
	}

	*ptr = 0;
	ptr = tmp;

	STRING_TOLOWER(ptr);

	OpCode* op = find_opcode(tmp);

	if (op) {
	    *str = ptr_str;
	}

	return op;
}

static Register* find_register_in_string(char **str) {
	char tmp[strlen(*str) + 1];
	char *ptr = tmp;
	char *ptr_str = *str;

	SKIP_BLANK(ptr_str);

	while(*ptr_str && isalnum(*ptr_str)) {
	    *ptr++ = *ptr_str++;
	}

	*ptr = 0;
	ptr = tmp;

	STRING_TOLOWER(ptr);

	Register *reg = find_register(tmp);

	if (reg) {
	    *str = ptr_str;
	}

	return reg;
}

static int add_macro(FILE *inf, char *name) {
	char str[512];
	Macro *mac = malloc(sizeof(Macro));

	mac->name = strdup(name);
	mac->lines = 0;
	mac->prev = macros;

	while(fgets(str, sizeof(str), inf)) {
	    char tmp[512];
	    char *ptr = str;
	    REMOVE_ENDLINE(ptr);

	    if (src_pass == 2) {
		fprintf(stderr, "%04X:     \t%s\n", output_addr, str);
	    }

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

	    mac->line = realloc(mac->line, sizeof(mac->line) * (mac->lines + 1));
	    mac->line[mac->lines] = strdup(str);
	    mac->lines++;
	}

	macros = mac;

	return 0;
}

static Macro* find_macro(char *name) {
	Macro *tmp = macros;
	while (tmp) {
	    if (!strcmp(tmp->name, name)) {
		return tmp;
	    }
	    tmp = tmp->prev;
	}
	return NULL;
}

static int match(char **str, char c) {
	SKIP_BLANK(*str);

	if (*(*str) != c) {
		return 0;
	}

	(*str)++;
	return 1;
}

static int exp2_(char **str);

static int toint(char c) {
	if (isdigit(c)) {
		return (c - '0');
	} else if (isxdigit(c)) {
		if (isupper(c)) {
			return (c - 'A' + 10);
		} else {
			return (c - 'a' + 10);
		}
	} else {
		fprintf(stderr, "Invalid number!\n");
		error = 1;
		return 0;
	}
}

static int hexnum(char **str) {
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

static int decimal(char **str) {
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

static int octal(char **str) {
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

static int binary(char **str) {
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

static int character(char **str) {
	char c;

	c = *(*str)++;
	if (*(*str) == '\\') {
		(*str)++;
	}
	return c;
}

static int operand(char **str) {
	char *ptr = *str;
	char tmp[strlen(*str) + 1];
	char *ptr1 = tmp;

	while (*ptr && (isalnum(*ptr) || *ptr == '_')) {
		*ptr1++ = *ptr++;
	}
	*ptr1 = 0;

	Label *label = find_label(&labels, tmp);

	if (label) {
		*str = ptr;
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
		to_second_pass = 1;
		return 0;
	}
}

static int exp8(char **str) {
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

static int exp7(char **str) {
	if (match(str, '~'))
		return 0xFFFF ^ exp8(str);
	if (match(str, '-'))
		return -exp8(str);
	return exp8(str);
}

static int exp6(char **str) {
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

static int exp5(char **str) {
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

static int exp4(char **str) {
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

static int exp3(char **str) {
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

static int exp2_(char **str) {
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

static int exp_(char **str) {
	if (match(str, '/'))
		return (exp2_(str) >> 8);
	else
		return (exp2_(str));
}

static int get_bytes(char *str) {
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
			output[output_addr++] = exp_(&str) & 0xFF;

			if (to_second_pass && src_pass == 2) {
				char tmp1[strlen(tmp) + 1];
				strcpy(tmp1, tmp);
				tmp = tmp1;
				while (*tmp && !isblank(*tmp) && *tmp != ',') {
					tmp++;
				}
				*tmp = 0;
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
		fprintf(stderr, "Expected close quote.\n");
		error = 1;
	}

	return output_addr - old_addr;
}

static int get_words(char *str) {
	int word;
	int nbytes = 0;
	int linesize = strlen(str);
	int old_addr = output_addr;

	while (nbytes < linesize) {
		char *tmp = str;
		word = exp_(&str);

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

		output[output_addr++] = word >> 8;
		output[output_addr++] = word & 0xFF;
		if (match(&str, ',') == 0) {
			break;
		}

	}

	return output_addr - old_addr;
}

static int do_asm(FILE *inf, char *str);

static int expand_macro(FILE *inf, Macro *mac, char *args) {
//fprintf(stderr, "[%s]\n", args);
	for (int i = 0; i < mac->lines; i++) {
//fprintf(stderr, ">>%s\n", mac->line[i]);
		char line[strlen(mac->line[i] + 1)];
		strcpy(line, mac->line[i]);
		int ret = do_asm(inf, line);
	    if (ret) {
		return ret;
	    }
	}
	return 0;
}

static int do_asm(FILE *inf, char *str) {
	char *ptr, *ptr1;
	char strtmp[strlen(str) + 1];

	ptr = str;
	REMOVE_ENDLINE(ptr);

	strcpy(strtmp, str);

	remove_comment(str);

	SKIP_BLANK(str);
	ptr = str;
	SKIP_TOKEN(str);
	ptr1 = str;
	str++;

	if (*ptr1 == ':') {
		*ptr1 = 0;
		if (src_pass == 1) {
			add_label(&labels, ptr, output_addr, src_line);
		}
		if (src_pass == 2) {
			fprintf(stderr, "%04X:     \t%s\n", output_addr, strtmp);
		}
	} else {
		char last = *ptr1;
		*ptr1 = 0;

		ptr1 = ptr;
		STRING_TOLOWER(ptr1);

		Macro *mac = find_macro(ptr);

		if (mac) {
			return expand_macro(inf, mac, str);
		}

		OpCode *opcode = find_opcode(ptr);

//fprintf(stderr, "OPCODE: %s %d %X %X\n", opcode->name, opcode->type, opcode->op, opcode->ext_op);

		if (opcode) {
			unsigned int old_addr = output_addr;
			Register *reg;
			int arg1 = 0;
			int arg2 = 0;
			int arg3 = 0;

			if (!strcmp(opcode->name, "macro")) {
			    SKIP_BLANK(str);
			    char *name = str;
			    SKIP_TOKEN(str);
			    *str = 0;
			    if (src_pass == 2) {
				fprintf(stderr, "%04X:     \t%s\n", output_addr, strtmp);
			    }
			    return add_macro(inf, name);
			}

			if ((opcode->type != op_noargs ) && last == 0) {
				fprintf(stderr, "Missed opcode parameters!\n");
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
				count = exp_(&str);

				if (match(&str, ',')) {
					fill = exp_(&str) & 0xFF;
				}

				if (opcode->type == pseudo_align) {
					int n = count - 1;
					count = ((output_addr + count) & ~n) - output_addr;
				}

				while (count-- > 0) {
					output[output_addr++] = fill;
				}
			} else if (opcode->type == op_rel) {
				SKIP_BLANK(str);

				char *tmp = str;

				int val = exp_(&str);

				if (to_second_pass && src_pass == 2) {
					add_label(&refs, tmp, output_addr + 1, src_line);
				} else if (src_pass == 2) {
					val = val - output_addr - 1;
				}
				to_second_pass = 0;

				if (val < -0x3ff || val > 0x1ff) {
				    fprintf(stderr, "ERROR: Related branch overflow!\n");
				    error = 1;
				}

				arg1 = (val & 0x300) >> 8;
				arg2 = (val & 0xe0) >> 5;
				arg3 =  val & 0x1f;
			} else if (opcode->type != op_noargs) {
				SKIP_BLANK(str);

				if (opcode->type == op_no_reg_reg) {
					arg1 = 0;
				} else {
					reg = find_register_in_string(&str);
					if (!reg) {
						fprintf(stderr, "Missed register arg1!\n");
						return 1;
					}
					arg1 = reg->n;

					if (match(&str, ',') == 0) {
						fprintf(stderr, "parameter 2 expected!\n");
						error = 1;
						return 1;
					}

					SKIP_BLANK(str);
				}

				if (opcode->type == op_reg_const) {
					char *tmp = str;
					int val = exp_(&str);

					if (to_second_pass && src_pass == 2) {
						add_label(&refs, tmp, output_addr + 1, src_line);
					}
					to_second_pass = 0;

					arg2 = (val & 0xe0) >> 5;
					arg3 =  val & 0x1f;
				} else {
					reg = find_register_in_string(&str);
					if (!reg) {
						fprintf(stderr, "Missed register arg2!\n");
						return 1;
					}
					arg2 = reg->n;

					if (opcode->type != op_reg_reg) {
						if (match(&str, ',') == 0) {
							fprintf(stderr, "parameter 3 expected!\n");
							error = 1;
							return 1;
						}

						SKIP_BLANK(str);
						if (opcode->type == op_reg_reg_reg || opcode->type == op_no_reg_reg) {
							reg = find_register_in_string(&str);
							if (reg) {
								arg3 = reg->n << 1;
							} else {
								char *tmp = str;
								int val = exp_(&str);

								if (to_second_pass && src_pass == 2) {
									add_label(&refs, tmp, output_addr + 1,
										src_line);
								}
								to_second_pass = 0;

								if (val > 16) {
									fprintf(stderr, "Constant value too big (> 16)\n");
									error = 1;
									return 1;
								}
								arg3 = ((val & 0x0f) << 1) | 0x01;
							}
						}
					}
				}
			}

			if (opcode->type == pseudo_db || opcode->type == pseudo_ds
					|| opcode->type == pseudo_align) {
				if (src_pass == 2) {
					int i;
					fprintf(stderr, "%04X:     \t%s\n", old_addr, strtmp);
					for (i = 0; i < output_addr - old_addr; i++) {
						if ((i % 8) == 0) {
							fprintf(stderr, "%04X:", old_addr + i);
						}

						fprintf(stderr, " %02X", output[old_addr + i]);

						if ((i % 8) == 7) {
							fprintf(stderr, "\n");
						}
					}

					if ((i % 8) != 0) {
						fprintf(stderr, "\n");
					}
				}
			} else if (opcode->type == pseudo_dw) {
				if (src_pass == 2) {
					int i;
					fprintf(stderr, "%04X:     \t%s\n", old_addr, strtmp);
					for (i = 0; i < output_addr - old_addr; i += 2) {
						if ((i % 8) == 0) {
							fprintf(stderr, "%04X:", old_addr + i);
						}

						fprintf(stderr, " %02X%02X", output[old_addr + i],
								output[old_addr + i + 1]);

						if ((i % 8) == 6) {
							fprintf(stderr, "\n");
						}
					}

					if ((i % 8) != 0) {
						fprintf(stderr, "\n");
					}
				}
			} else {
				if (src_pass == 2) {
//fprintf(stderr, "%02X %02X %02X %02X\n", opcode->op, arg1, arg2, arg3);
					fprintf(stderr, "%04X: %02X%02X\t%s\n", output_addr,
							(opcode->op << 3) | (arg1 & 0x07),
							((arg2 << 5) & 0xe0) | (arg3 & 0x1f),
							strtmp);
				}

				output[output_addr++] = (opcode->op << 3) | (arg1 & 0x07);
				output[output_addr++] = ((arg2 << 5) & 0xe0) | (arg3 & 0x1f);
			}

		} else {
			if (strlen(ptr)) {
				fprintf(stderr, "Syntax error '%s'!\n", ptr);
			} else if (src_pass == 2) {
				fprintf(stderr, "%04X:     \t%s\n", output_addr, strtmp);
			}
		}
	}

	if (src_pass == 1) {
		fprintf(stderr, "Line: %d\r", src_line);
	}

	src_line++;

	return 0;
}

static void output_hex() {
	int i;

	for (i = 0; i < output_addr; i++) {
		if ((i % 16) == 0) {
			printf("%04X:", i);
		}

		printf(" %02X", output[i]);

		if ((i % 16) == 15) {
			printf("\n");
		}
	}

	if ((i % 16) != 0) {
		printf("\n");
	}
}

static void output_verilog() {
	printf( "module sram(\n"											\
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

	for (int i = 0; i < output_addr; i++) {
		printf("        Mem[%d] = 8'h%02x;\n", i, output[i]);
	}

	printf( "    end\n"													\
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

int main(int argc, char *argv[]) {
	int out_type = 0;
	FILE *inf;

	if (!strcmp(argv[1], "-verilog")) {
		out_type = 1;
		argv++;
	}

	inf = fopen(argv[1], "rb");
	if (inf) {
		int err;
		char str[512];

		output_addr = 0;
		src_pass = 1;
		src_line = 1;

		// Pass 1

		fprintf(stderr, "\nPass 1\n");

		while (fgets(str, sizeof(str), inf)) {
			if ((err = do_asm(inf, str))) {
				fprintf(stderr, "ERROR assembly string\n");
				break;
			}
		}

		output_addr = 0;
		src_pass = 2;
		src_line = 1;

		if (fseek(inf, 0, SEEK_SET) == 0) {

			// Pass 2

			fprintf(stderr, "\n\nPass 2\n\n");

			while (fgets(str, sizeof(str), inf)) {
				if ((err = do_asm(inf, str))) {
					break;
				}
			}

			relink_refs();

			fprintf(stderr, "\nLabels:\n");
			dump_labels(labels);
			fprintf(stderr, "\nRefs:\n");
			dump_labels(refs);

			fprintf(stderr, "\nErrors: %d\n\n", error);

			if (out_type) {
				output_verilog();
			} else {
				output_hex();
			}
		} else {
			fprintf(stderr, "Source file IO error!\n");
		}

		fclose(inf);
	} else {
		fprintf(stderr, "Cannot open input file!\n");
		return -1;
	}

	return 0;
}
