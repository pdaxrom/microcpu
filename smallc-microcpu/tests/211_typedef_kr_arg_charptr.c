typedef char *str;

int f(s)
str s;
{
    return s[1];
}

int main()
{
    return f("ABC");
}
