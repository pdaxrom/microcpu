int putchar(int c);

int main()
{
    char *s;
    int i;

    s = "XYZ";
    i = 0;

    while (s[i]) {
        putchar(s[i]);
        i = i + 1;
    }

    return i;
}
