# LuaM

**LuaM** is a modernized fork of **Lua 5.1**, featuring a stricter, safer, and more concise syntax. It preserves the speed and simplicity of Lua 5.1 while selectively adopting features from later Lua versions and modern programming paradigms.

---

## Key Features

### 1. Safer Syntax

#### Implicit Locals
Variables are `local` by default, preventing accidental pollution of the global namespace. There is no need to explicitly write `local`.

```lua
x = 10        -- Local variable
function f()  -- Local function
end
```

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

LuaM provides a simplified build process via a dedicated shell script.

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

---

## License

LuaM is free software, released under the **MIT License**, matching Lua 5.1.
