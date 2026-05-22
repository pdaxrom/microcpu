int x;

int side()
{
    x = 99;
    return 1;
}

int main()
{
    x = 0;

    if (1 || side())
        return x + 13;

    return 0;
}
