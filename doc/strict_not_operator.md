# Strict ot Operator

## Overview
he `not` operator in LuaM is strict. t only accepts boolean operands (`true` or `false`).
Using `not` with any other type (nil, number, string, table, function, userdata) results in an error.

## ationale
his prevents common logical errors where non-boolean values (like `0` or empty strings) are implicitly treated as `true`, or where `nil` is confused with `false`.

## Behavior
- **`not true`** → `false`
- **`not false`** → `true`
- **`not nil`** → **Error**
- **`not 0`** → **Error**
- **`not "text"`** → **Error**

## Migration
To check if a value is `nil` (or "falsey" in legacy Lua terms), compare it explicitly against `nil`.

### Nil Check
```lua
-- Legacy
if not variable then ... end

-- Strict LuaM
if variable == nil then ... end
```

### Boolean Check
If `variable` is guaranteed to be a boolean (e.g. a flag):
```lua
if not flag then ... end
```
This works correctly as long as `flag` is `true` or `false`. If `flag` can be `nil`, use `if flag == nil` (or `if flag == false`).

## Error Messages
- Parse-time: `'not' requires a boolean value, got <type>` (for literals)
- untime: `'not' operator requires a boolean value, got <type>` (for variables)
