struct Point {
    int x;
    int y;
};

int main()
{
    struct Point p;
    struct Point *q;

    q = &p;

    q->x = 7;
    q->y = 8;

    return p.x + p.y;
}
