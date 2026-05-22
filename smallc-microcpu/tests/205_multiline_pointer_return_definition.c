char *id(
    char *s
)
{
    return s;
}

int main()
{
    char *p;

    p = id("ABC");
    return p[0] + 140;
}
