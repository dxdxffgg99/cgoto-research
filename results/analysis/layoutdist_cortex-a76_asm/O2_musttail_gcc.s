	.arch armv8-a
	.file	"s.c"
	.text
	.align	2
	.p2align 5,,15
	.type	halt, %function
halt:
.LFB11:
	.cfi_startproc
	ret
	.cfi_endproc
.LFE11:
	.size	halt, .-halt
	.align	2
	.p2align 5,,15
	.type	loadi, %function
loadi:
.LFB12:
	.cfi_startproc
	add	x2, x0, 1
	adrp	x1, ram
	add	x1, x1, :lo12:ram
	add	x3, x0, 2
	add	x0, x0, 3
	ldr	x2, [x1, x2, lsl 3]
	ldr	x3, [x1, x3, lsl 3]
	str	x3, [x1, x2, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	adrp	x1, .LANCHOR0
	add	x1, x1, :lo12:.LANCHOR0
	ldr	x1, [x1, x2, lsl 3]
	mov	x16, x1
	br	x16
	.cfi_endproc
.LFE12:
	.size	loadi, .-loadi
	.align	2
	.p2align 5,,15
	.type	mov, %function
mov:
.LFB13:
	.cfi_startproc
	add	x3, x0, 2
	adrp	x1, ram
	add	x1, x1, :lo12:ram
	add	x2, x0, 1
	add	x0, x0, 3
	ldr	x3, [x1, x3, lsl 3]
	ldr	x2, [x1, x2, lsl 3]
	ldr	x3, [x1, x3, lsl 3]
	str	x3, [x1, x2, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	adrp	x1, .LANCHOR0
	add	x1, x1, :lo12:.LANCHOR0
	ldr	x1, [x1, x2, lsl 3]
	mov	x16, x1
	br	x16
	.cfi_endproc
.LFE13:
	.size	mov, .-mov
	.align	2
	.p2align 5,,15
	.type	addi, %function
addi:
.LFB14:
	.cfi_startproc
	add	x2, x0, 1
	adrp	x1, ram
	add	x1, x1, :lo12:ram
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x2, [x1, x2, lsl 3]
	ldr	x4, [x1, x3, lsl 3]
	add	x2, x2, x4
	str	x2, [x1, x3, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	adrp	x1, .LANCHOR0
	add	x1, x1, :lo12:.LANCHOR0
	ldr	x1, [x1, x2, lsl 3]
	mov	x16, x1
	br	x16
	.cfi_endproc
.LFE14:
	.size	addi, .-addi
	.align	2
	.p2align 5,,15
	.type	muli, %function
muli:
.LFB15:
	.cfi_startproc
	add	x2, x0, 1
	adrp	x1, ram
	add	x1, x1, :lo12:ram
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x2, [x1, x2, lsl 3]
	ldr	x4, [x1, x3, lsl 3]
	mul	x2, x2, x4
	str	x2, [x1, x3, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	adrp	x1, .LANCHOR0
	add	x1, x1, :lo12:.LANCHOR0
	ldr	x1, [x1, x2, lsl 3]
	mov	x16, x1
	br	x16
	.cfi_endproc
.LFE15:
	.size	muli, .-muli
	.align	2
	.p2align 5,,15
	.type	shri, %function
shri:
.LFB16:
	.cfi_startproc
	add	x2, x0, 1
	adrp	x1, ram
	add	x1, x1, :lo12:ram
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 2
	add	x0, x0, 3
	ldr	x4, [x1, x2, lsl 3]
	ldr	x2, [x1, x3, lsl 3]
	lsr	x2, x2, x4
	str	x2, [x1, x3, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	adrp	x1, .LANCHOR0
	add	x1, x1, :lo12:.LANCHOR0
	ldr	x1, [x1, x2, lsl 3]
	mov	x16, x1
	br	x16
	.cfi_endproc
.LFE16:
	.size	shri, .-shri
	.align	2
	.p2align 5,,15
	.type	jeven, %function
jeven:
.LFB17:
	.cfi_startproc
	add	x2, x0, 1
	adrp	x1, ram
	add	x1, x1, :lo12:ram
	ldr	x2, [x1, x2, lsl 3]
	ldr	x2, [x1, x2, lsl 3]
	tbz	x2, 0, .L9
	add	x0, x0, 3
	ldr	x2, [x1, x0, lsl 3]
	adrp	x1, .LANCHOR0
	add	x1, x1, :lo12:.LANCHOR0
	ldr	x1, [x1, x2, lsl 3]
	mov	x16, x1
	br	x16
	.p2align 2,,3
.L9:
	add	x0, x0, 2
	ldr	x0, [x1, x0, lsl 3]
	ldr	x2, [x1, x0, lsl 3]
	adrp	x1, .LANCHOR0
	add	x1, x1, :lo12:.LANCHOR0
	ldr	x1, [x1, x2, lsl 3]
	mov	x16, x1
	br	x16
	.cfi_endproc
.LFE17:
	.size	jeven, .-jeven
	.align	2
	.p2align 5,,15
	.type	jnei, %function
jnei:
.LFB18:
	.cfi_startproc
	add	x2, x0, 1
	adrp	x1, ram
	add	x1, x1, :lo12:ram
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 2
	ldr	x4, [x1, x3, lsl 3]
	ldr	x3, [x1, x2, lsl 3]
	add	x2, x0, 4
	cmp	x4, x3
	beq	.L13
	add	x0, x0, 3
	ldr	x2, [x1, x0, lsl 3]
.L13:
	ldr	x0, [x1, x2, lsl 3]
	adrp	x1, .LANCHOR0
	add	x1, x1, :lo12:.LANCHOR0
	ldr	x1, [x1, x0, lsl 3]
	mov	x0, x2
	mov	x16, x1
	br	x16
	.cfi_endproc
.LFE18:
	.size	jnei, .-jnei
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
.LFB19:
	.cfi_startproc
	stp	x29, x30, [sp, -32]!
	.cfi_def_cfa_offset 32
	.cfi_offset 29, -32
	.cfi_offset 30, -24
	adrp	x0, ram
	mov	x29, sp
	ldr	x1, [x0, #:lo12:ram]
	str	x19, [sp, 16]
	.cfi_offset 19, -16
	add	x19, x0, :lo12:ram
	adrp	x0, .LANCHOR0
	add	x0, x0, :lo12:.LANCHOR0
	ldr	x1, [x0, x1, lsl 3]
	mov	x0, 0
	blr	x1
	ldr	x1, [x19, 816]
	adrp	x0, .LC0
	add	x0, x0, :lo12:.LC0
	bl	printf
	ldr	x19, [sp, 16]
	mov	w0, 0
	ldp	x29, x30, [sp], 32
	.cfi_restore 30
	.cfi_restore 29
	.cfi_restore 19
	.cfi_def_cfa_offset 0
	ret
	.cfi_endproc
.LFE19:
	.size	main, .-main
	.global	ram
	.section	.rodata
	.align	4
	.set	.LANCHOR0,. + 0
	.type	labels, %object
	.size	labels, 64
labels:
	.xword	halt
	.xword	loadi
	.xword	mov
	.xword	addi
	.xword	muli
	.xword	shri
	.xword	jeven
	.xword	jnei
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
