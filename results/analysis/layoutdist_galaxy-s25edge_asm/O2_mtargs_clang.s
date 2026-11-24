	.file	"mtargs.c"
	.text
	.globl	main                            // -- Begin function main
	.p2align	2
	.type	main,@function
main:                                   // @main
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-32]!           // 16-byte Folded Spill
	.cfi_def_cfa_offset 32
	str	x19, [sp, #16]                  // 8-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 32
	.cfi_offset w19, -16
	.cfi_offset w30, -24
	.cfi_offset w29, -32
	adrp	x19, mem
	add	x19, x19, :lo12:mem
	adrp	x2, ops
	add	x2, x2, :lo12:ops
	ldr	x8, [x19]
	mov	x0, x19
	mov	x1, xzr
	ldr	x8, [x2, x8, lsl #3]
	blr	x8
	ldr	x1, [x19, #816]
	adrp	x0, .L.str
	add	x0, x0, :lo12:.L.str
	bl	printf
	mov	w0, wzr
	.cfi_def_cfa wsp, 32
	ldr	x19, [sp, #16]                  // 8-byte Folded Reload
	ldp	x29, x30, [sp], #32             // 16-byte Folded Reload
	.cfi_def_cfa_offset 0
	.cfi_restore w19
	.cfi_restore w30
	.cfi_restore w29
	ret
.Lfunc_end0:
	.size	main, .Lfunc_end0-main
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function halt
	.type	halt,@function
halt:                                   // @halt
	.cfi_startproc
// %bb.0:
	ret
.Lfunc_end1:
	.size	halt, .Lfunc_end1-halt
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function loadi
	.type	loadi,@function
loadi:                                  // @loadi
	.cfi_startproc
// %bb.0:
	add	x8, x0, x1, lsl #3
	add	x1, x1, #3
	ldp	x9, x8, [x8, #8]
	str	x8, [x0, x9, lsl #3]
	ldr	x8, [x0, x1, lsl #3]
	ldr	x3, [x2, x8, lsl #3]
	br	x3
.Lfunc_end2:
	.size	loadi, .Lfunc_end2-loadi
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function mov
	.type	mov,@function
mov:                                    // @mov
	.cfi_startproc
// %bb.0:
	add	x8, x0, x1, lsl #3
	add	x1, x1, #3
	ldp	x8, x9, [x8, #8]
	ldr	x9, [x0, x9, lsl #3]
	str	x9, [x0, x8, lsl #3]
	ldr	x8, [x0, x1, lsl #3]
	ldr	x3, [x2, x8, lsl #3]
	br	x3
.Lfunc_end3:
	.size	mov, .Lfunc_end3-mov
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function addi
	.type	addi,@function
addi:                                   // @addi
	.cfi_startproc
// %bb.0:
	add	x8, x0, x1, lsl #3
	add	x1, x1, #3
	ldp	x9, x8, [x8, #8]
	ldr	x10, [x0, x9, lsl #3]
	add	x8, x10, x8
	str	x8, [x0, x9, lsl #3]
	ldr	x8, [x0, x1, lsl #3]
	ldr	x3, [x2, x8, lsl #3]
	br	x3
.Lfunc_end4:
	.size	addi, .Lfunc_end4-addi
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function muli
	.type	muli,@function
muli:                                   // @muli
	.cfi_startproc
// %bb.0:
	add	x8, x0, x1, lsl #3
	add	x1, x1, #3
	ldp	x9, x8, [x8, #8]
	ldr	x10, [x0, x9, lsl #3]
	mul	x8, x10, x8
	str	x8, [x0, x9, lsl #3]
	ldr	x8, [x0, x1, lsl #3]
	ldr	x3, [x2, x8, lsl #3]
	br	x3
.Lfunc_end5:
	.size	muli, .Lfunc_end5-muli
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function shri
	.type	shri,@function
shri:                                   // @shri
	.cfi_startproc
// %bb.0:
	add	x8, x0, x1, lsl #3
	add	x1, x1, #3
	ldp	x9, x8, [x8, #8]
	ldr	x10, [x0, x9, lsl #3]
	lsr	x8, x10, x8
	str	x8, [x0, x9, lsl #3]
	ldr	x8, [x0, x1, lsl #3]
	ldr	x3, [x2, x8, lsl #3]
	br	x3
.Lfunc_end6:
	.size	shri, .Lfunc_end6-shri
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function jeven
	.type	jeven,@function
jeven:                                  // @jeven
	.cfi_startproc
// %bb.0:
	add	x8, x0, x1, lsl #3
	ldr	x9, [x8, #8]
	ldr	x9, [x0, x9, lsl #3]
	tbnz	w9, #0, .LBB7_2
// %bb.1:
	ldr	x1, [x8, #16]
	b	.LBB7_3
.LBB7_2:
	add	x1, x1, #3
.LBB7_3:
	ldr	x8, [x0, x1, lsl #3]
	ldr	x3, [x2, x8, lsl #3]
	br	x3
.Lfunc_end7:
	.size	jeven, .Lfunc_end7-jeven
	.cfi_endproc
                                        // -- End function
	.p2align	2                               // -- Begin function jnei
	.type	jnei,@function
jnei:                                   // @jnei
	.cfi_startproc
// %bb.0:
	add	x8, x0, x1, lsl #3
	ldp	x9, x10, [x8, #8]
	ldr	x9, [x0, x9, lsl #3]
	cmp	x9, x10
	b.ne	.LBB8_2
// %bb.1:
	add	x1, x1, #4
	b	.LBB8_3
.LBB8_2:
	ldr	x1, [x8, #24]
.LBB8_3:
	ldr	x8, [x0, x1, lsl #3]
	ldr	x3, [x2, x8, lsl #3]
	br	x3
.Lfunc_end8:
	.size	jnei, .Lfunc_end8-jnei
	.cfi_endproc
                                        // -- End function
	.type	mem,@object                     // @mem
	.data
	.globl	mem
	.p2align	3, 0x0
mem:
	.xword	1                               // 0x1
	.xword	100                             // 0x64
	.xword	2                               // 0x2
	.xword	2                               // 0x2
	.xword	101                             // 0x65
	.xword	100                             // 0x64
	.xword	3                               // 0x3
	.xword	102                             // 0x66
	.xword	1                               // 0x1
	.xword	6                               // 0x6
	.xword	101                             // 0x65
	.xword	21                              // 0x15
	.xword	4                               // 0x4
	.xword	101                             // 0x65
	.xword	3                               // 0x3
	.xword	3                               // 0x3
	.xword	101                             // 0x65
	.xword	1                               // 0x1
	.xword	3                               // 0x3
	.xword	102                             // 0x66
	.xword	1                               // 0x1
	.xword	5                               // 0x5
	.xword	101                             // 0x65
	.xword	1                               // 0x1
	.xword	7                               // 0x7
	.xword	101                             // 0x65
	.xword	1                               // 0x1
	.xword	6                               // 0x6
	.xword	3                               // 0x3
	.xword	100                             // 0x64
	.xword	1                               // 0x1
	.xword	7                               // 0x7
	.xword	100                             // 0x64
	.xword	2000001                         // 0x1e8481
	.xword	3                               // 0x3
	.zero	7912
	.size	mem, 8192

	.type	ops,@object                     // @ops
	.section	.data.rel.ro,"aw",@progbits
	.p2align	3, 0x0
ops:
	.xword	halt
	.xword	loadi
	.xword	mov
	.xword	addi
	.xword	muli
	.xword	shri
	.xword	jeven
	.xword	jnei
	.size	ops, 64

	.type	.L.str,@object                  // @.str
	.section	.rodata.str1.1,"aMS",@progbits,1
.L.str:
	.asciz	"%llu\n"
	.size	.L.str, 6

	.ident	"clang version 21.1.8"
	.section	".note.GNU-stack","",@progbits
