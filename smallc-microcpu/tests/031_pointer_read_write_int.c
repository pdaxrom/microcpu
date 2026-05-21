int g;

int main()
{
    int *p;

    p = &g;
    *p = 10;
    *p = *p + 5;

    return g;
}
