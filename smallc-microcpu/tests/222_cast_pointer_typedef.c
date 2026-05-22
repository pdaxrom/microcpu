#include <stdint.h>

int main()
{
    char *s;
    char *p;

    s = "ABC";
    p = (char *)(uintptr_t)s;

    return p[1] + 156;
}
