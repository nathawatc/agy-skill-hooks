ALL_LDFLAGS = -nostdlib -static -s -Wa,-mx86-used-note=no -Wl,-n -Wl,-z,noexecstack -Wl,-z,nosectionheader -Wl,--build-id=none $(LDFLAGS)

HOOKS_DIR = $(HOME)/.gemini/config/hooks

# The program reads stdin and the file into the same buffer. This is longer than
# the short test files, so a read past their end finds a newline or an x.
STDIN = printf '\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx\nx'

# $(1) = arguments. Requires exit status 0 and exactly {} on stdout.
define expect_empty
	$(STDIN) | ./$< $(1) >check.out
	echo '{}' | cmp - check.out
endef

# $(1) = file contents for printf %b, $(2) = exact expected JSON-escaped body.
# Requires exit status 0.
define expect_body
	printf '%b' $(1) >check.in
	$(STDIN) | ./$< check.in >check.out
	printf '%s\n' '{"injectSteps":[{"systemMessage":{"systemMessage":"'$(2)'"}}]}' | cmp - check.out
endef

# $(1) = file contents for printf %b. Requires exit status 0 and exactly {}.
define expect_blank
	printf '%b' $(1) >check.in
	$(call expect_empty,check.in)
endef

all: agy-skill-hooks

agy-skill-hooks: src/main.s
	$(CC) $(CFLAGS) $< $(ALL_LDFLAGS) -o $@

check: agy-skill-hooks
	# Unusable files
	$(call expect_empty,)
	$(call expect_empty,"")
	$(call expect_empty,src)
	$(call expect_empty,src/missing.md)
	$(call expect_blank,'')
	$(call expect_blank,' \t\r\n\n')
	$(call expect_blank,'---\na: b\n---\n\n')
	# Frontmatter
	$(call expect_body,'---\na: b\n---\n\nbody\n','body')
	$(call expect_body,'---\r\na: b\r\n---\r\nbody\r\n','body')
	$(call expect_body,'---\na\n---\nb\n---\nc','b\n---\nc')
	$(call expect_body,'---\n\n---\nbody','body')
	$(call expect_body,'---\n---\nbody','---\n---\nbody')
	$(call expect_body,'---\na: b\nbody','---\na: b\nbody')
	$(call expect_body,'---\na\n---','---\na\n---')
	$(call expect_body,'---\r\na\r\nb\r\n\r\n---','---\na\nb\n\n---')
	$(call expect_body,'---\na\n ---\nbody','---\na\n ---\nbody')
	$(call expect_body,'x\n---\na\n---\nbody','x\n---\na\n---\nbody')
	# Trimming and newlines
	$(call expect_body,' \t\n a  b \t\r\n','a  b')
	$(call expect_body,'a\r\nb\rc\r\r\n\nd\r','a\nb\nc\n\n\nd')
	# JSON escaping
	$(call expect_body,'"q" \\ /','\"q\" \\ /')
	$(call expect_body,'a\tb\0001c\0037d\0177e\0000f','a\u0009b\u0001c\u001fd'"$$(printf '\177')"'e\u0000f')
	$(call expect_body,'ไทย 😀','ไทย 😀')
	# Size limit: the largest file, at the worst-case expansion, then one byte more
	printf x >check.in && truncate -s 262142 check.in && printf x >>check.in
	$(STDIN) | ./$< check.in >check.out
	test "$$(wc -c <check.out)" -eq $$((51 + 2 + 6 * 262141 + 6))
	printf x >>check.in
	$(call expect_empty,check.in)
	# Stdin must be read to the end, or the writer gets SIGPIPE
	printf hi >check.in
	{ printf '%1000000s' '' && echo ok >check.out; } | ./$< check.in >/dev/null
	test "$$(cat check.out)" = ok
	rm -f check.in check.out

install: agy-skill-hooks
	install -D -m 755 agy-skill-hooks $(DESTDIR)$(HOOKS_DIR)/agy-skill-hooks

uninstall:
	rm -f $(DESTDIR)$(HOOKS_DIR)/agy-skill-hooks

clean:
	rm -f agy-skill-hooks check.in check.out

.PHONY: all check install uninstall clean
