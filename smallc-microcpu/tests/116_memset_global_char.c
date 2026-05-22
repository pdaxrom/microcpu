char buf[8];

char *memset(char *s, int c, int n);

int main()
{
    memset(buf, 65, 4);

    return buf[0] + buf[1] + buf[2] + buf[3] + buf[4];
}
