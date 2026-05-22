char a[4] = { 1, 2, 3, 4 };
char b[4] = { 9, 9, 9, 9 };

int memcmp(char *a, char *b, int n);

int main()
{
    return memcmp(a, b, 0);
}
