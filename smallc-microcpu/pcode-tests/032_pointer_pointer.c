int main()
{
    int x;
    int *p;
    int **pp;

    x = 32;
    p = &x;
    pp = &p;

    return **pp;
}
