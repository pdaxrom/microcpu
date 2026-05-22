int main()
{
    int i;
    int s;

    i = 0;
    s = 0;

    do {
        s = s + i;
        i = i + 1;
    } while (i < 5);

    return s;
}
