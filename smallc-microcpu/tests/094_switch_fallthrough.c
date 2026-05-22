int main()
{
    int x;
    int y;

    x = 1;
    y = 0;

    switch (x) {
    case 1:
        y = y + 10;
    case 2:
        y = y + 20;
        break;
    default:
        y = y + 30;
        break;
    }

    return y;
}
