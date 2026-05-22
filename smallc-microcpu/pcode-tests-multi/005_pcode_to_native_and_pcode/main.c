int add(int a, int b);
int native_mul2(int x);

int main()
{
    return native_mul2(add(10, 11));
}
