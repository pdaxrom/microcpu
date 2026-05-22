int main()
{
    char *s;
    char **pp;

    s = "ABC";
    pp = &s;

    return (*pp)[2];
}
