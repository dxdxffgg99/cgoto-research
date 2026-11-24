	.file	"s.c"
	.text
	.globl	main                            // -- Begin function main
	.p2align	2
	.type	main,@function
main:                                   // @main
	.cfi_startproc
// %bb.0:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	adrp	x8, ram
	add	x8, x8, :lo12:ram
	adrp	x9, main.labels
	add	x9, x9, :lo12:main.labels
	ldr	x10, [x8, xzr, lsl #3]
	ldr	x11, [x9, x10, lsl #3]
	mov	x10, xzr
	br	x11
.Ltmp0:                                 // Block address taken
.LBB0_1:                                // =>This Inner Loop Header: Depth=1
	add	x11, x8, x10, lsl #3
	add	x10, x10, #3
	ldp	x12, x11, [x11, #8]
	str	x11, [x8, x12, lsl #3]
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.Ltmp1:                                 // Block address taken
.LBB0_2:                                // =>This Inner Loop Header: Depth=1
	add	x11, x8, x10, lsl #3
	add	x10, x10, #3
	ldp	x11, x12, [x11, #8]
	ldr	x12, [x8, x12, lsl #3]
	str	x12, [x8, x11, lsl #3]
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.Ltmp2:                                 // Block address taken
.LBB0_3:                                // =>This Inner Loop Header: Depth=1
	add	x11, x8, x10, lsl #3
	add	x10, x10, #3
	ldp	x12, x11, [x11, #8]
	ldr	x13, [x8, x12, lsl #3]
	add	x11, x13, x11
	str	x11, [x8, x12, lsl #3]
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.Ltmp3:                                 // Block address taken
.LBB0_4:                                // =>This Inner Loop Header: Depth=1
	add	x11, x8, x10, lsl #3
	add	x10, x10, #3
	ldp	x12, x11, [x11, #8]
	ldr	x13, [x8, x12, lsl #3]
	mul	x11, x13, x11
	str	x11, [x8, x12, lsl #3]
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.Ltmp4:                                 // Block address taken
.LBB0_5:                                // =>This Inner Loop Header: Depth=1
	add	x11, x8, x10, lsl #3
	add	x10, x10, #3
	ldp	x12, x11, [x11, #8]
	ldr	x13, [x8, x12, lsl #3]
	lsr	x11, x13, x11
	str	x11, [x8, x12, lsl #3]
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.Ltmp5:                                 // Block address taken
.LBB0_6:                                // =>This Inner Loop Header: Depth=1
	add	x11, x8, x10, lsl #3
	ldr	x12, [x11, #8]
	ldr	x12, [x8, x12, lsl #3]
	tbnz	w12, #0, .LBB0_8
// %bb.7:                               //   in Loop: Header=BB0_6 Depth=1
	ldr	x10, [x11, #16]
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.LBB0_8:                                //   in Loop: Header=BB0_6 Depth=1
	add	x10, x10, #3
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.Ltmp6:                                 // Block address taken
.LBB0_9:                                // =>This Inner Loop Header: Depth=1
	add	x11, x8, x10, lsl #3
	ldp	x12, x13, [x11, #8]
	ldr	x12, [x8, x12, lsl #3]
	cmp	x12, x13
	b.ne	.LBB0_11
// %bb.10:                              //   in Loop: Header=BB0_9 Depth=1
	add	x10, x10, #4
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.LBB0_11:                               //   in Loop: Header=BB0_9 Depth=1
	ldr	x10, [x11, #24]
	ldr	x11, [x8, x10, lsl #3]
	ldr	x11, [x9, x11, lsl #3]
	br	x11
.Ltmp7:                                 // Block address taken
.LBB0_12:
	adrp	x8, ram+816
	adrp	x0, .L.str
	add	x0, x0, :lo12:.L.str
	ldr	x1, [x8, :lo12:ram+816]
	bl	printf
	mov	w0, wzr
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16             // 16-byte Folded Reload
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
.Lfunc_end0:
	.size	main, .Lfunc_end0-main
	.cfi_endproc
                                        // -- End function
	.type	ram,@object                     // @ram
	.data
	.globl	ram
	.p2align	3, 0x0
ram:
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
	.size	ram, 8192

	.type	main.labels,@object             // @main.labels
	.section	.data.rel.ro,"aw",@progbits
	.p2align	3, 0x0
main.labels:
	.xword	.Ltmp7
	.xword	.Ltmp0
	.xword	.Ltmp1
	.xword	.Ltmp2
	.xword	.Ltmp3
	.xword	.Ltmp4
	.xword	.Ltmp5
	.xword	.Ltmp6
	.size	main.labels, 64

	.type	.L.str,@object                  // @.str
	.section	.rodata.str1.1,"aMS",@progbits,1
.L.str:
	.asciz	"%llu\n"
	.size	.L.str, 6

	.ident	"clang version 21.1.8 (https://github.com/llvm/llvm-project 2078da43e25a4623cab2d0d60decddf709aaea28)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
