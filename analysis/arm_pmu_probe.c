/* PMU event probe (analysis/arm_pmu_probe.sh): mode 0 = random 8-way indirect branch,
 * 1 = random conditional branch, 2 = indirect branch with a period-8 (predictable) pattern.  N iterations.
 * An event counting ~7/8 N in mode 0 and ~0 in modes 1 and 2 counts indirect mispredictions
 * (Oryon: raw 0x8117; results/analysis/arm_pmu_scan_galaxy-s25edge.txt). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define N 8000000
#define M ((1 << 20) - 1)
static unsigned char r[M + 1];

int main(int argc, char **argv)
{
    int mode = argc > 1 ? atoi(argv[1]) : 0;
    uint32_t x = 12345;
    for (int i = 0; i <= M; i++) {
        x = x * 1664525u + 1013904223u;
        r[i] = mode == 2 ? (i & 7) : (x >> 24) & 7;
    }
    uint64_t s = 0;
    int k = 0;
    if (mode == 1) {
        for (k = 0; k < N; k++) {
            if (r[k & M] & 1) { s += k; __asm__ volatile("nop" ::: "memory"); }
            else              { s ^= k; __asm__ volatile("nop\n\tnop\n\tnop" ::: "memory"); }
        }
        goto done;
    }
    static void *T[8] = { &&a0, &&a1, &&a2, &&a3, &&a4, &&a5, &&a6, &&a7 };
    goto *T[r[0]];
a0: s += 1; goto next;
a1: s ^= 3; goto next;
a2: s += 5; goto next;
a3: s ^= 7; goto next;
a4: s += 11; goto next;
a5: s ^= 13; goto next;
a6: s += 17; goto next;
a7: s ^= 19; goto next;
next:
    if (++k == N) goto done;
    goto *T[r[k & M]];
done:
    printf("%llu\n", (unsigned long long)s);
    return 0;
}
