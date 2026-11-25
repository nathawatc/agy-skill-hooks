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

	.set	SYS_read, 0
	.set	SYS_write, 1
	.set	SYS_open, 2
	.set	SYS_exit, 60

	# The low byte of MAX must be 0: %dl doubles as a NUL.
	.set	MAX, 256 * 1024
	# Input, output at the worst-case 6x escape (\u00XX), and the JSON wrapper.
	.set	FRAME, 7 * MAX + 256

	.text
	# Defined before use so gas can pick the 2-byte push for .Lprefix_len.
.Lprefix:
	.ascii	"{\"injectSteps\":[{\"systemMessage\":{\"systemMessage\":\""
	.set	.Lprefix_len, . - .Lprefix

	# Ahead of _start to be in jrcxz range.
.Lempty:
	pushq	$0x0a7d7b		# {}\n
	pushq	%rsp
	popq	%rsi
	pushq	$3
	popq	%rdx
	jmp	.Lwrite

	.globl	_start
_start:
	popq	%rbx			# argc
	popq	%rbx			# argv[0]
	popq	%rbx			# argv[1], NULL if absent: open gives EFAULT
	subq	$FRAME, %rsp
	movl	$MAX, %edx

	# The hook contract requires consuming stdin. %edi is already 0.
.Ldrain:
	xorl	%eax, %eax		# SYS_read
	pushq	%rsp
	popq	%rsi
	syscall
	testl	%eax, %eax
	jg	.Ldrain

	pushq	$SYS_open
	popq	%rax
	pushq	%rbx
	popq	%rdi
	xorl	%esi, %esi		# O_RDONLY
	syscall

	# A failed open needs no check: read then fails with EBADF.
	xchgl	%eax, %edi
	xorl	%eax, %eax		# SYS_read
	pushq	%rsp
	popq	%rsi
	syscall
	cmpl	%edx, %eax		# unsigned: catches -errno and too big
	jae	.Lempty
	movb	%dl, (%rsi,%rax)	# so the \r\n peek cannot see stale stdin
	xchgl	%eax, %ecx
.Lempty_near:
	jrcxz	.Lempty

	# Universal newlines, in place: \r\n and \r become \n.
	pushq	%rsi
	popq	%rdi
.Lnewline:
	lodsb
	cmpb	$'\r', %al
	jne	.Lkeep
	movb	$'\n', %al
	cmpb	%al, (%rsi)
	jne	.Lkeep
	incq	%rsi
	decl	%ecx			# the \n is inside the file, so %ecx >= 1
.Lkeep:
	stosb
	decl	%ecx
	jnz	.Lnewline
	movb	%dl, (%rdi)		# no match below can run past the end

	# Skip frontmatter: "---\n" at 0, closed by "\n---\n" at 4 or later.
	pushq	%rsp
	popq	%rsi
	movl	$0x0a2d2d2d, %eax	# "---\n"
	cmpl	%eax, (%rsi)
	jne	.Lltrim
	leaq	3(%rsi), %rdx
.Lfind:
	incq	%rdx
	cmpq	%rdi, %rdx
	jae	.Lltrim			# unclosed: keep the text as is
	cmpl	%eax, 1(%rdx)
	jne	.Lfind
	cmpb	$'\n', (%rdx)
	jne	.Lfind
	leaq	5(%rdx), %rsi

	# Trim both ends of bytes <= space: ASCII whitespace plus other control
	# characters, but not Unicode spaces. %rsi = start, %rdi = end.
.Lltrim:
	cmpq	%rdi, %rsi
	jae	.Lempty_near		# %rcx is 0 here; a short hop via jrcxz
	lodsb
	cmpb	$' ', %al
	jbe	.Lltrim
	decq	%rsi
.Lrtrim:
	decq	%rdi
	cmpb	$' ', (%rdi)		# stops at the byte .Lltrim found
	jbe	.Lrtrim
	incq	%rdi
	movl	%edi, %ecx
	subl	%esi, %ecx

	# Output goes right after the input, sharing its pages.
	pushq	%rdi
	pushq	%rcx
	pushq	%rsi
	movl	$.Lprefix, %esi
	pushq	$.Lprefix_len
	popq	%rcx
	rep movsb
	popq	%rsi
	popq	%rcx

.Lescape:
	lodsb
	cmpb	$'"', %al
	je	.Lbackslash
	cmpb	$'\\', %al
	je	.Lbackslash
	cmpb	$' ', %al
	jb	.Lcontrol
	stosb
.Lnext:
	decl	%ecx
	jnz	.Lescape

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

.Lcontrol:
	cmpb	$'\n', %al
	jne	.Lunicode
	movb	$'n', %al
.Lbackslash:
	movb	%al, %ah
	movb	$'\\', %al
	stosw
	jmp	.Lnext

.Lunicode:
	pushq	%rax
	movl	$0x3030755c, %eax	# \u00
	stosl
	popq	%rax
	movb	%al, %ah
	shrb	$4, %al
	andb	$15, %ah
	cmpb	$10, %ah
	jb	.Ldigit
	addb	$'a' - '0' - 10, %ah
.Ldigit:
	addw	$0x3030, %ax
	stosw
	jmp	.Lnext
