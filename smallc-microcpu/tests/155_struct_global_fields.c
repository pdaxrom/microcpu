struct Point {
    int x;
    int y;
};

struct Point p;

int main()
{
    p.x = 10;
    p.y = 20;

    return p.x + p.y;
}
