char buf[8];

char *memset(char *s, int c, int n);

int main()
{
    char *p;

    p = memset(buf, 66, 3);

    if (p == buf)
        return buf[0] + buf[1] + buf[2];

    return 999;
}
