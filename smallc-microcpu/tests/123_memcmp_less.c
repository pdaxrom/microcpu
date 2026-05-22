char a[4] = { 1, 2, 3, 4 };
char b[4] = { 1, 2, 9, 4 };

int memcmp(char *a, char *b, int n);

int main()
{
    if (memcmp(a, b, 4) < 0)
        return 1;

    return 0;
}
