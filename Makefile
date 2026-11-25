ALL_LDFLAGS = -nostdlib -static -s -Wa,-mx86-used-note=no -Wl,-n -Wl,-z,noexecstack -Wl,-z,nosectionheader -Wl,--build-id=none $(LDFLAGS)

agy-skill-hooks: src/main.s
	$(CC) $(CFLAGS) $< $(ALL_LDFLAGS) -o $@

.PHONY: clean
clean:
	$(RM) agy-skill-hooks
