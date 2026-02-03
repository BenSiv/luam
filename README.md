# LuaM

LuaM is a modernized fork of Lua 5.1, featuring a stricter, safer, and more concise syntax. 
t retains the speed and simplicity of Lua 5.1 while adopting features from later Lua versions and modern programming paradigms.

## Key Features

### 1. Safer Syntax
*   **mplicit Locals**: ariables are `local` by default. o need to type `local` everywhere.
    ```lua
    x = 10        -- Local variable
    function f()  -- Local function
    end
    ```
*   **Constants**: Use the `const` keyword to define immutable variables. Reassignment to a `const` variable results in a compile-time error.
    ```lua
    const y = 20
    y = 30 -- Error: attempt to assign to const variable
    ```

### 2. Modern Operators & Control Flow
*   **Inequality**: Use `!=` instead of `~=`.
    ```lua
    if x != y then ... end
    ```
*   **Removed Keywords**: `repeat`, `until`, and `local` have been removed to simplify the language. Use `while` loops instead.

### 3. Enhanced String & Data Support
*   **riple Quoted Strings**: Use `"""` for multiline strings (replacing `[[...]]`).
    ```lua
    s = """
    Multi-line
    String
    """
    ```
*   **Hexadecimal Escapes**: Use `\xXX` for characters in strings (e.g., `"\x41"` is "").
    ```lua
    str = "Lua\x4D" -- LuaM
    ```
*   **`__len` Metamethod**: ables support the `__len` metamethod (from Lua 5.2).
    ```lua
    mt = { __len = function(t) return 42 end }
    ```

### 4. Improved Standard Library
*   **`xpcall` with rguments**: `xpcall` now accepts arguments to pass to the function (from Lua 5.2).
    ```lua
    xpcall(func, handler, arg1, arg2)
    ```
*   **Unified `load`**: `load(chunk)` handles both functions (as `load` did) and strings (replacing `loadstring`).
    ```lua
    load("return 1") -- Works like loadstring
    ```
*   **Math & able Enhancements**:
    *   `math.log(x, base)`: Supports optional base argument.
    *   `table.pack(...)`: Creates a table from arguments with field `n`.
    *   `table.unpack(t)`: Unpacks a table (renamed from `unpack`, though global `unpack` remains).
*   **System & Packages**:
    *   `os.exit(boolean)`: Pass `true` (success) or `false` (failure).
    *   `package.searchers`: lias for `package.loaders` for 5.2 compatibility.

## Build & Install

LuaM uses [xmake](https://xmake.io) as its build system.

### Building
To build LuaM, run:

```sh
xmake f -o bld -y
xmake
```

This will produce all build artifacts (including intermediate files) in the `bld/` directory:
*   `bld/luam`: The interpreter
*   `bld/luamc`: The compiler
*   `bld/sqlite3.so`: The SQLite3 module

### Running Tests
To run the full regression suite:

```sh
xmake test
```

## Documentation
The `doc` directory contains detailed information about LuaM features and changes. Additionally, Unix manual pages are provided:
*   `doc/lua.1`: Manual page for the `luam` interpreter.
*   `doc/luac.1`: Manual page for the `luamc` compiler.

These can be viewed using `man`:
```sh
man doc/lua.1
```

## License
LuaM is free software, released under the M license (same as Lua 5.1).
See [COPYRIGHT.md](COPYRIGHT.md) for details.
