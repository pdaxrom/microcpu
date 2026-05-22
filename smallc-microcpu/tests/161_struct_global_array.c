struct Point {
    int x;
    int y;
};

struct Point arr[2];

int main()
{
    arr[0].x = 1;
    arr[0].y = 2;
    arr[1].x = 3;
    arr[1].y = 4;

    return arr[0].x + arr[0].y + arr[1].x + arr[1].y;
}
