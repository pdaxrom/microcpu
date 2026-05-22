int add1(int x)
{
    return x + 1;
}

int (*gfp)(int);

int main()
{
    gfp = add1;
    return (*gfp)(40);
}
