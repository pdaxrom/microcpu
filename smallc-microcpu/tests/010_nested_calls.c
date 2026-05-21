int add(int a, int b)
{
    return a + b;
}

int main()
{
    return add(add(1, 2), add(3, 4));
}
