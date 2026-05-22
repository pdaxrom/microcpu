int getchar();
int putchar(int c);

int main()
{
    int c;
    int n;

    n = 0;

    while (1) {
        c = getchar();
        if (c == '\n')
            break;

        putchar(c);
        n = n + 1;
    }

    return n;
}
