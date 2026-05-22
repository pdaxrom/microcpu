#define HAVE_X
#ifdef HAVE_X
#define VALUE 44
#else
#define VALUE 99
#endif
int main()
{
    return VALUE;
}
