int arr[4];

int main()
{
    int *p;

    arr[0] = 3;
    arr[1] = 4;
    arr[2] = 5;

    p = arr;

    return p[0] + p[1] + p[2];
}
