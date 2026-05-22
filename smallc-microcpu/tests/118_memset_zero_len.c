char buf[4] = { 1, 2, 3, 4 };

char *memset(char *s, int c, int n);

int main()
{
    memset(buf, 99, 0);

    return buf[0] + buf[1] + buf[2] + buf[3];
}
