# clang-format Style Options for Luam

## Current Lua/Luam Style
- **Indent**: 2 spaces
- **Braces**: K&R (same line)
- **Line length**: ~80 chars

## Option 1: Conservative (Recommended) ⭐

Preserves Lua's original style, minimal changes.

```yaml
---
BasedOnStyle: LLVM
IndentWidth: 2
UseTab: Never
ColumnLimit: 80
BreakBeforeBraces: Attach
AllowShortFunctionsOnASingleLine: Empty
AllowShortIfStatementsOnASingleLine: Never
PointerAlignment: Right
SortIncludes: false
```

**Impact:** ~5% of lines changed (whitespace only)

## Option 2: Linux Kernel

Uses tabs, brace-on-newline for functions.

```yaml
---
BasedOnStyle: LLVM  
IndentWidth: 8
UseTab: Always
BreakBeforeBraces: Linux
```

**Impact:** ~40% of lines changed

## Option 3: Google Style

Modern, opinionated, very readable.

```yaml
---
BasedOnStyle: Google
IndentWidth: 2
ColumnLimit: 80
```

**Impact:** ~30% of lines changed

## Recommendation

**Use Option 1** - respects legacy Lua code style while enforcing consistency.

Test first:
```bash
clang-format -style=file src/lbaselib.c | diff src/lbaselib.c -
```
