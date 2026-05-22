struct Point {
    int x;
    int y;
};

struct Point p;

int main()
{
    struct Point *q;

    p.x = 3;
    p.y = 4;

    q = &p;

    return (*q).x + (*q).y;
}
