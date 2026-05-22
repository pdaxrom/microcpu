int main()
{
    int i;
    int j;
    int s;

    s = 0;

    for (i = 0; i < 3; i = i + 1) {
        for (j = 0; j < 4; j = j + 1) {
            if (j == 1)
                continue;
            s = s + 1;
        }
    }

    return s;
}
