int x;

void add(int v)
{
    x = x + v;
}

int main()
{
    x = 0;
    add(100);
    add(97);

    return x;
}
