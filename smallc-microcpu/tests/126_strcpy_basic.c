char dst[8];

char *strcpy(char *dst, char *src);

int main()
{
    strcpy(dst, "ABC");

    return dst[0] + dst[1] + dst[2] + dst[3];
}
