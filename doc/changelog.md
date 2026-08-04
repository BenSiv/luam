# Differences from Lua 5.1

Luam is a fork of Lua 5.1. This document lists what actually changed, checked
against the current `src/` and the built interpreter — not aspirational. (An
earlier version of this file had several claims that didn't match the code;
see the notes inline below.)

## Language

| Feature | Lua 5.1 | Luam |
|---|---|---|
| Conditionals | truthy/falsy (any value) | strict boolean required (`if`/`while`/`not`) |
| Variable declaration | explicit `local`, implicit global | `local` removed; bare assignment is implicit-local (see below) |
| Constants | none | `const` keyword, compile-time enforced |
| Inequality operator | `~=` | `!=` (`~=` removed) |
| `repeat`/`until` | present | removed (use `while`) |
| Multiline strings | `[[ ... ]]` | `""" ... """` |
| String escapes | — | `\xXX` hex escapes added |
| `__len` metamethod | not in 5.1 | backported from 5.2 |
| Colon method syntax | `obj:m()`, `function obj:m()` | removed (use `obj.m(obj, ...)`) |

### Strict conditionals

`if`, `while`, and `not` require an actual `true`/`false` value:

```lua
x = nil
if x then print("runs") end   -- error: conditional requires a boolean value

y = 0
if y then print("runs") end   -- error: conditional requires a boolean value

-- correct:
if y != nil then print("runs") end   -- comparison returns a boolean
```

A literal `nil` in a conditional position, or `not` applied to anything but a
boolean, is rejected — with the same underlying check in both cases (there is
no separate "not nil" special case):

```
$ luam -e 'if nil then print(1) end'
nil is not a conditional value near 'then'

$ luam -e 'x = not nil; print(x)'
'not' requires a boolean value, got nil near ';'
```

The check is a single bit in the `OP_TEST`/`OP_TESTSET` instruction's C
operand (`lvm.c`), set by the compiler only when it can't already prove the
value is boolean. When it can prove it — e.g. a local holding the result of a
comparison — the bit is unset and the runtime check is skipped entirely. This
*is* real, verified by disassembling both cases with `luamc -l`:

```lua
x = (1 > 0); if x then end   --  TEST 0 0 0   (strict bit unset — proven boolean)
x = foo();   if x then end   --  TEST 0 0 2   (strict bit set — unproven)
```

See [strict_not_operator.md](strict_not_operator.md) and
[error_handling.md](error_handling.md) for the full rules and migration
patterns.

### Implicit locals, and how to still create a real global

`local` is removed. Bare assignment (`x = 5`) to a name that isn't already a
local or upvalue declares a new local in the current block — for any loaded
chunk (a file, `load`, `loadstring`, `dofile`). The one exception is the
interactive prompt: bare assignment there still writes a real global, so
variables persist across separate lines typed at the REPL.

Confirmed by running it:

```
$ echo 'x = 5' > /tmp/f.lua
$ luam -e 'dofile("/tmp/f.lua"); print(x)'
nil                          -- x never left the chunk
```

This means the common Lua pattern of running a script and reading back the
globals it set no longer works unless the script writes through `_G`
explicitly:

```lua
_G.result = compute()   -- real global, visible to the host afterward
```

`_G`, `getfenv`, and `setfenv` all still work exactly as in Lua 5.1.

### Removed from the standard language

- `module()` and `newproxy()` — confirmed removed (`type(module) == nil`).
- **Not removed:** `getfenv`/`setfenv`. An earlier version of this doc listed
  them as removed; they were removed early in development and later restored,
  and this doc wasn't updated. They're in `lbaselib.c` and work.

## Standard library

All spot-checked against the built interpreter:

- `xpcall(func, handler, arg1, ...)` — extra arguments forwarded to `func` (backported from 5.2).
- `load(chunk)` — accepts both a function and a string, replacing `loadstring`.
- `math.log(x, base)` — optional base argument.
- `table.pack(...)` / `table.unpack(t)` — as in 5.2.
- `os.exit(true|false)` — boolean accepted alongside the integer status code.
- `package.searchers` — alias for `package.loaders`.

## Size, measured

Earlier drafts of this doc, and a separate `codebase_size_comparison.md` (now
removed — its numbers are superseded by this section), quoted size numbers
that didn't match each other or the actual binaries. Real numbers, same
machine, same `-O2`, both built with their own `make linux`:

| Metric | Lua 5.1 | Luam | Diff |
|---|---|---|---|
| Source lines (`src/*.c` + `*.h`) | 16,963 | 16,914 | -49 (-0.3%) |
| Interpreter binary, stripped | 207,072 B | 215,264 B | **+8,192 B (+4.0%, larger)** |

Luam is *not* smaller than Lua 5.1 — this doc previously claimed the
opposite. Source size is close (clang-format reformatting offset most of the
added logic), but the binary is measurably bigger, consistent with a compiler
front end that does more work (implicit-local resolution, the strict-boolean
type inference above, `const` tracking).

No wall-clock timing benchmark in this repo should be trusted as-is — none of
the numbers previously here were reproducible from a described methodology.
If you need real timing numbers, run a benchmark suite with multiple trials
yourself; the only performance claim that's actually verified is the
bytecode-level one above.

## Building

```sh
./bld/build_lang.sh     # wraps `make clean && make linux`
```

See [install.md](install.md) for other platform targets (macosx, mingw, ...).

## License

Luam is distributed under the same MIT license as Lua 5.1.
