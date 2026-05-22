int strcmp(char *a, char *b);

int main()
{
    if (strcmp("ABC", "ABD") < 0)
        return 1;

    return 0;
}
