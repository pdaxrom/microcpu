char dst[8];

char *strcpy(char *dst, char *src);

int main()
{
    char *p;

    p = strcpy(dst, "XY");

    if (p == dst)
        return dst[0] + dst[1] + dst[2];

    return 999;
}
