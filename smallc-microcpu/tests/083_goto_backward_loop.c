int main()
{
    int i;
    int s;

    i = 0;
    s = 0;

loop:
    if (i >= 5)
        goto done;

    s = s + i;
    i = i + 1;
    goto loop;

done:
    return s;
}
