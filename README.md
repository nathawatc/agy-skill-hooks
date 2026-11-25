# Antigravity Skill Hooks

Load a skill into every [Antigravity](https://antigravity.google) CLI session, automatically.

A `SessionStart` hook. Give it the path to a `SKILL.md` and it adds that skill's
instructions to the session as a system message. It is a static binary of about 500 bytes, written
in assembly, with no runtime dependencies.

## Requirements

- Linux on x86-64
- To build: `make`, a C compiler such as GCC, and GNU binutils 2.41 or newer

## Install

```sh
git clone https://github.com/nathawatc/agy-skill-hooks.git
cd agy-skill-hooks
make install
```

This installs the binary to `~/.gemini/config/hooks/agy-skill-hooks`. It does not need root.

To install to another directory, set `HOOKS_DIR`:

```sh
make install HOOKS_DIR=/path/to/hooks
```

### Setup `hooks.json`

1. Find the `SKILL.md` you want to load:

   ```sh
   find ~/.gemini/config/plugins -name SKILL.md
   ```

2. Open `~/.gemini/config/hooks.json`, or create it, and add a `SessionStart` hook. This example
   loads the `ponytail` skill:

   ```json
   {
     "ponytail-session-start": {
       "SessionStart": [
         {
           "type": "command",
           "command": "./hooks/agy-skill-hooks ./plugins/ponytail/skills/ponytail/SKILL.md",
           "timeout": 5
         }
       ]
     }
   }
   ```

   - `ponytail-session-start` is a name you choose.
   - In `command`, replace the last path with the path to your own `SKILL.md`.
   - Relative paths start from `~/.gemini/config`. Absolute paths also work.
   - If the file already has other hooks, add this entry next to them.

3. Test the command. It should print JSON containing your skill's text:

   ```sh
   cd ~/.gemini/config
   echo '{}' | ./hooks/agy-skill-hooks ./plugins/ponytail/skills/ponytail/SKILL.md
   ```

4. Start a new Antigravity CLI session.

## Troubleshooting

### The Test Command Prints `{}`

The hook prints `{}`, which adds nothing to the session, when the file:

- does not exist, or the path is wrong
- cannot be read, or is a directory
- has no text after its frontmatter
- is 256 KiB or larger

### The Test Command Works but the Skill Does Not Load

Use absolute paths for both the binary and the `SKILL.md` in `hooks.json`:

```json
"command": "/home/you/.gemini/config/hooks/agy-skill-hooks /home/you/path/to/SKILL.md"
```

Also check that `SKILL.md` is saved as UTF-8. The hook does not validate the encoding, so any other
encoding can produce invalid JSON.

## Uninstall

Remove the entry from `~/.gemini/config/hooks.json`, then run:

```sh
make uninstall
```

If you installed with `HOOKS_DIR`, pass the same value here.
