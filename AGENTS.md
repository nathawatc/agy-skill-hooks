# AGENTS.md

A `SessionStart` hook for Antigravity CLI in x86-64 Linux assembly (GNU as, AT&T syntax, raw
syscalls). All code is in `src/main.s`. Optimize for binary size first, then startup time. User
documentation is in `README.md`.

## Changing the Code

1. Record the binary size before the change: `make && stat -c %s agy-skill-hooks`.
2. Make the change. Add a `check` case in `Makefile` for each behavior it adds or alters.
3. Run `make check` until it passes.
4. Mutate each changed instruction or branch that affects behavior, and confirm `make check` goes
   red. If a mutant survives, strengthen the tests. Restore the code afterward.
5. Report the size before and after, and justify every byte of growth.
6. After editing Markdown, run `rumdl check .`.

Commit with Conventional Commits messages.

## Contract

- Read stdin to EOF. Exiting early gives the writer `SIGPIPE`. The contents are ignored.
- Write one JSON object and a newline to stdout, and always exit 0.
- Fail open: every error prints `{}`, so a broken hook cannot break the session.

The first version was a Python script, and the parsed JSON matches it except where size won:

| Case | Python | Here |
| --- | --- | --- |
| File of `MAX` bytes or more | Loaded | `{}` |
| Unreadable file | Traceback | `{}` |
| Invalid UTF-8 | Traceback | Passed through, so the JSON is invalid |
| Control characters at either end | Kept, unless whitespace | Trimmed (every byte <= space) |
| Unicode spaces at either end | Trimmed | Kept |

Control characters other than `\n` use the `\u00XX` form, tab included. `\r` never reaches the
escaper, because `\r\n` and `\r` become `\n` first.

## Memory Layout

The stack is the only buffer. A `.data` or `.bss` section would add a 56-byte program header.

```text
low   rsp   input: stdin chunks, then the file over them, normalized in place
            output: starts where the normalized text ends, sharing its pages
high        original stack: argv, environment
```

The frame is 8 x `MAX`, where `MAX` is `1 << MAX_BIT`: `MAX` of input, 6 x `MAX` of output (every
byte as `\u00XX`), and the wrapper. Pages are only backed once touched, so `MAX` sets address space,
not typical memory use. The frame is 2 MiB, so the stack limit must be larger than that. With the
default 8 MiB, `MAX_BIT` can be at most 19.

## Invariants

Each of these saves bytes, and breaks silently:

- **Zeroed registers:** the kernel clears them at exec. `%eax`, `%edx`, `%esi` and `%ebx` are all
  used as 0 before being set.
- **Open before drain:** this reuses the zeroed `%esi` as `O_RDONLY`. The cost is that closed or
  failing stdin prints `{}`. After a stdin error `%eax` is `-errno`, so the file `read` fails too.
- **`shrl $MAX_BIT` check:** the result is nonzero for `-errno` and for oversized files. It covers a
  failed `open` as well, since `read` on that descriptor fails.
- **Early rejects land on `.Lcheck`:** `%rbx` is still 0 there, so `ja` is taken. This keeps those
  branches short.
- **`%al` is 0 after `shrl`:** it is stored as a NUL after the raw file, so the `\r\n` lookahead
  cannot see stale stdin.
- **The prefix is a sentinel:** its `{` directly follows the text. It ends the delimiter match and
  the left trim without bounds checks.
- **`%rcx` is 0 after `loop` and `rep`:** so `movb` to `%cl` sets the whole register.
- **Stack order:** `.Lfind` pushes the new start over the old one, and `.Ltrim` pops whichever is on
  top. The leftover is never popped.
- **`%al` is live into `.Lescape`:** the left trim loads the first byte. `rep movsb` runs before it.
- **`scasb` and `scasl`:** used only to advance `%rdi`. They need the direction flag clear.
- **Prefix in two pieces:** `.Lrepeat` is copied twice, so the JSON keys are stored once.
- **Non-PIE:** `movl $.Lprefix, %esi` needs a 32-bit absolute address.
- **One `read` for the file, one `write` for the output:** sound for regular files and blocking
  stdout, which is all the hook meets.

Size beats speed by choice. Replacing every hot `lodsb` and `stosb` with `movb` and `incq` made a
3.5 KB skill about 6 microseconds (4-5%) faster, for 17 more bytes. `loop` costs nothing on Zen 3.

## Testing Gotchas

- **`STDIN` is adversarial on purpose:** stdin and the file share a buffer, so its newlines and `x`s
  expose reads past the end of a short file. Keep it longer than most test files, with a newline at
  every even offset.
- **The stdin test uses the shell's built-in `printf`:** `head` still exited 0 there with the drain
  loop removed.
- **The worst-case size test hard-codes the printed prefix length (51):** update it with `.Lprefix`.
- **`$(call ...)` splits on commas:** keep them out of test contents. Octal escapes for `%b` are
  written `\0ooo`.

## Disassembly

The binary has no section headers, so `objdump -d` shows nothing. Code starts at file offset `0x78`:

```sh
objdump -D -b binary -m i386:x86-64 --start-address=0x78 agy-skill-hooks
```

The first 34 bytes there are `.Lprefix`, decoded as nonsense instructions.
