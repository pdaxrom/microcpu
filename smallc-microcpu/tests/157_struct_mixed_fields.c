struct Item {
    char c;
    int x;
};

struct Item item;

int main()
{
    item.c = 65;
    item.x = 10;

    return item.c + item.x;
}
