	.arch armv8-a
	.file	"s.c"
	.text
	.section	.rodata.str1.8,"aMS",@progbits,1
	.align	3
.LC0:
	.string	"%llu\n"
	.section	.text.startup,"ax",@progbits
	.align	2
	.p2align 5,,15
	.global	main
	.type	main, %function
main:
.LFB11:
	.cfi_startproc
	adrp	x1, ram
	add	x1, x1, :lo12:ram
	stp	x29, x30, [sp, -16]!
	.cfi_def_cfa_offset 16
	.cfi_offset 29, -16
	.cfi_offset 30, -8
	mov	x0, 0
	mov	x29, sp
	.p2align 5,,15
.L2:
	ldr	x2, [x1, x0, lsl 3]
	cmp	x2, 4
	beq	.L3
.L20:
	bhi	.L4
	cmp	x2, 2
	beq	.L5
	cmp	x2, 3
	beq	.L6
	cbz	x2, .L7
	add	x2, x0, 1
	add	x3, x0, 2
	add	x0, x0, 3
	ldr	x2, [x1, x2, lsl 3]
	ldr	x3, [x1, x3, lsl 3]
	str	x3, [x1, x2, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	cmp	x2, 4
	bne	.L20
	.p2align 5,,15
.L3:
	add	x2, x0, 1
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x2, [x1, x2, lsl 3]
	ldr	x4, [x1, x3, lsl 3]
	mul	x2, x2, x4
	str	x2, [x1, x3, lsl 3]
	b	.L2
	.p2align 2,,3
.L4:
	cmp	x2, 6
	beq	.L9
	cmp	x2, 7
	beq	.L10
	add	x2, x0, 1
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x4, [x1, x2, lsl 3]
	ldr	x2, [x1, x3, lsl 3]
	lsr	x2, x2, x4
	str	x2, [x1, x3, lsl 3]
	b	.L2
	.p2align 2,,3
.L5:
	add	x3, x0, 2
	add	x2, x0, 1
	add	x0, x0, 3
	ldr	x3, [x1, x3, lsl 3]
	ldr	x2, [x1, x2, lsl 3]
	ldr	x3, [x1, x3, lsl 3]
	str	x3, [x1, x2, lsl 3]
	b	.L2
	.p2align 2,,3
.L10:
	add	x2, x0, 1
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 2
	ldr	x3, [x1, x3, lsl 3]
	ldr	x2, [x1, x2, lsl 3]
	cmp	x3, x2
	beq	.L14
	add	x0, x0, 3
	ldr	x0, [x1, x0, lsl 3]
	b	.L2
	.p2align 2,,3
.L9:
	add	x2, x0, 1
	ldr	x2, [x1, x2, lsl 3]
	ldr	x2, [x1, x2, lsl 3]
	tbz	x2, 0, .L13
	add	x0, x0, 3
	b	.L2
	.p2align 2,,3
.L7:
	ldr	x1, [x1, 816]
	adrp	x0, .LC0
	add	x0, x0, :lo12:.LC0
	bl	printf
	mov	w0, 0
	ldp	x29, x30, [sp], 16
	.cfi_remember_state
	.cfi_restore 30
	.cfi_restore 29
	.cfi_def_cfa_offset 0
	ret
	.p2align 2,,3
.L6:
	.cfi_restore_state
	add	x2, x0, 1
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x2, [x1, x2, lsl 3]
	ldr	x4, [x1, x3, lsl 3]
	add	x2, x2, x4
	str	x2, [x1, x3, lsl 3]
	b	.L2
.L13:
	add	x0, x0, 2
	ldr	x0, [x1, x0, lsl 3]
	b	.L2
.L14:
	add	x0, x0, 4
	b	.L2
	.cfi_endproc
.LFE11:
	.size	main, .-main
	.global	ram
	.data
	.align	4
	.type	ram, %object
	.size	ram, 8192
ram:
	.xword	1
	.xword	100
	.xword	2
	.xword	2
	.xword	101
	.xword	100
	.xword	3
	.xword	102
	.xword	1
	.xword	6
	.xword	101
	.xword	21
	.xword	4
	.xword	101
	.xword	3
	.xword	3
	.xword	101
	.xword	1
	.xword	3
	.xword	102
	.xword	1
	.xword	5
	.xword	101
	.xword	1
	.xword	7
	.xword	101
	.xword	1
	.xword	6
	.xword	3
	.xword	100
	.xword	1
	.xword	7
	.xword	100
	.xword	2000001
	.xword	3
	.xword	0
	.zero	7904
	.ident	"GCC: (Arm GNU Toolchain 15.2.Rel1 (Build arm-15.86)) 15.2.1 20251203"
	.section	.note.GNU-stack,"",@progbits
