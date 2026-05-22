char *strchr(char *s, int c);

int main()
{
    char *s;
    char *p;

    s = "ABC";
    p = strchr(s, 66);

    return *p;
}
