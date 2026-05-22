int main()
{
    int x;
    int y;

    x = 2;
    y = 0;

    switch (x) {
    case 1:
        y = 10;
        break;
    case 2:
        y = 20;
        break;
    default:
        y = 30;
        break;
    }

    return y;
}
