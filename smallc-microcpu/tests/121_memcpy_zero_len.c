char src[4] = { 9, 9, 9, 9 };
char dst[4] = { 1, 2, 3, 4 };

char *memcpy(char *dst, char *src, int n);

int main()
{
    memcpy(dst, src, 0);

    return dst[0] + dst[1] + dst[2] + dst[3];
}
