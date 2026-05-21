#ifndef MICROCPU_CORE_H
#define MICROCPU_CORE_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

typedef uint8_t (*microcpu_bus_read_fn)(void *ctx, uint16_t addr);
typedef void (*microcpu_bus_write_fn)(void *ctx, uint16_t addr, uint8_t value);
typedef bool (*microcpu_bus_intr_fn)(void *ctx);

typedef struct {
    void *ctx;
    microcpu_bus_read_fn read;
    microcpu_bus_write_fn write;
    microcpu_bus_intr_fn intr;
} microcpu_bus_t;

typedef struct {
    uint16_t r[8];
    uint16_t user_pc;
    bool super_mode_req;
    bool super_mode;
    microcpu_bus_t bus;
} microcpu_t;

typedef enum {
    MICROCPU_STEP_OK = 0,
    MICROCPU_STEP_SELF_BRANCH,
    MICROCPU_STEP_ERROR,
} microcpu_step_result_t;

typedef struct {
    bool trace;
    bool stop_on_self_branch;
    FILE *trace_file;
} microcpu_step_options_t;

void microcpu_init(microcpu_t *cpu, microcpu_bus_t bus);
microcpu_step_result_t microcpu_step(microcpu_t *cpu, uint64_t step,
    const microcpu_step_options_t *options, unsigned *cycles);
void microcpu_dump_regs(const microcpu_t *cpu, FILE *out);

#endif
