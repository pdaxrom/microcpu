int addone(x)
int x;
{
    return x + 1;
}

int callit(fn, x)
int (*fn)();
int x;
{
    return (*fn)(x);
}

int main()
{
    return callit(addone, 228);
}
