static int x;

static void setx(
    int v
)
{
    x = v;
}

int main()
{
    setx(204);
    return x;
}
