int arr[4];

int main()
{
    int *p;

    arr[0] = 11;
    arr[1] = 22;

    p = arr;

    return *(p + 1);
}
