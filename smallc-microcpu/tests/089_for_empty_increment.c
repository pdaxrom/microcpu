int main()
{
    int i;
    int s;

    i = 0;
    s = 0;

    for (; i < 5;) {
        s = s + i;
        i = i + 1;
    }

    return s;
}
