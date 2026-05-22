struct Point {
    int x;
    int y;
};

struct Point p;

int main()
{
    struct Point *q;

    q = &p;
    q->x = 20;
    q->y = 8;

    return p.x + p.y;
}
