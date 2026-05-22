int second(char **p)
{
    return p[0][1];
}

int main()
{
    char *v[2];

    v[0] = "ABC";
    v[1] = "XYZ";

    return second(v);
}
