struct Point {
    int x;
    int y;
};

struct Point p;

int main()
{
    struct Point *q;

    q = &p;

    q->x = 5;
    q->y = 6;

    return p.x + p.y;
}
