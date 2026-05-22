struct Point {
    int x;
    int y;
};

int main()
{
    struct Point arr[2];

    arr[0].x = 10;
    arr[0].y = 20;
    arr[1].x = 30;
    arr[1].y = 40;

    return arr[0].x + arr[1].y;
}
