int add1(int x);

int main()
{
    int (*fp)(int);

    fp = add1;
    return (*fp)(144);
}
