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

#### Defined Table Order
`pairs` and `next` visit integer keys in ascending order, then every other
key in the order it was added, so records, JSON output and declarations come
out the way they were written. See [doc/table_order.md](doc/table_order.md).

---

### 3. Enhanced String & Data Support

#### Unified Double-Quoted Strings (`"..."` and `"""..."""`)
Luam uses `"` as its sole string quote (`'...'` single-quoted strings and `[[ ... ]]` bracket strings are removed). Both single-line `"..."` and multiline `"""..."""` share the same strict `\` escape engine, and `"""..."""` preserves raw bytes 100% literally — including line 1, with no hidden leading-newline stripping:

```lua
s = """
first line
    second line
"""
-- exact value: "\nfirst line\n    second line\n"
```

Use `string.dedent(...)` when you want indentation stripped explicitly. See [doc/strings_and_escapes.md](doc/strings_and_escapes.md) for the full specification.

#### Strict `\` Escape Sequences
Unknown escapes (such as `"\d"` or `"\s"`) and legacy decimal escapes (`"\27"`, `"\027"`) are compile-time syntax errors instead of silently dropping backslashes. Supported escapes across both `"..."` and `"""..."""`:
- Standard controls & quotes: `\a`, `\b`, `\f`, `\n`, `\r`, `\t`, `\v`, `\\`, `\"`, `\'`, `\0` (when not followed by a digit)
- Hexadecimal bytes: `\xXX` (`"A" == "\x41"`)
- Compile-time UTF-8 code points: `\u{X...}` (`"\u{2122}" == "™"`)
- Line continuations & whitespace skip: `\<newline>` and `\z`

#### `__len` Metamethod
Tables support the `__len` metamethod (backported from Lua 5.2), enabling custom length semantics.

#### Procedural C Handles & Metatables
Colon method-call and method-definition sugar (`obj:method()`, `function obj:method() ... end`) are removed, and both userdata and string `__index` dispatch are disabled in the VM so C bindings (`io`, `sqlite3`, `mariadb`, `lfs`, `crypto`, `vec`) and `string` expose flat procedural functions (`mod.fn(handle, ...)` / `string.fn(s, ...)`), eliminating shared global string-metatable leaks across sandboxes while retaining internal C `__gc` finalizers and `luaL_checkudata` pointer safety. Table metatables currently remain available for passive serialization markers (such as `dkjson`'s container hints).

---

### 4. Improved Standard Library

#### `xpcall` with Arguments
`xpcall` accepts arguments passed directly to the called function (backported from Lua 5.2).

```lua
xpcall(func, handler, arg1, arg2)
```

#### Unified `load` with `mode` and `env`
`load(chunk [, chunkname [, mode [, env]]])` handles both functions and strings, supports Lua 5.2's `mode` guard (`"t"` text-only, `"b"` binary-only, `"bt"` default) and chunk `env` table binding, and `lib/sandbox.lua` enforces `"t"` so untrusted code cannot load precompiled bytecode.

#### Math, String, Bitwise & Table Enhancements
- Plain-text `string.*` helpers (100% literal bytes, no `%` pattern magic): `contains`, `starts_with`, `ends_with`, `index_of`, `count`, `replace`, `trim`, `ltrim`, `rtrim`, `strip_prefix`, `strip_suffix`, `dedent`, `split`, `lines`, `words`, and `template` (`{{}}` / `{{key}}`).
- `string.format("%q", s)` emits `\x00` for NUL bytes so arbitrary binary strings round-trip cleanly through `load`.
- Built-in bitwise and binary packing libraries linked directly into the VM: `bit` (`band`, `bor`, `bxor`, `bnot`, `lshift`, `rshift`) and `struct` (`struct.pack`, `struct.unpack`, `struct.size`), with `string.pack` and `string.unpack` wired to `struct.pack` / `struct.unpack`.
- `math.log(x, base)` supports an optional base argument.
- `table.pack(...)` creates a table from arguments and includes an `n` field.
- `table.unpack(t)` is standardized (renamed from `unpack`).

#### System & Package Improvements
- `os.exit(boolean)` supports `true` for success and `false` for failure.
- `os.clock_ms()`, `os.time_ms()`, and `os.sleep(ms)` provide monotonic/wall-clock milliseconds and `EINTR`-safe sub-second sleep.
- `os.execute(cmd)` and `io.close(popen_handle)` return `(ok_bool, why, code)` so strict boolean conditionals (`if os.execute(cmd) then`) work directly and `io.popen` callers inspect real exit/signal codes.
- `package.searchers` is provided as an alias for `package.loaders` for Lua 5.2 compatibility.
- POSIX executable-relative module discovery (`!` and `!/..` in `LUA_PATH_DEFAULT`/`LUA_CPATH_DEFAULT`, plus `package.exec_dir` and `package.luam_root`) resolves `lib/` automatically without requiring `LUA_PATH`, `LUA_CPATH`, or `LUAM_DIR`.
- Integrated CLI toolchain subcommands: `luam build`, `luam run`, `luam check`, and `luam test`.

---

## `lib/` Shared Standard Library

Beyond the core VM, `lib/` hosts the shared pure-Luam and C modules used across downstream Luam projects:

- **Database (`database`, `database_adapter`, `sqlite3`, `mariadb`):** Unified SQLite and MariaDB query/transaction layer over `lsqlite3` and `libmariadb`.
- **Sandboxing & Declarative Data (`sandbox`, `data`, `dkjson`, `yaml`):** Capability-scoped execution (`sandbox.data_env()`), canonical Luam table serialization, `${var}` interpolation, and declarative schema validation, plus JSON (`dkjson`) and LibYAML (`yaml`).
- **Static Bundler, Toolchain & Assets (`static/build`, `cmd/{run,check,test}`, `asset`):** Single-binary ahead-of-time bundler with `obj/ext/` C object caching (`luam build`), zero-compile project runner (`luam run`), static syntax/manifest/asset verifier (`luam check`), test runner (`luam test`), and dev/static embedded asset loader (`lib/asset.lua`).
- **CLI, Filesystem, Process & Event I/O Tooling (`cli`, `paths`, `proc`, `poll`, `net`, `task`, `external_tool`, `git`, `lfs`):** Zero-dependency flag/subcommand parser, atomic file/path helpers over `lfs`, synchronous (`proc.exec`/`proc.run`) and asynchronous (`proc.spawn`) argv-safe POSIX subprocess execution without `/bin/sh`, `poll(2)` + signal-fd multiplexing (`poll`), procedural TCP and `AF_UNIX` sockets (`net`), cooperative coroutine scheduling (`task`), shell-quoted process helpers (`external_tool`), and Git plumbing wrappers.
- **Testing & Property Checking (`test`, `laws`):** Unit assertion runner and zero-dependency property-based / stateful law-checking library.
- **HTTP, Web, Templates & Safe Markdown (`http`, `http_serve`, `cgi`, `cgi_serve`, `multipart`, `markdown`, `html`, `render`):** Outbound HTTP/JSON/download client and RFC 3986 URL helpers (`http`), pure-Luam HTTP/1.1 loopback/gateway server (`http_serve`), CGI request/header/cookie handling (`cgi`), zero-Python local HTTP-to-CGI dev/test server (`cgi_serve`), multipart form parsing (`multipart`), safe CommonMark/GFM rendering via `cmark-gfm` (`markdown`), context-aware HTML/JS escaping (`html`), and `{{ expr }}` interpolation templates (`render`).
- **Cryptography, Encoding & Dense Vectors (`crypto`, `base64`, `bcrypt`, `hmac`, `vec`):** SHA-256, HMAC-SHA256, CSPRNG, hex encode/decode, and constant-time comparison (`crypto` / `hmac` over `-lcrypto`), RFC 4648 standard & URL-safe Base64 (`base64`), password hashing (`bcrypt` over `-lcrypt`), and dense little-endian `float32` vector math (`vec`).
- **Data & Domain Utilities (`dates`, `dataframes`, `delimited_files`, `graphs`, `bioinfo`, `gnuplot`, `prettyprint`):** Timezone-free Gregorian civil calendar & ISO-8601/RFC 3339 helpers (`dates`), tabular/CSV/TSV helpers, graph utilities, FASTA I/O, Gnuplot wrappers, and ANSI terminal formatting.

---

## Build & Install

### Building Luam & `lib/` C Extensions

```sh
./bld/build_lang.sh   # builds obj/liblua.a, bin/luam, and bin/luamc
./bld/build_libs.sh   # builds C extensions in lib/ (lfs, sqlite3, mariadb, bcrypt, crypto, hmac, vec, proc, yaml)
make test             # runs the full core & stdlib test suite
./bld/test_stack.sh   # verifies luam plus sibling Luam stack checkouts
```

### Integrated Project Commands (`luam build`, `luam run`, `luam check`, `luam test`)

A downstream Luam project declares a data-only `bld/package.lua` manifest (`bin`, `entry`, optional `src`, `luam` minimum ancestor commit, optional `luam_pin`, `with`, `always_include`, optional `define_git_commit`, `symlinks`, and `native` C/C++ sources):

```sh
luam check            # validates bld/package.lua, compiles src/ & tst/ chunks, verifies asset.read() paths
luam run -- [args]    # runs project in-process (or builds & execs when native C/C++ sources are declared)
luam test             # discovers and runs tst/**/test_*.lua in isolated subprocesses
luam build            # links standalone native executable into ./bin/<bin> (caching C extension .o files)
```

It validates `bld/package.lua` in `sandbox.data_env()`, verifies `LUAM_DIR` contains the required `luam` commit, traces reachable literal `require()` and `asset.read()` calls from `entry` (plus `always_include` directories), precompiles all reachable `.lua` modules into `.rodata` bytecode, compiles requested C/C++ extensions, and links one standalone native executable into `./bin/`.

---

## Ecosystem Consumers

Core applications and infrastructure built on Luam and `lib/`:

- [daat](../daat/doc/architecture.md) — knowledge base, LIMS, and agent platform (see also [why-luam](../daat/doc/why-luam.md))
- [brain-ex](../brain-ex/README.md) — `brex` CLI for personal notes, tasks, and two-way `daat` knowledge sync
- [teken](../teken/doc/design.md) — `tkn` atomic generation builder and switcher for home environments and Podman dev containers
- [seder](../seder/doc/architecture.md) — declarative Linux host configuration engine
- [automations](../automations/README.md) — multicall developer workflow CLI (`rd`, `edit`, `luam-find`, `repo`, `pkg`, `code`, `view`)

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
- [doc/table_order.md](doc/table_order.md) — `pairs` order: integer keys ascending, then every other key in the order it was added
- [doc/strings_and_escapes.md](doc/strings_and_escapes.md) — unified `"..."` / `"""..."""` string literals, strict `\` escapes, and plain-text `string.*` helpers
- [doc/changelog.md](doc/changelog.md) — full list of differences from Lua 5.1, with measured (not estimated) size numbers
- [doc/install.md](doc/install.md) — build targets and platform options

---

## License

Luam is free software, released under the **MIT License**, matching Lua 5.1.
