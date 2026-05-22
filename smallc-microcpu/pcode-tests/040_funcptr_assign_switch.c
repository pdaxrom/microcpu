int add1(int x)
{
    return x + 1;
}

int add2(int x)
{
    return x + 2;
}

int main()
{
    int (*fp)(int);
    int k;

    k = 1;

    if (k)
        fp = add2;
    else
        fp = add1;

    return (*fp)(38);
}
