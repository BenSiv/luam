# NOT NIL Is a Syntax Error - Implementation Notes

## Change Made

Modified `lparser.c` to reject `not nil` expressions in **all** contexts, not just conditionals.

### Code Location
**File:** `src/lparser.c`  
**Function:** `subexpr()` (line ~846)

### Implementation
```c
static BinOpr subexpr(LexState *ls, expdesc *v, unsigned int limit) {
  // ... existing code ...
  if (uop != OPR_NOUNOPR) {
    luaX_next(ls);
    subexpr(ls, v, UNARY_PRIORITY);
    
    /* NEW: Check for 'not nil' which is always constant true */
    if (uop == OPR_NOT && v->k == VNIL)
      luaX_syntaxerror(ls, "'not nil' is always true - use 'true' instead");
      
    luaK_prefix(ls->fs, uop, v);
  }
  // ... rest of function ...
}
```

## Error Messages

### Before This Change
```bash
$ ./bld/luam -e "x = not nil; print(x)"
true  # ✗ Silently allowed, always evaluates to true
```

### After This Change
```bash
$ ./bld/luam -e "x = not nil; print(x)"
Error: 'not nil' is always true - use 'true' instead
# ✓ Syntax error at parse time
```

## Test Results

All contexts now reject `not nil`:

| Context | Command | Result |
|---------|---------|--------|
| Assignment | `x = not nil` | ❌ Syntax Error |
| Return | `return not nil` | ❌ Syntax Error |
| Conditional | `if not nil then` | ❌ Syntax Error |
| Expression | `y = nil or not nil` | ❌ Syntax Error |
| Function call | `print(not nil)` | ❌ Syntax Error |

## Rationale

### Why Reject `not nil`?

1. **Always Constant**: `not nil` always evaluates to `true`
2. **Likely Bug**: Using a constant where you probably meant a variable
3. **Explicit Intent**: If you want `true`, write `true`
4. **Consistency**: Matches the restriction on `if nil then`

### Example of Bug This Catches

```lua
-- WRONG - Probably meant to check a variable
function is_valid(x)
    return not nil  -- ❌ Always returns true!
end

-- CORRECT - Check the variable
function is_valid(x)
    return not is x  -- ✓ Actually checks if x is not nil
end
```

## Complete Nil-Checking Restrictions

LuaM now forbids **three** patterns involving literal `nil`:

1. `if nil then` → ❌ "nil is not a conditional value"
2. `if not nil then` → ❌ "nil is not a conditional value" (detected first)
3. `not nil` (anywhere) → ❌ "'not nil' is always true - use 'true' instead"

## Correct Patterns

### ❌ WRONG
```lua
if not nil then       -- Syntax error
x = not nil           -- Syntax error
return not nil        -- Syntax error
```

### ✅ CORRECT
```lua
if true then          -- For literal true
x = true              -- For literal true

value = get_value()
if not is value then  -- Check if variable is nil
    return nil
end
```

## Migration

If you have code using `not nil` (unlikely), replace:
- `not nil` → `true`
- To check a variable: `not is x` instead of `not nil`
