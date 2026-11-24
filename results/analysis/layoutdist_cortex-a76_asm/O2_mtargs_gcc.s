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
	add	x3, x1, 2
	add	x1, x1, 3
	ldr	x6, [x0, x3, lsl 3]
	add	x3, x0, x3, lsl 3
	ldr	x5, [x3, -8]
	str	x6, [x0, x5, lsl 3]
	ldr	x3, [x3, 8]
	ldr	x3, [x2, x3, lsl 3]
	mov	x16, x3
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
	add	x4, x1, 2
	add	x1, x1, 3
	ldr	x5, [x0, x4, lsl 3]
	add	x4, x0, x4, lsl 3
	ldr	x6, [x0, x5, lsl 3]
	ldr	x5, [x4, -8]
	str	x6, [x0, x5, lsl 3]
	ldr	x3, [x4, 8]
	ldr	x3, [x2, x3, lsl 3]
	mov	x16, x3
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
	add	x4, x1, 1
	add	x1, x1, 3
	ldr	x5, [x0, x4, lsl 3]
	add	x4, x0, x4, lsl 3
	lsl	x5, x5, 3
	ldr	x7, [x4, 8]
	ldr	x6, [x0, x5]
	add	x6, x6, x7
	str	x6, [x0, x5]
	ldr	x3, [x4, 16]
	ldr	x3, [x2, x3, lsl 3]
	mov	x16, x3
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
	add	x4, x1, 1
	add	x1, x1, 3
	ldr	x5, [x0, x4, lsl 3]
	add	x4, x0, x4, lsl 3
	lsl	x5, x5, 3
	ldr	x7, [x4, 8]
	ldr	x6, [x0, x5]
	mul	x6, x6, x7
	str	x6, [x0, x5]
	ldr	x3, [x4, 16]
	ldr	x3, [x2, x3, lsl 3]
	mov	x16, x3
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
	add	x4, x1, 1
	add	x1, x1, 3
	ldr	x5, [x0, x4, lsl 3]
	add	x4, x0, x4, lsl 3
	lsl	x5, x5, 3
	ldr	x7, [x4, 8]
	ldr	x6, [x0, x5]
	lsr	x6, x6, x7
	str	x6, [x0, x5]
	ldr	x3, [x4, 16]
	ldr	x3, [x2, x3, lsl 3]
	mov	x16, x3
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
	add	x3, x1, 1
	add	x1, x1, 3
	ldr	x4, [x0, x3, lsl 3]
	ldr	x4, [x0, x4, lsl 3]
	tbnz	x4, 0, .L10
	add	x3, x0, x3, lsl 3
	ldr	x1, [x3, 8]
.L10:
	ldr	x3, [x0, x1, lsl 3]
	ldr	x3, [x2, x3, lsl 3]
	mov	x16, x3
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
	add	x3, x1, 1
	add	x1, x1, 4
	ldr	x4, [x0, x3, lsl 3]
	add	x3, x0, x3, lsl 3
	ldr	x5, [x0, x4, lsl 3]
	ldr	x4, [x3, 8]
	cmp	x5, x4
	beq	.L13
	ldr	x1, [x3, 16]
.L13:
	ldr	x3, [x0, x1, lsl 3]
	ldr	x3, [x2, x3, lsl 3]
	mov	x16, x3
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
	stp	x29, x30, [sp, -16]!
	.cfi_def_cfa_offset 16
	.cfi_offset 29, -16
	.cfi_offset 30, -8
	adrp	x1, mem
	add	x0, x1, :lo12:mem
	mov	x29, sp
	adrp	x2, .LANCHOR0
	ldr	x1, [x1, #:lo12:mem]
	add	x2, x2, :lo12:.LANCHOR0
	ldr	x3, [x2, x1, lsl 3]
	mov	x1, 0
	blr	x3
	adrp	x0, mem
	add	x0, x0, :lo12:mem
	ldr	x1, [x0, 816]
	adrp	x0, .LC0
	add	x0, x0, :lo12:.LC0
	bl	printf
	mov	w0, 0
	ldp	x29, x30, [sp], 16
	.cfi_restore 30
	.cfi_restore 29
	.cfi_def_cfa_offset 0
	ret
	.cfi_endproc
.LFE19:
	.size	main, .-main
	.global	mem
	.section	.rodata
	.align	4
	.set	.LANCHOR0,. + 0
	.type	ops, %object
	.size	ops, 64
ops:
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
	.type	mem, %object
	.size	mem, 8192
mem:
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
