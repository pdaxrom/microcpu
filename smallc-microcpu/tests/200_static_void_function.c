static int x;

static void setx(void)
{
    x = 200;
}

int main()
{
    setx();
    return x;
}
