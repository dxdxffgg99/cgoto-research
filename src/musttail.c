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
    JNEI,  100, 10000001, 3,
    HALT,
};

typedef void op(uint64_t pc);

static op halt, loadi, mov, addi, muli, shri, jeven, jnei;
static op *const labels[] = { halt, loadi, mov, addi, muli, shri, jeven, jnei };

#define NEXT __attribute__((musttail)) return labels[ram[pc]](pc)

static void halt(uint64_t pc)  { (void)pc; }
static void loadi(uint64_t pc) { ram[ram[pc + 1]]   = ram[pc + 2];      pc += 3; NEXT; }
static void mov(uint64_t pc)   { ram[ram[pc + 1]]   = ram[ram[pc + 2]]; pc += 3; NEXT; }
static void addi(uint64_t pc)  { ram[ram[pc + 1]]  += ram[pc + 2];      pc += 3; NEXT; }
static void muli(uint64_t pc)  { ram[ram[pc + 1]]  *= ram[pc + 2];      pc += 3; NEXT; }
static void shri(uint64_t pc)  { ram[ram[pc + 1]] >>= ram[pc + 2];      pc += 3; NEXT; }
static void jeven(uint64_t pc) { pc = ram[ram[pc + 1]] & 1            ? pc + 3 : ram[pc + 2]; NEXT; }
static void jnei(uint64_t pc)  { pc = ram[ram[pc + 1]] != ram[pc + 2] ? ram[pc + 3] : pc + 4; NEXT; }

int main(void)
{
    uint64_t pc = 0;

    labels[ram[pc]](pc);

    printf("%llu\n", (unsigned long long)ram[102]);
    return 0;
}
