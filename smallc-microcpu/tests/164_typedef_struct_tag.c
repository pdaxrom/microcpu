struct Point {
    int x;
    int y;
};

typedef struct Point Point;

int main()
{
    Point p;

    p.x = 12;
    p.y = 13;

    return p.x + p.y;
}
