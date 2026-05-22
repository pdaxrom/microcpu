int arr[3];

int main()
{
    int *p;

    arr[0] = 10;
    arr[1] = 20;

    p = arr;

    return *(p + 1);
}
