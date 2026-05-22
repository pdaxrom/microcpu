int strcmp(char *a, char *b);

int main()
{
    if (strcmp("ABC", "ABCD") < 0)
        return 1;

    return 0;
}
