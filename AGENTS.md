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
            output: starts where the trimmed body ends, sharing its pages
high        original stack: argv, environment
```

`FRAME` holds `MAX` bytes of input and 6 x `MAX` of output (every byte as `\u00XX`), plus the
wrapper. Pages are only backed once touched, so `MAX` sets address space, not typical memory use.
With the default 8 MiB stack limit, `MAX` can be at most about 1 MiB.

## Invariants

Each of these saves bytes, and breaks silently:

- **Zeroed registers:** `%edi` is 0 (stdin) at entry because the kernel clears registers at exec.
- **`%dl` is 0:** `%edx` holds `MAX`, whose low byte is 0, until `.Lfind` setup overwrites it.
- **Unsigned size check:** `cmpl %edx, %eax; jae` catches `-errno` and oversized files together.
  It covers a failed `open` as well, since `read` on that descriptor fails.
- **NUL terminators:** one after the raw file and one after normalization. They stop lookahead from
  matching stale bytes, which are left over from stdin or from before normalization.
- **`%rcx` is 0 at `.Lltrim`:** `.Lempty_near` reuses the `jrcxz` to reach `.Lempty` in a short jump.
- **Placement:** `.Lempty` precedes `_start` to stay in `jrcxz` range. `.Lprefix` precedes its use so
  gas can choose the 2-byte `pushq` for `.Lprefix_len`.
- **Non-PIE:** `movl $.Lprefix, %esi` needs a 32-bit absolute address.
- **One `read` for the file, one `write` for the output:** sound for regular files and blocking
  stdout, which is all the hook meets.

## Testing Gotchas

- **`STDIN` is adversarial on purpose:** stdin and the file share a buffer, so its newlines and `x`s
  expose reads past the end of a short file. Keep it longer than most test files, with a newline at
  every even offset.
- **The stdin test uses the shell's built-in `printf`:** `head` still exited 0 there with the drain
  loop removed.
- **The worst-case size test hard-codes the prefix length (51):** update it with `.Lprefix`.
- **`$(call ...)` splits on commas:** keep them out of test contents. Octal escapes for `%b` are
  written `\0ooo`.

## Disassembly

The binary has no section headers, so `objdump -d` shows nothing. Code starts at file offset `0xb0`:

```sh
objdump -D -b binary -m i386:x86-64 --start-address=0xb0 agy-skill-hooks
```

The first 51 bytes there are `.Lprefix`, decoded as nonsense instructions.
