# Code Style

Luam uses the Conservative / Lua-5.1-compatible clang-format style: 2-space
indent, K&R braces (attached), 80-column limit, based on `BasedOnStyle: LLVM`.
The decision this file used to debate between three options has already been
made and is encoded in `.clang-format` at the repo root — that file is the
source of truth, not this doc.

```bash
clang-format -style=file src/lbaselib.c | diff src/lbaselib.c -
```

**Historical note:** An earlier revision of `.clang-format` had a character-stripping
typo (`BasedOnStyle: LLM`); this has been fixed to `BasedOnStyle: LLVM` in
`.clang-format`.
