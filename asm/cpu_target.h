#ifndef MICROASM_CPU_TARGET_H
#define MICROASM_CPU_TARGET_H

#include <string.h>

/* Stable IDs at offset 0x10 in version-2+ objects. Legacy version-1 objects
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

/* v3 introduced compact CALL/JMP; v4 adds CBZ/CBNZ and ADC/SBC. Older tools
 * must reject v4 instead of interpreting the new GETF escape as a register write. */
static inline unsigned int cpu_object_version(int cpu)
{
    return cpu == CPU_ORIGINAL ? 1 : cpu == CPU_J11 ? 2 : 4;
}

static inline int cpu_object_supported(unsigned int version, int cpu)
{
    return cpu >= 0 && cpu < CPU_COUNT &&
        (version == cpu_object_version(cpu) || (version == 2 && cpu == CPU_ORIGINAL) ||
         (version == 3 && cpu == CPU_UCODE));
}

#endif
