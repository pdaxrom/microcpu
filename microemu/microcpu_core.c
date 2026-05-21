#include "microcpu_core.h"

#include <inttypes.h>
#include <string.h>

enum {
    INST_LDRL = 0x0,
    INST_STRL = 0x1,
    INST_LDR = 0x2,
    INST_STR = 0x3,
    INST_SETL = 0x4,
    INST_SETH = 0x5,
    INST_MOVL = 0x6,
    INST_MOVH = 0x7,
    INST_MOV = 0x8,
    INST_SWS = 0x9,
    INST_SWU = 0xa,
    INST_B = 0xb,
    INST_SETP = 0xc,
    INST_GETP = 0xd,
    INST_NOPE = 0xe,
    INST_NOPF = 0xf,
};

enum {
    ALU_CMP = 0x0,
    ALU_BIT = 0x1,
    ALU_SEXT = 0x4,
    ALU_ADD = 0x8,
    ALU_SUB = 0x9,
    ALU_SHL = 0xa,
    ALU_SHR = 0xb,
    ALU_AND = 0xc,
    ALU_OR = 0xd,
    ALU_INV = 0xe,
    ALU_XOR = 0xf,
};

enum {
    CMP_EQ = 0,
    CMP_NE = 1,
    CMP_MI = 2,
    CMP_VS = 3,
    CMP_LT = 4,
    CMP_GE = 5,
    CMP_LTU = 6,
    CMP_GEU = 7,
};

void microcpu_init(microcpu_t *cpu, microcpu_bus_t bus)
{
    memset(cpu, 0, sizeof(*cpu));
    cpu->bus = bus;
}

static uint8_t bus_read(microcpu_t *cpu, uint16_t addr)
{
    if (cpu->bus.read == NULL) {
        return 0;
    }
    return cpu->bus.read(cpu->bus.ctx, addr);
}

static void bus_write(microcpu_t *cpu, uint16_t addr, uint8_t value)
{
    if (cpu->bus.write != NULL) {
        cpu->bus.write(cpu->bus.ctx, addr, value);
    }
}

static bool bus_intr(microcpu_t *cpu)
{
    return cpu->bus.intr != NULL && cpu->bus.intr(cpu->bus.ctx);
}

static uint16_t reg_read(const microcpu_t *cpu, unsigned reg, uint16_t exec_pc)
{
    return reg == 0 ? exec_pc : cpu->r[reg & 7u];
}

static uint16_t write_low(uint16_t old_value, uint8_t value)
{
    return (uint16_t)((old_value & 0xff00u) | value);
}

static uint16_t write_high(uint16_t old_value, uint8_t value)
{
    return (uint16_t)(((uint16_t)value << 8) | (old_value & 0x00ffu));
}

static int16_t sign_extend11(unsigned value)
{
    value &= 0x7ffu;
    if (value & 0x400u) {
        value |= ~0x7ffu;
    }
    return (int16_t)value;
}

static bool cmp_condition(unsigned cond, uint32_t acc, uint16_t lhs, uint16_t rhs)
{
    uint16_t result = (uint16_t)acc;
    bool flag_z = result == 0;
    bool flag_c = (acc & 0x10000u) != 0;
    bool flag_n = (result & 0x8000u) != 0;
    bool flag_v = (((lhs ^ rhs) & (lhs ^ result) & 0x8000u) != 0);

    switch (cond & 7u) {
    case CMP_EQ:
        return flag_z;
    case CMP_NE:
        return !flag_z;
    case CMP_MI:
        return flag_n;
    case CMP_VS:
        return flag_v;
    case CMP_LT:
        return flag_n ^ flag_v;
    case CMP_GE:
        return !(flag_n ^ flag_v);
    case CMP_LTU:
        return flag_c;
    case CMP_GEU:
        return !flag_c;
    default:
        return false;
    }
}

static uint32_t alu_compute(unsigned kind, uint16_t lhs, uint16_t rhs)
{
    switch (kind) {
    case ALU_SEXT:
        return (lhs & 0x80u) ? (uint32_t)(0xff00u | (lhs & 0xffu)) :
            (uint32_t)(lhs & 0xffu);
    case ALU_ADD:
        return (uint32_t)lhs + (uint32_t)rhs;
    case ALU_CMP:
    case ALU_SUB:
        return ((uint32_t)lhs - (uint32_t)rhs) & 0x1ffffu;
    case ALU_SHL:
        return rhs >= 17u ? 0 : (((uint32_t)lhs << rhs) & 0x1ffffu);
    case ALU_SHR:
        return rhs >= 17u ? 0 : ((uint32_t)lhs >> rhs);
    case ALU_BIT:
    case ALU_AND:
        return (uint32_t)(lhs & rhs);
    case ALU_OR:
        return (uint32_t)(lhs | rhs);
    case ALU_INV:
        return (uint32_t)((~lhs) & 0xffffu);
    case ALU_XOR:
        return (uint32_t)(lhs ^ rhs);
    default:
        return 0;
    }
}

static void trace_instruction(const microcpu_t *cpu, FILE *out, uint64_t step,
    uint16_t pc, uint8_t op_byte, uint8_t arg_byte)
{
    fprintf(out,
        "%08" PRIu64 " pc=%04x insn=%02x %02x "
        "r0=%04x r1=%04x r2=%04x r3=%04x "
        "r4=%04x r5=%04x r6=%04x r7=%04x mode=%c\n",
        step, pc, op_byte, arg_byte,
        cpu->r[0], cpu->r[1], cpu->r[2], cpu->r[3],
        cpu->r[4], cpu->r[5], cpu->r[6], cpu->r[7],
        cpu->super_mode ? 'S' : 'U');
}

microcpu_step_result_t microcpu_step(microcpu_t *cpu, uint64_t step,
    const microcpu_step_options_t *options, unsigned *cycles)
{
    uint16_t pc = cpu->r[0];
    uint16_t exec_pc;
    uint16_t next_pc;
    uint8_t op_byte;
    uint8_t arg_byte;
    unsigned op5;
    unsigned dest;
    unsigned kind;
    unsigned arg1;
    unsigned arg2;
    unsigned const4;
    bool is_const4;
    uint16_t lhs;
    uint16_t rhs;
    uint32_t acc;
    bool trace = options != NULL && options->trace;
    bool stop_on_self_branch = options != NULL && options->stop_on_self_branch;
    FILE *trace_file = options != NULL && options->trace_file != NULL ?
        options->trace_file : stderr;

    *cycles = 2;

    if ((pc & 1u) == 0 && !cpu->super_mode &&
        (cpu->super_mode_req || bus_intr(cpu))) {
        cpu->user_pc = pc;
        cpu->r[0] = 0x0002u;
        cpu->super_mode = true;
        *cycles = 1;
        return MICROCPU_STEP_OK;
    }

    if (pc & 1u) {
        fprintf(stderr, "microcpu: pc is odd at instruction boundary: %04x\n", pc);
        return MICROCPU_STEP_ERROR;
    }

    op_byte = bus_read(cpu, pc);
    arg_byte = bus_read(cpu, (uint16_t)(pc + 1u));
    op5 = op_byte >> 3;
    dest = op_byte & 7u;
    kind = op5 >> 1;
    arg1 = arg_byte >> 5;
    arg2 = (arg_byte >> 2) & 7u;
    const4 = (arg_byte >> 1) & 0x0fu;
    is_const4 = (arg_byte & 1u) != 0;
    exec_pc = (uint16_t)(pc + 1u);
    next_pc = (uint16_t)(pc + 2u);

    if (trace) {
        trace_instruction(cpu, trace_file, step, pc, op_byte, arg_byte);
    }

    if ((op5 & 1u) == 0) {
        switch (kind) {
        case INST_LDRL:
        case INST_STRL:
        case INST_LDR:
        case INST_STR: {
            uint16_t base = reg_read(cpu, arg1, exec_pc);
            uint16_t offset = is_const4 ? (uint16_t)const4 :
                reg_read(cpu, arg2, exec_pc);
            uint16_t addr = (uint16_t)(base + offset);
            bool word = kind == INST_LDR || kind == INST_STR;

            *cycles = word ? 5u : 3u;
            if (kind == INST_LDRL) {
                uint8_t value = bus_read(cpu, addr);
                if (dest == 0) {
                    next_pc = write_low(next_pc, value);
                } else {
                    cpu->r[dest] = write_low(cpu->r[dest], value);
                }
            } else if (kind == INST_LDR) {
                uint8_t low = bus_read(cpu, addr);
                uint8_t high = bus_read(cpu, (uint16_t)(addr + 1u));
                uint16_t value = (uint16_t)(low | ((uint16_t)high << 8));
                if (dest == 0) {
                    next_pc = value;
                } else {
                    cpu->r[dest] = value;
                }
            } else if (kind == INST_STRL) {
                bus_write(cpu, addr, (uint8_t)(reg_read(cpu, dest, exec_pc) & 0xffu));
            } else {
                uint16_t value = reg_read(cpu, dest, exec_pc);
                bus_write(cpu, addr, (uint8_t)(value & 0xffu));
                bus_write(cpu, (uint16_t)(addr + 1u), (uint8_t)(value >> 8));
            }
            break;
        }
        case INST_SETL:
            if (dest == 0) {
                next_pc = write_low(next_pc, arg_byte);
            } else {
                cpu->r[dest] = write_low(cpu->r[dest], arg_byte);
            }
            break;
        case INST_SETH:
            if (dest == 0) {
                next_pc = write_high(next_pc, arg_byte);
            } else {
                cpu->r[dest] = write_high(cpu->r[dest], arg_byte);
            }
            break;
        case INST_MOVL:
            if (dest == 0) {
                next_pc = write_low(next_pc, (uint8_t)reg_read(cpu, arg1, exec_pc));
            } else {
                cpu->r[dest] = write_low(cpu->r[dest],
                    (uint8_t)reg_read(cpu, arg1, exec_pc));
            }
            break;
        case INST_MOVH:
            if (dest == 0) {
                next_pc = write_high(next_pc, (uint8_t)reg_read(cpu, arg1, exec_pc));
            } else {
                cpu->r[dest] = write_high(cpu->r[dest],
                    (uint8_t)reg_read(cpu, arg1, exec_pc));
            }
            break;
        case INST_MOV:
            if (dest == 0) {
                next_pc = reg_read(cpu, arg1, exec_pc);
            } else {
                cpu->r[dest] = reg_read(cpu, arg1, exec_pc);
            }
            break;
        case INST_SWS:
            cpu->super_mode_req = true;
            break;
        case INST_SWU:
            next_pc = cpu->user_pc;
            cpu->super_mode = false;
            cpu->super_mode_req = false;
            break;
        case INST_B: {
            int16_t rel = sign_extend11((dest << 8) | arg_byte);
            next_pc = (uint16_t)((exec_pc & 0xfffeu) + ((int32_t)rel * 2));
            if (stop_on_self_branch && next_pc == pc) {
                cpu->r[0] = next_pc;
                return MICROCPU_STEP_SELF_BRANCH;
            }
            break;
        }
        case INST_SETP:
            cpu->user_pc = reg_read(cpu, dest, exec_pc);
            break;
        case INST_GETP:
            if (dest == 0) {
                next_pc = cpu->user_pc;
            } else {
                cpu->r[dest] = cpu->user_pc;
            }
            break;
        case INST_NOPE:
        case INST_NOPF:
            break;
        default:
            fprintf(stderr, "microcpu: unknown non-ALU opcode %u at %04x\n", kind, pc);
            return MICROCPU_STEP_ERROR;
        }
        cpu->r[0] = next_pc;
        return MICROCPU_STEP_OK;
    }

    lhs = reg_read(cpu, arg1, exec_pc);
    rhs = is_const4 ? (uint16_t)const4 : reg_read(cpu, arg2, exec_pc);
    acc = alu_compute(kind, lhs, rhs);
    *cycles = 4;

    if (kind == ALU_CMP || kind == ALU_BIT) {
        if (cmp_condition(dest, acc, lhs, rhs)) {
            next_pc = (uint16_t)(next_pc + 2u);
        }
        cpu->r[0] = next_pc;
        return MICROCPU_STEP_OK;
    }

    switch (kind) {
    case ALU_SEXT:
    case ALU_ADD:
    case ALU_SUB:
    case ALU_SHL:
    case ALU_SHR:
    case ALU_AND:
    case ALU_OR:
    case ALU_INV:
    case ALU_XOR:
        if (dest == 0) {
            next_pc = (uint16_t)acc;
        } else {
            cpu->r[dest] = (uint16_t)acc;
        }
        cpu->r[0] = next_pc;
        return MICROCPU_STEP_OK;
    default:
        fprintf(stderr, "microcpu: unknown ALU opcode %u at %04x\n", kind, pc);
        return MICROCPU_STEP_ERROR;
    }
}

void microcpu_dump_regs(const microcpu_t *cpu, FILE *out)
{
    if (out == NULL) {
        out = stderr;
    }
    fprintf(out,
        "\nr0=%04x r1=%04x r2=%04x r3=%04x r4=%04x r5=%04x r6=%04x r7=%04x\n"
        "user_pc=%04x mode=%s super_req=%u\n",
        cpu->r[0], cpu->r[1], cpu->r[2], cpu->r[3],
        cpu->r[4], cpu->r[5], cpu->r[6], cpu->r[7],
        cpu->user_pc, cpu->super_mode ? "super" : "user",
        cpu->super_mode_req ? 1u : 0u);
}
