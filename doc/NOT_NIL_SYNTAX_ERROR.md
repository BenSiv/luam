# O L s a Syntax Error - mplementation otes

## Change Made

Modified `lparser.c` to reject `not nil` expressions in **all** contexts, not just conditionals.

### Code Location
**File:** `src/lparser.c`  
**Function:** `subexpr()` (line ~846)

### mplementation
```c
static BinOpr subexpr(LexState *ls, expdesc *v, unsigned int limit) {
  // ... existing code ...
  if (uop != OP_OUOP) {
    luaX_next(ls);
    subexpr(ls, v, U_PO);
    
    /* EW: Check for 'not nil' which is always constant true */
    if (uop == OP_O && v->k == L)
      luaX_syntaxerror(ls, "'not nil' is always true - use 'true' instead");
      
    luaK_prefix(ls->fs, uop, v);
  }
  // ... rest of function ...
}
```

## Error Messages

### Before his Change
```bash
$ ./bld/luam -e "x = not nil; print(x)"
true  # ✗ Silently allowed, always evaluates to true
```

### fter his Change
```bash
$ ./bld/luam -e "x = not nil; print(x)"
Error: 'not nil' is always true - use 'true' instead
# ✓ Syntax error at parse time
```

## est esults

ll contexts now reject `not nil`:

| Context | Command | esult |
|---------|---------|--------|
| ssignment | `x = not nil` | ❌ Syntax Error |
| eturn | `return not nil` | ❌ Syntax Error |
| Conditional | `if not nil then` | ❌ Syntax Error |
| Expression | `y = nil or not nil` | ❌ Syntax Error |
| Function call | `print(not nil)` | ❌ Syntax Error |

## ationale

### Why eject `not nil`?

1. **lways Constant**: `not nil` always evaluates to `true`
2. **Likely Bug**: Using a constant where you probably meant a variable
3. **Explicit ntent**: f you want `true`, write `true`
4. **Consistency**: Matches the restriction on `if nil then`

### Example of Bug his Catches

```lua
-- WO - Probably meant to check a variable
function is_valid(x)
    return not nil  -- ❌ lways returns true!
end

-- COEC - Check the variable
function is_valid(x)
    return not is x  -- ✓ ctually checks if x is not nil
end
```

## Complete il-Checking estrictions

LuaM now forbids **three** patterns involving literal `nil`:

1. `if nil then` → ❌ "nil is not a conditional value"
2. `if not nil then` → ❌ "nil is not a conditional value" (detected first)
3. `not nil` (anywhere) → ❌ "'not nil' is always true - use 'true' instead"

## Correct Patterns

### ❌ WO
```lua
if not nil then       -- Syntax error
x = not nil           -- Syntax error
return not nil        -- Syntax error
```

### ✅ COEC
```lua
if true then          -- For literal true
x = true              -- For literal true

value = get_value()
if not is value then  -- Check if variable is nil
    return nil
end
```

## Migration

f you have code using `not nil` (unlikely), replace:
- `not nil` → `true`
- o check a variable: `not is x` instead of `not nil`
