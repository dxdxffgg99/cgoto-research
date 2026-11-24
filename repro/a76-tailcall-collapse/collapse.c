/*
 * Reproducer: layout-dependent indirect-branch misprediction of clang's merged
 * tail-call dispatch on Cortex-A76.  A tiny bytecode VM (Collatz steps) whose handlers
 * dispatch with __attribute__((musttail)) calls through a table.  In jeven, clang -O2 joins the
 * two outcomes of a data-dependent condition into ONE indirect branch, reached by two
 * paths that each take exactly one branch (odd: tbnz, even: b).  Depending on where those
 * two branches and their targets fall, the predictor's path history becomes identical on
 * both paths and the indirect branch mispredicts about half of the time.
 * Build:  clang -O2 -falign-functions=256 -DPAD=<0..15> collapse.c   (see run.sh)
 * Expected output: 277182223 (same for every PAD and flag).
 */
#include <stdio.h>
#include <stdint.h>

enum OPCODE { HALT, LOADI, MOV, ADDI, MULI, SHRI, JEVEN, JNEI };

uint64_t ram[1024] = {
    LOADI, 100, 2,
    MOV,   101, 100,
    ADDI,  102, 1,
    JEVEN, 101, 21,
    MULI,  101, 3,
    ADDI,  101, 1,
    ADDI,  102, 1,
    SHRI,  101, 1,
    JNEI,  101, 1, 6,
    ADDI,  100, 1,
    JNEI,  100, 2000001, 3,
    HALT,
};

typedef void op(uint64_t pc);

static op halt, loadi, mov, addi, muli, shri, jeven, jnei;
static op *const labels[] = { halt, loadi, mov, addi, muli, shri, jeven, jnei };

#define NEXT __attribute__((musttail)) return labels[ram[pc]](pc)
#ifndef PAD
#define PAD 0
#endif
#define STR2(x) #x
#define STR(x) STR2(x)
#define PADDING __asm__ volatile(".rept " STR(PAD) "\n\tnop\n\t.endr")

static void halt(uint64_t pc)  { (void)pc; }
static void loadi(uint64_t pc) { ram[ram[pc + 1]]   = ram[pc + 2];      pc += 3; NEXT; }
static void mov(uint64_t pc)   { ram[ram[pc + 1]]   = ram[ram[pc + 2]]; pc += 3; NEXT; }
static void addi(uint64_t pc)  { ram[ram[pc + 1]]  += ram[pc + 2];      pc += 3; NEXT; }
static void muli(uint64_t pc)  { ram[ram[pc + 1]]  *= ram[pc + 2];      pc += 3; NEXT; }
static void shri(uint64_t pc)  { ram[ram[pc + 1]] >>= ram[pc + 2];      pc += 3; NEXT; }
static void jeven(uint64_t pc)
{
    PADDING;   /* PAD nops: moves the branches below relative to 2^k-byte blocks */
    pc = ram[ram[pc + 1]] & 1 ? pc + 3 : ram[pc + 2];   /* parity of a data value: ~50/50 */
    NEXT;      /* one indirect tail call, its target depends on the branch above */
}
static void jnei(uint64_t pc)  { pc = ram[ram[pc + 1]] != ram[pc + 2] ? ram[pc + 3] : pc + 4; NEXT; }

int main(void)
{
    uint64_t pc = 0;

    labels[ram[pc]](pc);

    printf("%llu\n", (unsigned long long)ram[102]);
    return 0;
}
