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

A bare **function statement** (`function f() ... end`) gets exactly the
same implicit-local treatment as `f = function() ... end` — both create a
genuine local, and the two forms are interchangeable for this rule despite
looking like two different things. Activation happens *before* the
function's own body is compiled, so a function can always call itself by
its own bare name and recurse correctly. Calling a *different* function
defined later in the same file is the one case that doesn't work for
free: that name doesn't exist yet at the point the earlier code compiles,
so the reference falls through to an unresolved global — `nil` at call
time, a loud crash at the exact call site, not silent misbehavior. See
[doc/forward_references.md](doc/forward_references.md) for the full rules
and the pre-declaration idiom for when a forward reference (including
genuine mutual recursion) is really needed. An earlier version of Luam
tried a different fix for the underlying collision bug this closes — see
[doc/changelog.md](doc/changelog.md) for that history.

Because bare assignment and a bare function statement are both really
local, the common Lua idiom of loading a script and then reading back
whatever globals it set (`lua_getglobal` from C, or `dofile(...);
print(x)` from Lua) no longer works by default for a plain variable or a
bare function — neither becomes visible outside the chunk that created it.

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

### Building a static binary for a downstream project

`bld/build_lang.sh` above builds Luam itself. A separate project written
*in* Luam that wants to ship as one standalone native executable (no
Luam installation required on the target machine) uses
`lib/static/build.lua` instead:

```sh
luam lib/static/build.lua --entry main.lua --bin myproject --with sqlite3,lfs
```

It flattens the project's own source together with Luam's stdlib and
any vendored modules it needs, compiles and preload-registers whatever
C extensions are requested (see `MODULES` in that file for the full
list), and links everything into one binary in `./bin/`. Run it with
`--help` for the full option list. This replaces hand-rolling the same
temp-dir/flatten/compile/link logic in a project's own `bld/build.sh`
independently each time -- see `daat`'s and `brain-ex`'s own
`bld/build.sh` for the (now very thin) delegation this leaves behind.

---

## Documentation

Manual pages are provided in the `doc/` directory:

- `doc/lua.1`
- `doc/luac.1`

Design notes on specific language changes:

- [doc/manifesto.md](doc/manifesto.md) — the design tenets behind Luam, and how each one continues a goal Lua's own creators stated for Lua itself
- [doc/error_handling.md](doc/error_handling.md) — nil-check patterns under strict conditionals
- [doc/forward_references.md](doc/forward_references.md) — why calling a same-file function defined later doesn't work by default, and the zero-new-syntax pre-declaration idiom for when it's genuinely needed
- [doc/strict_not_operator.md](doc/strict_not_operator.md) — the strict `not` operator and literal-`nil` restrictions
- [doc/changelog.md](doc/changelog.md) — full list of differences from Lua 5.1, with measured (not estimated) size numbers
- [doc/install.md](doc/install.md) — build targets and platform options

---

## License

Luam is free software, released under the **MIT License**, matching Lua 5.1.
