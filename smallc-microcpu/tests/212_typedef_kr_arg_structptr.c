struct Point {
    int x;
    int y;
};

typedef struct Point *PointPtr;

int sum(p)
PointPtr p;
{
    return p->x + p->y;
}

int main()
{
    struct Point p;

    p.x = 100;
    p.y = 112;

    return sum(&p);
}
