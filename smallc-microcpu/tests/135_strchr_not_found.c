char *strchr(char *s, int c);

int main()
{
    char *p;

    p = strchr("ABC", 88);

    if (p == 0)
        return 1;

    return 0;
}
