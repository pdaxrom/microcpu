int main()
{
    int x;
    int *p;
    int **pp;

    x = 208;
    p = &x;
    pp = &p;

    return **pp;
}
