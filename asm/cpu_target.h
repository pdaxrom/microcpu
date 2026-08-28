#ifndef MICROASM_CPU_TARGET_H
#define MICROASM_CPU_TARGET_H

#include <string.h>

/* Stable IDs at offset 0x10 in version-2 objects. Legacy version-1 objects
 * are always original CPU; their reserved header fields stay uninterpreted. */
enum { CPU_ORIGINAL = 0, CPU_J11, CPU_UCODE, CPU_COUNT };

#define CPU_MASK(cpu) (1u << (cpu))
#define CPU_ALL ((1u << CPU_COUNT) - 1)
#define CPU_ENGINES (CPU_MASK(CPU_J11) | CPU_MASK(CPU_UCODE))

static inline const char *cpu_name(int cpu)
{
    static const char *names[] = { "original", "j11", "ucode" };
    return cpu >= 0 && cpu < CPU_COUNT ? names[cpu] : "unknown";
}

static inline int parse_cpu(const char *name)
{
    for (int cpu = 0; cpu < CPU_COUNT; cpu++) {
        if (!strcmp(name, cpu_name(cpu))) return cpu;
    }
    return -1;
}

#endif
