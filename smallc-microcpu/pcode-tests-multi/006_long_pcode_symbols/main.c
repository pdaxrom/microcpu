int very_long_pcode_function_alpha();
int very_long_pcode_function_beta();

extern int very_long_pcode_global_alpha;
extern int very_long_pcode_global_beta;

int main()
{
    return very_long_pcode_function_alpha()
         + very_long_pcode_function_beta()
         + very_long_pcode_global_alpha
         + very_long_pcode_global_beta;
}
