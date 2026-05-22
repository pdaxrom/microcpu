int main()
{
    int x;
    int y;
    int *p;
    int **pp;

    x = 1;
    y = 209;

    p = &x;
    pp = &p;

    *pp = &y;

    return **pp;
}
