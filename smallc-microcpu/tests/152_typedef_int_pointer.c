typedef int *intptr;

int g;

int main()
{
    intptr p;

    g = 77;
    p = &g;

    return *p;
}
