struct Point {
    int x;
    int y;
};

typedef struct Point *PointPtr;

struct Point p;

int main()
{
    PointPtr q;

    q = &p;

    q->x = 14;
    q->y = 15;

    return p.x + p.y;
}
