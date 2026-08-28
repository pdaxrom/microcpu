/* Reuse the upstream assertions and fixtures, not a second set of expected values.
 * Every exported instruction is reassembled with microasm11 before RTL replay.
 */
#include "core/core.h"
#include "core/disas.h"

static int capture_step(regs *r);
#define core_step capture_step
#define main upstream_core_tests_main
#include "tests/core_tests.c"
#undef main
#undef core_step

#if ENABLE_MMU
#error This runner requires ENABLE_MMU=0
#endif

static unsigned exported_steps;

static void json_string(const char *s)
{
    putchar('"');
    for (; *s; ++s) {
        if (*s == '"' || *s == '\\') putchar('\\');
        if (*s == '\t') fputs("\\t", stdout);
        else if (*s == '\n') fputs("\\n", stdout);
        else putchar(*s);
    }
    putchar('"');
}

static void export_registers(const regs *r)
{
    putchar('[');
    for (unsigned i = 0; i < 8; ++i) printf("%s%u", i ? "," : "", r->r[i]);
    printf(",%u]", r->psw);
}

static void export_banks(const regs *r, unsigned lazy_pop)
{
    /* C initializes an as-yet-unused SP bank on first switch, after RTI/RTT
     * has popped its frame. Seed that latent fixture state, not hardware's
     * zero-on-reset banks. The reference itself is not modified. */
    word initial = (word)(r->r[6] + lazy_pop);
    printf("[%u,%u,%u]", r->sp_mode_init ? r->sp_mode[0] : initial,
           r->sp_mode_init ? r->sp_mode[1] : initial,
           r->sp_mode_init ? r->sp_mode[3] : initial);
}

static void export_cpu_io(const regs *r)
{
    printf("[%u,%u,%u]", r->J11_CPUERR, r->J11_PIRQ, r->J11_CCR);
}

static void export_inactive_registers(const regs *r)
{
    unsigned inactive = ((r->psw >> 11) & 1) ^ 1;
    putchar('[');
    for (unsigned i = 0; i < 6; ++i)
        printf("%s%u", i ? "," : "",
               r->rset_bank_init ? r->rset_bank[inactive][i] : r->r[i]);
    putchar(']');
}

static void export_memory(const byte *mem)
{
    int first = 1;
    putchar('[');
    for (unsigned i = 0; i < 65536; ++i) {
        if (mem[i]) {
            printf("%s[%u,%u]", first ? "" : ",", i, mem[i]);
            first = 0;
        }
    }
    putchar(']');
}

static int capture_step(regs *r)
{
    char instruction[128];
    word pc = r->r[7], end = pc;
    word opcode = r->load_word(r, pc);
    if (r->model != DCJ11) {
        fprintf(stderr, "Non-J11 fixture selected: %s\n", current_test);
        exit(1);
    }
    if (r->fTrap) {
        fprintf(stderr, "SKIP RTL: %s (C-only fTrap injection, not architectural state)\n", current_test);
        return core_step(r);
    }
    disas(r, &end, instruction);
    /* Normalize two upstream disassembler spelling defects; byte-for-byte
     * reassembly below guards against hiding an actual instruction change.
     */
    if ((opcode & 0177700) == 0006400)
        snprintf(instruction, sizeof(instruction), "MARK %o", opcode & 077);
    if ((opcode & 0077700) == 0006500)
        memcpy(instruction, (opcode & 0100000) ? "MFPD" : "MFPI", 4);

    fputs("{\"name\":", stdout);
    json_string(current_test);
    fputs(",\"asm\":", stdout);
    json_string(instruction);
    printf(",\"pc\":%u,\"length\":%u,\"before\":", pc, (word)(end - pc));
    export_registers(r);
    fputs(",\"banks_before\":", stdout);
    export_banks(r, (opcode == 000002 || opcode == 000006) ? 4 : 0);
    fputs(",\"inactive_before\":", stdout);
    export_inactive_registers(r);
    fputs(",\"cpu_io_before\":", stdout);
    export_cpu_io(r);
    fputs(",\"memory_before\":", stdout);
    export_memory(r->hwstub_mem);
    printf(",\"wait_before\":%u", r->fWait);
    int rc = core_step(r);
    fputs(",\"after\":", stdout);
    export_registers(r);
    fputs(",\"banks_after\":", stdout);
    export_banks(r, 0);
    fputs(",\"inactive_after\":", stdout);
    export_inactive_registers(r);
    printf(",\"regset_valid\":%u", r->rset_bank_init);
    fputs(",\"cpu_io_after\":", stdout);
    export_cpu_io(r);
    fputs(",\"memory_after\":", stdout);
    export_memory(r->hwstub_mem);
    printf(",\"wait_after\":%u,\"banks_valid\":%u}\n", r->fWait, r->sp_mode_init);
    ++exported_steps;
    return rc;
}

int main(int argc, char **argv)
{
    int failed = 0;
    int banks = argc == 2 && strcmp(argv[1], "--banks") == 0;
    if (argc > 2 || (argc == 2 && !banks)) {
        fprintf(stderr, "Usage: %s [--banks]\n", argv[0]);
        return 2;
    }
#define MODEL_TEST(fn) failed += fn(DCJ11, "DCJ11")
    MODEL_TEST(test_extended_ops_supported_models);
    MODEL_TEST(test_eis_odd_register_cc_basis_model);
    MODEL_TEST(test_condition_codes_model);
    MODEL_TEST(test_branches_model);
    MODEL_TEST(test_jmp_model);
    MODEL_TEST(test_jmp_jsr_autoinc_mode2_model);
    MODEL_TEST(test_jmp_jsr_mode0_trap_model);
    MODEL_TEST(test_reg_source_order_split_model);
    MODEL_TEST(test_addressing_modes_model);
    MODEL_TEST(test_single_operand_word_ops_model);
    MODEL_TEST(test_single_operand_byte_ops_model);
    MODEL_TEST(test_misc_ops_model);
    MODEL_TEST(test_double_operand_word_ops_model);
    MODEL_TEST(test_double_operand_byte_ops_model);
    MODEL_TEST(test_emt_trap_ignore_code_model);
    failed += test_dcj11_special_ops();
    failed += test_dcj11_tstset_wrtlck_mode0_illegal();
    failed += test_dcj11_alignment_trap();
    failed += test_dcj11_alignment_trap_store();
    failed += test_dcj11_alignment_trap_fetch();
    failed += test_dcj11_rti_traces_immediately_when_t_restored();
    failed += test_dcj11_rtt_traces_after_one_instruction();
    failed += test_dcj11_rti_restores_state();
    failed += test_dcj11_tstb_flags();
    failed += test_dcj11_bpl_after_tstb();
    failed += test_dcj11_bpl_after_tstb_neg();
    failed += test_dcj11_bpt_stack_order();
    failed += test_dcj11_iot_stack_order();
    failed += test_dcj11_bus_error_stack_order();
    failed += test_dcj11_spl_kernel_sets_priority();
    failed += test_dcj11_spl_user_is_nop();
    failed += test_dcj11_mtps_user_restricts_psw();
    failed += test_dcj11_explicit_psw_write_preserves_t();
    failed += test_dcj11_mov_to_psw_keeps_written_cc();
    failed += test_dcj11_regblock_177752_177766_core_owned();
    failed += test_dcj11_yellow_stack_trap_autodec_sp();
    failed += test_dcj11_yellow_stack_trap_on_bpt_push();
    failed += test_dcj11_stack_limit_boundary_no_trap();
    failed += test_dcj11_trace_priority_over_yellow_stack();
    if (banks) {
        failed += test_dcj11_mode_stack_banking();
        failed += test_dcj11_register_set_banking();
        failed += test_dcj11_rti_user_sets_high_psw_bits();
        failed += test_dcj11_mxpi_prev_mode2_uses_user_sp();
        failed += test_dcj11_rti_user_restricts_psw();
    }
#undef MODEL_TEST
    fprintf(stderr, "%s: J-11 no-MMU core assertions; %u instruction snapshots\n",
            failed ? "FAIL" : "PASS", exported_steps);
    return failed ? 1 : 0;
}
