int main()
{
    int i;
    int s;

    s = 0;

    for (i = 0; i < 5; i = i + 1) {
        if (i == 2)
            continue;
        s = s + i;
    }

    return s;
}
