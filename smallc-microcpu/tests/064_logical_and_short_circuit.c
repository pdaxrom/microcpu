int x;

int side()
{
    x = 99;
    return 1;
}

int main()
{
    x = 0;

    if (0 && side())
        return 1;

    return x;
}
