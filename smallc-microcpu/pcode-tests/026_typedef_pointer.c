typedef int *intptr;

int g;

int main()
{
    intptr p;

    g = 26;
    p = &g;

    return *p;
}
