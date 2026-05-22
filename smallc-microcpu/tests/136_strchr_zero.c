char *strchr(char *s, int c);

int main()
{
    char *s;
    char *p;

    s = "ABC";
    p = strchr(s, 0);

    if (*p == 0)
        return 1;

    return 0;
}
