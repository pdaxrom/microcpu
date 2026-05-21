int g;

int main()
{
    int *p;

    p = &g;
    *p = 123;

    return g;
}
