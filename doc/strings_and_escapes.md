# Strings, Escapes, and Plain-Text Helpers

Luam unifies its text model around one text type (`string`), one quote character (`"`), and one `\` escape engine shared across single-line and multiline string literals, paired with literal plain-text functions in `string.*` so everyday string code never needs pattern escaping.

## 1. String Literals

Luam has two string literal forms and removes single-quoted `'...'` strings:

| Form | Delimiter | Raw Newlines? | `\` Escapes? | Inner `"` Rule |
|---|---|---|---|---|
| Single-line | `"..."` | No (compile error; use `\n`, `\<LF>`, or `\z`) | Yes | Escape every `"` as `\"` |
| Multiline | `"""..."""` | Yes (100% literal, including line 1) | Yes (same rules) | 1 or 2 quotes (`"hi"`, `""`) stay unescaped; 3 quotes or a quote adjacent to closing `"""` uses `\"` (`"""say "hi\""""`, `"""a \"\"\" b"""`) |

### Zero Hidden Stripping in `"""..."""`

Unlike Lua 5.1's `[[...]]` (and earlier versions of Luam's `"""..."""`), `"""..."""` does **not** strip an immediate newline after the opening `"""` and never guesses or strips indentation spaces:

```lua
s = """
first line
    second line    
"""
-- exact value: "\nfirst line\n    second line    \n"
```

When you do not want a leading newline, start on the opening line (`"""first line`), skip whitespace explicitly with `\z` (`"""\z\nfirst line`), or normalize an indented block with `string.dedent(...)`.

### Single-Quoted Strings Removed

Single-quoted `'...'` literals are rejected at compile time (`unexpected symbol near '''`). Every string uses `"..."` or `"""..."""`.

---

## 2. Strict `\` Escape Sequences

Both `"..."` and `"""..."""` decode the same explicit whitelist of `\` escapes in `src/llex.c`:

| Escape | Bytes Emitted | Description |
|---|---|---|
| `\a`, `\b`, `\f`, `\n`, `\r`, `\t`, `\v` | `0x07`..`0x0D` | Standard ASCII control characters |
| `\\`, `\"`, `\'` | `\`, `"`, `'` | Literal backslash and quote characters |
| `\0` | `0x00` | ASCII NUL — only valid when **not** immediately followed by `0`–`9` (writing `"\07"` or `"\027"` is a compile error; use `"\x007"` or `"\x1B"`) |
| `\xXX` | 1 byte (`0x00`–`0xFF`) | Exact 2 hexadecimal digits |
| `\u{X...}` | 1–4 UTF-8 bytes | 1 to 6 hexadecimal digits (`0`–`10FFFF`), encoded to UTF-8 at compile time |
| `\<newline>` | `0x0A` (`\n`) | Explicit escaped line break (`\r\n` and `\n\r` count as one newline) |
| `\z` | 0 bytes | Skips all immediately following source whitespace, including newlines and indentation |

### Rejected Escapes

- **Unrecognized escapes are compile-time errors:** Lua 5.1 silently dropped backslashes on unknown escapes (`"\d" == "d"`, `"\s" == "s"`). Luam rejects any escape outside the table above with `invalid escape sequence`.
- **Decimal `\ddd` escapes are removed:** Multi-digit or non-zero decimal escapes (`\27`, `\027`, `\239`) are rejected at compile time; use fixed-width `\xXX` (`\x1B`) for raw bytes and `\u{...}` (`\u{FEFF}`) for Unicode code points.
- **`string.format("%q", s)`** emits `\x00` for NUL bytes instead of Lua 5.1's `\000`, so `load("return " .. string.format("%q", s))()` round-trips arbitrary binary strings cleanly.

---

## 3. Plain-Text `string.*` Functions vs. `%` Patterns

### Why Both Exist

In Lua 5.1, `string.find`, `string.match`, `string.gsub`, and `string.gmatch` interpret `%` pattern wildcards (`%d`, `%s`, `%.`), forcing callers doing ordinary substring checks, replacements, trimming, or splitting to either pass `plain = true` or escape punctuation (`"%.lua$"`, `"%[%["`, `"%%"`).

Luam keeps `%` exclusively as the runtime specifier for `string.format` and pattern matching (`match`, `find`, `gsub`, `gmatch`) — avoiding double-backslash `"\\s+"` noise inside `"..."` — and adds literal plain-text functions directly to `string.*` in `src/lstrlib.c`. Every substring, separator, prefix, suffix, and replacement argument in the functions below is treated as **100% literal bytes**:

### Predicates (Return `flag`: `true` / `false`)
- `string.contains(s, sub)` — `true` if `sub` occurs anywhere in `s` (`""` is contained in every string).
- `string.starts_with(s, prefix)` — `true` if `s` begins with `prefix`.
- `string.ends_with(s, suffix)` — `true` if `s` ends with `suffix`.

### Literal Search & Counting
- `string.index_of(s, sub [, init])` — 1-based start index of literal `sub` in `s` (supports negative `init` like `string.sub`), or `nil` if not found.
- `string.count(s, sub)` — number of non-overlapping occurrences of non-empty literal `sub` in `s` (errors if `sub == ""`).

### Literal Transformations
- `string.replace(s, old, new [, max])` — replaces non-overlapping occurrences of non-empty literal `old` with literal `new` (up to `max` replacements when given); returns `result, count`. Neither `old` nor `new` interprets `%` or `\`.
- `string.trim(s [, chars])`, `string.ltrim(s [, chars])`, `string.rtrim(s [, chars])` — strips leading and/or trailing characters. When `chars` is omitted, strips ASCII whitespace (`' '`, `\t`, `\n`, `\r`, `\v`, `\f`); when `chars` is a string, strips any byte present in `chars` (e.g. `string.rtrim(url, "/")`).
- `string.strip_prefix(s, prefix)` / `string.strip_suffix(s, suffix)` — removes `prefix` / `suffix` if present; returns `stripped, did_strip` (`flag`).
- `string.dedent(s)` — strips a leading newline (if the first line is empty/whitespace-only) and trailing whitespace-only final line, then removes the common leading space/tab indentation shared by all non-empty lines:

```lua
help = string.dedent("""
    Usage: tool <command>

    Commands:
      run     Execute job
""")
-- exact value: "Usage: tool <command>\n\nCommands:\n  run     Execute job"
```

### Splitting & Line/Word Lists
- `string.split(s, sep [, max])` — splits `s` on non-empty literal `sep` into a 1-indexed table, preserving empty fields (`string.split("a::b", ":")` → `{"a", "", "b"}`). Optional `max` limits the number of splits.
- `string.lines(s)` — splits `s` on `\n` or `\r\n` into a table of lines (a trailing newline at the end of `s` does not produce an extra empty trailing element; `string.lines("")` → `{}`).
- `string.words(s)` — splits `s` on runs of ASCII whitespace into a table of non-empty tokens (`string.words("  a\tb\nc ")` → `{"a", "b", "c"}`).

### Safe Template Substitution (`{{}}` and `{{key}}`)
- `string.template(s, ...)` — positional substitution: replaces each `{{}}` in `s` with `tostring(arg_i)`.
- `string.template(s, values)` — named substitution (when the single extra argument is a table): replaces each `{{key}}` (`[%w_]+` trimmed inside `{{ ... }}`) with `tostring(values[key])` when `values[key] != nil`, leaving unmatched placeholders untouched. Literal `%` and `\` in `s` or substituted values need no escaping.
