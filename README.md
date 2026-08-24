# Luam

**Luam** is a modernized fork of **Lua 5.1**, featuring a stricter, safer, and more concise syntax. It preserves the speed and simplicity of Lua 5.1 while selectively adopting features from later Lua versions and modern programming paradigms.

---

## Key Features

### 1. Safer Syntax

#### Implicit Locals
The `local` keyword has been removed. A bare *assignment* to a name that
isn't already a local or upvalue declares a new local in the current block
instead of writing a global — this is true for any loaded chunk (a file,
`load`, `loadstring`, `dofile`, `require`, ...). The one exception is the
interactive prompt (`luam -e`, the REPL), where bare assignment still writes
a real global so that variables persist across separate lines typed at the
prompt.

```lua
x = 10   -- local to this chunk/block
```

A bare **function statement** (`function f() ... end`) is not the same
thing, even though it looks like it should be: `f` is not a local. It's an
ordinary write into whatever environment is currently in effect, exactly
like unmodified Lua 5.1 — an earlier version of Luam did make it a genuine
local, matching plain assignment exactly, but that broke any file where one
function calls another defined later in the same file (routine in Lua-family
code; a real global tolerates it because both the write and the read
resolve at *call* time, while a lexical local can't, because the reference
is resolved once, at *parse* time, before a later declaration exists) — see
[doc/changelog.md](doc/changelog.md) for that history. What actually keeps
`f` from leaking today is module isolation, next.

Because bare assignment really is local, the common Lua idiom of loading a
script and then reading back whatever globals it set (`lua_getglobal` from
C, or `dofile(...); print(x)` from Lua) no longer works by default for a
plain variable — `x` above never becomes visible outside the chunk that
created it.

#### Module Isolation
Every module loaded via `require()` gets its own private global table
instead of sharing the real `_G` directly. Reads still fall through to the
real globals (`string`, `pairs`, `require`, any already-`require`d module a
file binds to its own bare name, ...); only a *write* to a name that isn't
already a local, upvalue, or otherwise-resolvable global is affected —
exactly the bare-function-statement case above, plus the rare case a plain
assignment doesn't already cover on its own. This closes a real bug: two
unrelated required files each defining the same private, never-exported
bare helper function used to silently clobber each other's real global,
with no error at all.

Deliberately scoped to `require()` itself — not to `load`/`loadstring`/
`dofile()`, and not to the top-level script or the REPL, all of which keep
sharing whatever environment the calling code already has, exactly as in
stock Lua. A required module is this language's actual unit of isolation;
a directly-run script or an explicit `dofile()` is ordinary inline
execution, sharing the caller's scope by design.

**Known limitation:** this isolation always falls back to the real `_G`,
not to whatever environment the code that *called* `require()` happens to
be restricted to. A module loaded via `require()` from inside a sandboxed
environment still gets full read access to the real globals through that
fallback — so `require` itself should never be exposed to sandboxed code
that's meant to be denied that access. A sandbox that wants to let
untrusted code load a restricted set of modules needs to resolve and hand
over the *values* those modules export, never the `require` function
itself.

#### Real Globals
`_G` is still the same global table as in Lua 5.1, and reading an undeclared
name still resolves to a global. To deliberately create or modify a real
global from a script, assign through `_G` explicitly:

```lua
_G.config = { debug = true }  -- visible to the host / other chunks
```

`getfenv`/`setfenv` are also still present, so a chunk's environment can be
swapped out the same way it can in Lua 5.1 (e.g. to sandbox untrusted code).

#### Constants
Use the `const` keyword to define immutable variables. Reassigning a `const` variable results in a compile-time error.

```lua
const y = 20
y = 30 -- Error: attempt to assign to const variable
```

---

### 2. Modern Operators & Control Flow

#### Inequality Operator
Use `!=` instead of `~=`.

```lua
if x != y then
    -- ...
end
```

#### Removed Keywords
To simplify the language and enforce a single idiomatic style:

- `repeat`
- `until`
- `local`

have been removed.

All iterative logic is expressed using `while` loops.

#### Strict Conditionals
`if`, `while`, and `not` require an actual boolean (`true`/`false`). There is
no truthy/falsy coercion, and a literal `nil` in a conditional is a
compile-time error:

```lua
if 0 then ... end          -- error: conditional requires a boolean value
if nil then ... end        -- error: nil is not a conditional value
if not nil then ... end    -- error: 'not' requires a boolean value, got nil

value = get_value()
if value != nil then ... end   -- OK: comparison produces a boolean
```

When the compiler can already prove an expression is a boolean (e.g. the
result of a comparison held in a local), the runtime check is skipped
entirely — the check only costs anything for values it can't already prove
safe. See [doc/strict_not_operator.md](doc/strict_not_operator.md) and
[doc/error_handling.md](doc/error_handling.md) for the full rules and
migration patterns.

---

### 3. Enhanced String & Data Support

#### Triple-Quoted Strings
Multiline strings use `"""` instead of the traditional `[[ ... ]]` syntax.

```lua
s = """
Multi-line
String support
"""
```

#### Hexadecimal Escape Sequences
Strings support hexadecimal escapes using `\xXX`.

```lua
"A" == "\x41"
```

#### `__len` Metamethod
Tables support the `__len` metamethod (backported from Lua 5.2), enabling custom length semantics.

#### Metatables
Metatables and tag methods (`setmetatable`, `getmetatable`, `__index`,
`__newindex`, `__call`, ...) work the same as Lua 5.1's. This is a deliberate
tradeoff, not an oversight: Luam discourages OOP-style programming at the
*syntax* layer — colon method-call and method-definition sugar
(`obj:method()`, `function obj:method() ... end`) are removed, so any
metatable-based object still has to be called and defined the long way
(`obj.method(obj, ...)`). The underlying `setmetatable`/`__index` mechanism
itself stays fully enabled, because vendored libraries under `lib/`
(LuaSocket, the sqlite test framework, ...) are ordinary upstream Lua code
that relies on it — disabling it at the primitive level would mean rewriting
every vendored library rather than just declining to add ergonomic sugar for
new code.

---

### 4. Improved Standard Library

#### `xpcall` with Arguments
`xpcall` accepts arguments passed directly to the called function (backported from Lua 5.2).

```lua
xpcall(func, handler, arg1, arg2)
```

#### Unified `load`
`load(chunk)` handles both functions and strings, replacing the need for `loadstring`.

#### Math & Table Enhancements
- `math.log(x, base)` supports an optional base argument.
- `table.pack(...)` creates a table from arguments and includes an `n` field.
- `table.unpack(t)` is standardized (renamed from `unpack`).

#### System & Package Improvements
- `os.exit(boolean)` supports `true` for success and `false` for failure.
- `package.searchers` is provided as an alias for `package.loaders` for Lua 5.2 compatibility.

---

## Build & Install

Luam provides a simplified build process via a dedicated shell script.

### Building

```sh
chmod +x bld/build_lang.sh
./bld/build_lang.sh
```

Build artifacts are placed in the `bin/` directory:

- `bin/luam` — Interactive interpreter
- `bin/luamc` — Bytecode compiler
- `bin/sqlite3.so` — SQLite3 module

---

## Documentation

Manual pages are provided in the `doc/` directory:

- `doc/lua.1`
- `doc/luac.1`

Design notes on specific language changes:

- [doc/manifesto.md](doc/manifesto.md) — the design tenets behind Luam, and how each one continues a goal Lua's own creators stated for Lua itself
- [doc/error_handling.md](doc/error_handling.md) — nil-check patterns under strict conditionals
- [doc/strict_not_operator.md](doc/strict_not_operator.md) — the strict `not` operator and literal-`nil` restrictions
- [doc/changelog.md](doc/changelog.md) — full list of differences from Lua 5.1, with measured (not estimated) size numbers
- [doc/install.md](doc/install.md) — build targets and platform options

---

## License

Luam is free software, released under the **MIT License**, matching Lua 5.1.
