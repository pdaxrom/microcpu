struct Point {
    int x;
    int y;
};

struct Point arr[2];

int main()
{
    struct Point *p;

    arr[0].x = 1;
    arr[0].y = 2;
    arr[1].x = 3;
    arr[1].y = 4;

    p = arr;

    return (p + 1)->x;
}
