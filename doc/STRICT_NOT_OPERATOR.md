# Strict Not Operator

## Overview
The `not` operator in LuaM is strict. It only accepts boolean operands (`true` or `false`).
Using `not` with any other type (nil, number, string, table, function, userdata) results in an error.

## Rationale
This prevents common logical errors where non-boolean values (like `0` or empty strings) are implicitly treated as `true`, or where `nil` is confused with `false`.

## Behavior
- **`not true`** → `false`
- **`not false`** → `true`
- **`not nil`** → **Error**
- **`not 0`** → **Error**
- **`not "text"`** → **Error**

## Migration
To check if a value is `nil` (or "falsey" in legacy Lua terms), use the `is` operator combined with `not`.
The `is` keyword checks if a value is **not nil**.

### Nil Check
```lua
-- Legacy
if not variable then ... end

-- Strict LuaM
if not is variable then ... end
```
If `variable` is `nil`:
- `is variable` returns `false`.
- `not is variable` returns `true`.

If `variable` is `5` (or any non-nil value):
- `is variable` returns `true`.
- `not is variable` returns `false`.

### Boolean Check
If `variable` is guaranteed to be a boolean (e.g. a flag):
```lua
if not flag then ... end
```
This works correctly as long as `flag` is `true` or `false`. If `flag` can be `nil`, use `if not is flag` (which treats nil as false).

## Error Messages
- Parse-time: `'not' requires a boolean value, got <type>` (for literals)
- Runtime: `'not' operator requires a boolean value, got <type>` (for variables)
