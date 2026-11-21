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

int main(void)
{
    uint64_t pc = 0;

    while (ram[pc] != HALT) {
        switch (ram[pc]) {
            case LOADI: ram[ram[pc + 1]]   = ram[pc + 2];      pc += 3; break;
            case MOV:   ram[ram[pc + 1]]   = ram[ram[pc + 2]]; pc += 3; break;
            case ADDI:  ram[ram[pc + 1]]  += ram[pc + 2];      pc += 3; break;
            case MULI:  ram[ram[pc + 1]]  *= ram[pc + 2];      pc += 3; break;
            case SHRI:  ram[ram[pc + 1]] >>= ram[pc + 2];      pc += 3; break;
            case JEVEN: pc = ram[ram[pc + 1]] & 1            ? pc + 3 : ram[pc + 2]; break;
            case JNEI:  pc = ram[ram[pc + 1]] != ram[pc + 2] ? ram[pc + 3] : pc + 4; break;
        }
    }

    printf("%llu\n", (unsigned long long)ram[102]);
    return 0;
}
