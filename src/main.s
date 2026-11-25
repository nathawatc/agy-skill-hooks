# Sizes are minimized: registers are chosen for short encodings, and
# pushq/popq loads constants in 3 bytes where movl takes 5.
#
# Usage: agy-skill-hooks <path to SKILL.md>
#
# Drains stdin, then prints the skill body (frontmatter stripped, trimmed,
# JSON-escaped) as an Antigravity injectSteps payload. Prints {} if the file
# is missing, unreadable, blank, or MAX bytes or larger. Always exits 0.
#
# x86-64 Linux only. Relies on the kernel zeroing registers at exec.

	.set	SYS_write, 1
	.set	SYS_open, 2
	.set	SYS_exit, 60

	# MAX = 1 << MAX_BIT. The frame is 8 x MAX: input, output at the worst-case
	# 6x escape (\u00XX), and the JSON wrapper. One register holds both the frame
	# size and the read size.
	.set	MAX_BIT, 18
	.set	FRAME_BIT, MAX_BIT + 3

	.text
	# Copied in two overlapping pieces, so that .Lrepeat appears twice.
.Lprefix:
	.ascii	"{\"injectSteps\":["
.Lrepeat:
	.ascii	"{\"systemMessage\":"
.Lquote:
	.ascii	"\""
.Lprefix_end:

	.globl	_start
_start:
	popq	%rdi			# argc
	popq	%rdi			# argv[0]
	popq	%rdi			# argv[1], NULL if absent: open gives EFAULT
	movb	$SYS_open, %al		# %esi is 0: O_RDONLY
	syscall
	btsl	$FRAME_BIT, %edx
	subq	%rdx, %rsp
	pushq	%rsp
	popq	%rsi			# %rsi = base of the buffer until .Lnewline
	pushq	%rax
	xorl	%edi, %edi

	# The hook contract requires consuming stdin.
.Ldrain:
	xorl	%eax, %eax		# SYS_read
	syscall
	testl	%eax, %eax
	jg	.Ldrain

	# %eax is 0 again: SYS_read. After a stdin error it is -errno, which is no
	# syscall and fails. A failed open needs no check: read gives EBADF.
	popq	%rdi
	syscall
	movl	%eax, %ecx
	shrl	$MAX_BIT, %eax		# nonzero for both -errno and too big
	jnz	.Lcheck			# %rbx is still 0, so .Lcheck rejects
	movb	%al, (%rsi,%rcx)	# NUL, so the \r\n peek cannot see stale stdin
	jrcxz	.Lcheck

	# Universal newlines, in place: drop the \r of \r\n, other \r become \n.
	pushq	%rsi			# text start, for .Ltrim
	pushq	%rsi
	popq	%rdi
.Lnewline:
	lodsb
	cmpb	$'\r', %al
	jne	.Lkeep
	movb	$'\n', %al
	cmpb	%al, (%rsi)
	je	.Ldrop
.Lkeep:
	stosb
.Ldrop:
	loop	.Lnewline

	# Output goes right after the text, sharing its pages. Its { also stops
	# the scans below: it matches no delimiter and is not blank.
	pushq	%rdi
	popq	%rbx			# %rbx = text end
	movl	$.Lprefix, %esi
	movb	$.Lquote - .Lprefix, %cl
	rep movsb
	subl	$.Lquote - .Lrepeat, %esi
	movb	$.Lprefix_end - .Lrepeat, %cl
	rep movsb

	# Skip frontmatter: "---\n" at 0, closed by "\n---\n" at 4 or later.
	popq	%rsi
	pushq	%rsi
	lodsl
	cmpl	$0x0a2d2d2d, %eax	# "---\n"
	jne	.Ltrim
	xchgl	%eax, %edx
.Lfind:
	cmpl	%ebx, %esi		# equality only, so 32 bits are enough
	je	.Ltrim			# unclosed: keep the text as is
	lodsb
	cmpb	$'\n', %al
	jne	.Lfind
	cmpl	%edx, (%rsi)
	jne	.Lfind
	lodsl
	pushq	%rsi			# the new start, over the old one

	# Trim both ends of bytes <= space: ASCII whitespace plus other control
	# characters, but not Unicode spaces.
.Ltrim:
	popq	%rsi
	pushq	%rbx			# output start, for write
.Lltrim:
	lodsb
	cmpb	$' ', %al
	jbe	.Lltrim
.Lcheck:
	cmpq	%rbx, %rsi
	ja	.Lempty			# ran into the prefix: nothing but blanks
.Lrtrim:
	decq	%rbx			# %rbx = last byte to print
	cmpb	$' ', (%rbx)		# stops at the byte .Lltrim found
	jbe	.Lrtrim

	# %al already holds the first byte.
.Lescape:
	cmpb	$'"', %al
	je	.Lbackslash
	cmpb	$'\\', %al
	je	.Lbackslash
	cmpb	$' ', %al
	jae	.Lput
	cmpb	$'\n', %al
	jne	.Lunicode
	movb	$'n', %al
.Lbackslash:
	movb	$'\\', %ah
.Lpair:
	movb	%ah, (%rdi)
	scasb				# incq %rdi in 1 byte
.Lput:
	stosb
	cmpq	%rbx, %rsi
	lodsb				# keeps the flags
	jbe	.Lescape

	movl	$0x5d7d7d22, %eax	# "}}]
	stosl
	movw	$0x0a7d, %ax		# }\n
	stosw
	popq	%rsi
	movl	%edi, %edx
	subl	%esi, %edx

.Lwrite:
	pushq	$SYS_write
	popq	%rax
	movl	%eax, %edi		# stdout is also 1
	syscall
	pushq	$SYS_exit
	popq	%rax
	xorl	%edi, %edi
	syscall

.Lempty:
	pushq	$0x0a7d7b		# {}\n
	pushq	%rsp
	popq	%rsi
	pushq	$3
	popq	%rdx
	jmp	.Lwrite

	# %al < 0x20, so the high digit is 0 or 1.
.Lunicode:
	movl	$0x3030755c, (%rdi)	# \u00
	scasl				# addq $4, %rdi in 1 byte
	movb	$'0', %ah
	cmpb	$0x10, %al
	sbbb	$-1, %ah		# +1 if %al >= 0x10
	orb	$'0', %al
	cmpb	$'9', %al
	jbe	.Lpair
	addb	$'a' - '9' - 1, %al
	jmp	.Lpair
