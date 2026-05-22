int f(int x)
{
    return x + 1;
}

int (*gfp)(int);

int main()
{
    gfp = f;
    return (*gfp)(230);
}
