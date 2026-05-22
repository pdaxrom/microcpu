int main()
{
    int i;
    int s;

    s = 0;

    for (i = 0; i < 10; i = i + 1) {
        if (i == 5)
            break;
        s = s + i;
    }

    return s;
}
