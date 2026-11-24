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
	stp	x29, x30, [sp, -16]!
	.cfi_def_cfa_offset 16
	.cfi_offset 29, -16
	.cfi_offset 30, -8
	adrp	x1, ram
	adrp	x3, .LANCHOR0
	mov	x29, sp
	add	x3, x3, :lo12:.LANCHOR0
	ldr	x0, [x1, #:lo12:ram]
	add	x1, x1, :lo12:ram
	ldr	x2, [x3, x0, lsl 3]
	mov	x0, 0
	br	x2
	.p2align 2,,3
.L3:
	add	x2, x0, 1
	add	x4, x0, 2
	ldr	x2, [x1, x2, lsl 3]
.L18:
	add	x0, x0, 3
	ldr	x4, [x1, x4, lsl 3]
	str	x4, [x1, x2, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	ldr	x2, [x3, x2, lsl 3]
	br	x2
	.p2align 2,,3
.L15:
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
.L9:
	.cfi_restore_state
	add	x2, x0, 1
	ldr	x2, [x1, x2, lsl 3]
	ldr	x2, [x1, x2, lsl 3]
	tbz	x2, 0, .L10
	add	x0, x0, 3
	ldr	x2, [x1, x0, lsl 3]
	ldr	x2, [x3, x2, lsl 3]
	br	x2
	.p2align 2,,3
.L7:
	add	x2, x0, 1
	ldr	x4, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x2, [x1, x2, lsl 3]
	ldr	x5, [x1, x4, lsl 3]
	mul	x2, x2, x5
	str	x2, [x1, x4, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	ldr	x2, [x3, x2, lsl 3]
	br	x2
	.p2align 2,,3
.L6:
	add	x2, x0, 1
	ldr	x4, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x2, [x1, x2, lsl 3]
	ldr	x5, [x1, x4, lsl 3]
	add	x2, x2, x5
	str	x2, [x1, x4, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	ldr	x2, [x3, x2, lsl 3]
	br	x2
	.p2align 2,,3
.L4:
	add	x2, x0, 1
	add	x4, x0, 2
	ldr	x2, [x1, x2, lsl 3]
	ldr	x4, [x1, x4, lsl 3]
	b	.L18
	.p2align 2,,3
.L8:
	add	x2, x0, 1
	ldr	x4, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x5, [x1, x2, lsl 3]
	ldr	x2, [x1, x4, lsl 3]
	lsr	x2, x2, x5
	str	x2, [x1, x4, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	ldr	x2, [x3, x2, lsl 3]
	br	x2
	.p2align 2,,3
.L12:
	add	x2, x0, 1
	ldr	x4, [x1, x2, lsl 3]
	add	x2, x0, 2
	ldr	x4, [x1, x4, lsl 3]
	ldr	x2, [x1, x2, lsl 3]
	cmp	x4, x2
	beq	.L13
	add	x0, x0, 3
	ldr	x0, [x1, x0, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	ldr	x2, [x3, x2, lsl 3]
	br	x2
.L10:
	add	x0, x0, 2
	ldr	x0, [x1, x0, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	ldr	x2, [x3, x2, lsl 3]
	br	x2
.L13:
	add	x0, x0, 4
	ldr	x2, [x1, x0, lsl 3]
	ldr	x2, [x3, x2, lsl 3]
	br	x2
	.cfi_endproc
.LFE11:
	.size	main, .-main
	.global	ram
	.section	.rodata
	.align	4
	.set	.LANCHOR0,. + 0
	.type	labels.0, %object
	.size	labels.0, 64
labels.0:
	.xword	.L15
	.xword	.L3
	.xword	.L4
	.xword	.L6
	.xword	.L7
	.xword	.L8
	.xword	.L9
	.xword	.L12
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
