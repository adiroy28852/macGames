/* Report the x86 instruction-set extensions a Windows program sees (CPUID),
 * e.g. whether Rosetta advertises AVX/AVX2. Run by `macgames doctor`. */
#include <cpuid.h>
#include <stdio.h>

int main(void)
{
    unsigned a, b, c, d, xcr0 = 0;
    __cpuid(1, a, b, c, d);
    int osxsave = (c >> 27) & 1;
    if (osxsave) __asm__ volatile("xgetbv" : "=a"(xcr0) : "c"(0) : "edx");
    int avx = ((c >> 28) & 1) && (xcr0 & 6) == 6;
    printf("SSE4.2 %s  F16C %s  FMA %s  AVX %s", (c >> 20) & 1 ? "yes" : "no",
           (c >> 29) & 1 ? "yes" : "no", (c >> 12) & 1 ? "yes" : "no", avx ? "yes" : "no");
    __cpuid_count(7, 0, a, b, c, d);
    printf("  AVX2 %s  BMI2 %s  AVX-512 %s\n", avx && ((b >> 5) & 1) ? "yes" : "no",
           (b >> 8) & 1 ? "yes" : "no", (b >> 16) & 1 ? "yes" : "no");
    return 0;
}
