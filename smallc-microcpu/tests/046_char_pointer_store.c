char buf[4];

int main()
{
    char *p;

    p = buf;
    p[0] = 80;
    p[1] = 81;

    return buf[0] + buf[1];
}
