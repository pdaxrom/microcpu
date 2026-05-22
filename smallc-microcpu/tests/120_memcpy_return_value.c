char src[4] = { 5, 6, 7, 8 };
char dst[4];

char *memcpy(char *dst, char *src, int n);

int main()
{
    char *p;

    p = memcpy(dst, src, 4);

    if (p == dst)
        return dst[0] + dst[1] + dst[2] + dst[3];

    return 999;
}
