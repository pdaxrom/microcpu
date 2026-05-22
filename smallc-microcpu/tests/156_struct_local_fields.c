struct Point {
    int x;
    int y;
};

int main()
{
    struct Point p;

    p.x = 11;
    p.y = 22;

    return p.x + p.y;
}
