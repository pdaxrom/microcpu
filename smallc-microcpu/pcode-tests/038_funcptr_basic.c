int f(int x)
{
    return x + 1;
}

int main()
{
    int (*fp)(int);

    fp = f;
    return (*fp)(37);
}
