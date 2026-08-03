# Strict `not` Operator

## Overview
The `not` operator in Luam is strict. It only accepts boolean operands
(`true` or `false`). Using `not` on any other type (nil, number, string,
table, function, userdata) is an error.

## Rationale
This prevents common logical errors where non-boolean values (like `0` or
empty strings) are implicitly treated as `true`, or where `nil` is confused
with `false`.

## Behavior
- `not true` → `false`
- `not false` → `true`
- `not nil` → **error**
- `not 0` → **error**
- `not "text"` → **error**

`not nil` specifically is worth calling out: it's always a bug when it shows
up (it can only ever mean "I meant to check a variable but wrote a literal
instead"), and it's rejected the same way as any other non-boolean operand —
there's no separate "always true" special case:

```
$ luam -e 'x = not nil; print(x)'
'not' requires a boolean value, got nil near ';'
```

## Migration
To check if a value is `nil` (or "falsy" in legacy Lua terms), compare it
explicitly against `nil`.

### Nil Check
```lua
-- Legacy Lua 5.1
if not variable then ... end

-- Strict Luam
if variable == nil then ... end
```

### Boolean Check
If `variable` is guaranteed to be a boolean (e.g. a flag):
```lua
if not flag then ... end
```
This works correctly as long as `flag` is `true` or `false`. If `flag` can be
`nil`, use `if flag == nil` (or `if flag == false`) instead.

## Error Messages
Verified against the built interpreter — the wording differs slightly
depending on whether the operand is a literal or a variable:

- Literal operand (compile-time constant, e.g. `not nil`): `'not' requires a boolean value, got <type>`
- Variable operand (checked at runtime, e.g. `not v`): `'not' operator requires a boolean value, got <type>`
