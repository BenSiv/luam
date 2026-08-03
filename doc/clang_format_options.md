# Code Style

Luam uses the Conservative / Lua-5.1-compatible clang-format style: 2-space
indent, K&R braces (attached), 80-column limit. The decision this file used
to debate between three options has already been made and is encoded in
`.clang-format` at the repo root — that file is the source of truth, not this
doc.

```bash
clang-format -style=file src/lbaselib.c | diff src/lbaselib.c -
```

**Known issue:** `.clang-format`'s `BasedOnStyle: LLM` is not a valid
clang-format base style (valid values are `LLVM`, `Google`, `Chromium`,
`Mozilla`, `WebKit`, `Microsoft`, `GNU`) — it should be `LLVM`. This repo's
`.clang-format` and the top-level `Makefile` comments both show the same
pattern of missing letters (`A`, `N`, `T`, `I`, `G`, `R`, `V`, `Y` dropped
throughout prose), which is why this file is being left as a pointer rather
than fully rewritten here — the fix belongs in `.clang-format` itself, not in
this doc.
