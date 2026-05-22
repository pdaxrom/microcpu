#define VALUE(x) 1
#undef VALUE
#define VALUE(x) x

int main()
{
    return VALUE(180);
}
