	.file	"s.c"
	.text
	.globl	main                            // -- Begin function main
	.p2align	2
	.type	main,@function
main:                                   // @main
	.cfi_startproc
// %bb.0:
	mov	x8, xzr
	adrp	x9, ram
	add	x9, x9, :lo12:ram
	b	.LBB0_2
.LBB0_1:                                //   in Loop: Header=BB0_2 Depth=1
	add	x10, x9, x8, lsl #3
	add	x8, x8, #3
	ldp	x11, x10, [x10, #8]
	ldr	x12, [x9, x11, lsl #3]
	lsr	x10, x12, x10
	str	x10, [x9, x11, lsl #3]
.LBB0_2:                                // =>This Inner Loop Header: Depth=1
	ldr	x10, [x9, x8, lsl #3]
	cmp	x10, #3
	b.le	.LBB0_6
// %bb.3:                               //   in Loop: Header=BB0_2 Depth=1
	cmp	x10, #5
	b.gt	.LBB0_9
// %bb.4:                               //   in Loop: Header=BB0_2 Depth=1
	cmp	x10, #4
	b.ne	.LBB0_1
// %bb.5:                               //   in Loop: Header=BB0_2 Depth=1
	add	x10, x9, x8, lsl #3
	add	x8, x8, #3
	ldp	x11, x10, [x10, #8]
	ldr	x12, [x9, x11, lsl #3]
	mul	x10, x12, x10
	str	x10, [x9, x11, lsl #3]
	b	.LBB0_2
.LBB0_6:                                //   in Loop: Header=BB0_2 Depth=1
	cmp	x10, #1
	b.le	.LBB0_12
// %bb.7:                               //   in Loop: Header=BB0_2 Depth=1
	cmp	x10, #2
	b.ne	.LBB0_16
// %bb.8:                               //   in Loop: Header=BB0_2 Depth=1
	add	x10, x9, x8, lsl #3
	add	x8, x8, #3
	ldp	x10, x11, [x10, #8]
	ldr	x11, [x9, x11, lsl #3]
	str	x11, [x9, x10, lsl #3]
	b	.LBB0_2
.LBB0_9:                                //   in Loop: Header=BB0_2 Depth=1
	cmp	x10, #6
	add	x10, x9, x8, lsl #3
	b.ne	.LBB0_14
// %bb.10:                              //   in Loop: Header=BB0_2 Depth=1
	ldr	x11, [x10, #8]
	ldr	x11, [x9, x11, lsl #3]
	tbnz	w11, #0, .LBB0_17
// %bb.11:                              //   in Loop: Header=BB0_2 Depth=1
	ldr	x8, [x10, #16]
	b	.LBB0_2
.LBB0_12:                               //   in Loop: Header=BB0_2 Depth=1
	b.ne	.LBB0_19
// %bb.13:                              //   in Loop: Header=BB0_2 Depth=1
	add	x10, x9, x8, lsl #3
	add	x8, x8, #3
	ldp	x11, x10, [x10, #8]
	str	x10, [x9, x11, lsl #3]
	b	.LBB0_2
.LBB0_14:                               //   in Loop: Header=BB0_2 Depth=1
	ldp	x11, x12, [x10, #8]
	ldr	x11, [x9, x11, lsl #3]
	cmp	x11, x12
	b.ne	.LBB0_18
// %bb.15:                              //   in Loop: Header=BB0_2 Depth=1
	add	x8, x8, #4
	b	.LBB0_2
.LBB0_16:                               //   in Loop: Header=BB0_2 Depth=1
	add	x10, x9, x8, lsl #3
	add	x8, x8, #3
	ldp	x11, x10, [x10, #8]
	ldr	x12, [x9, x11, lsl #3]
	add	x10, x12, x10
	str	x10, [x9, x11, lsl #3]
	b	.LBB0_2
.LBB0_17:                               //   in Loop: Header=BB0_2 Depth=1
	add	x8, x8, #3
	b	.LBB0_2
.LBB0_18:                               //   in Loop: Header=BB0_2 Depth=1
	ldr	x8, [x10, #24]
	b	.LBB0_2
.LBB0_19:
	stp	x29, x30, [sp, #-16]!           // 16-byte Folded Spill
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
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

	.type	.L.str,@object                  // @.str
	.section	.rodata.str1.1,"aMS",@progbits,1
.L.str:
	.asciz	"%llu\n"
	.size	.L.str, 6

	.ident	"clang version 21.1.8 (https://github.com/llvm/llvm-project 2078da43e25a4623cab2d0d60decddf709aaea28)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
