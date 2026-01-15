# clang-format Style Options for Luam

## Current Lua/Luam Style
- **ndent**: 2 spaces
- **Braces**: K& (same line)
- **Line length**: ~80 chars

## Option 1: Conservative (ecommended) ⭐

Preserves Lua's original style, minimal changes.

```yaml
---
BasedOnStyle: LLM
ndentWidth: 2
Useab: ever
ColumnLimit: 80
BreakBeforeBraces: ttach
llowShortFunctionsOnSingleLine: Empty
llowShortfStatementsOnSingleLine: ever
Pointerlignment: ight
Sortncludes: false
```

**mpact:** ~5% of lines changed (whitespace only)

## Option 2: Linux Kernel

Uses tabs, brace-on-newline for functions.

```yaml
---
BasedOnStyle: LLM  
ndentWidth: 8
Useab: lways
BreakBeforeBraces: Linux
```

**mpact:** ~40% of lines changed

## Option 3: oogle Style

Modern, opinionated, very readable.

```yaml
---
BasedOnStyle: oogle
ndentWidth: 2
ColumnLimit: 80
```

**mpact:** ~30% of lines changed

## ecommendation

**Use Option 1** - respects legacy Lua code style while enforcing consistency.

est first:
```bash
clang-format -style=file src/lbaselib.c | diff src/lbaselib.c -
```
