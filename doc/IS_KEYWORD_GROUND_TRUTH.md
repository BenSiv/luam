# LuaM 'is' Keyword: Ground Truth from Tests

This document contains **verified facts** about LuaM's `is` keyword based on actual test results.

## ✅ VERIFIED: Literal `nil` in Conditionals is a SYNTAX ERROR

### Test Command
```bash
./bld/luam -e "if nil then print('test') end"
```

### Result
```
./bld/luam: (command line):1: nil is not a conditional value near 'then'
Exit code: 1
```

### Test Command 2
```bash
./bld/luam -e "if not nil then print('test') end"  
```

### Result
```
./bld/luam: (command line):1: nil is not a conditional value near 'then'
Exit code: 1
```

**Conclusion:** ✅ Both `if nil then` and `if not nil then` cause **parse-time syntax errors**.

---

## ✅ VERIFIED: `is` Keyword Checks for Existence (Not Nil)

### Test Results
```lua
assert(is 5 == true)          -- ✓ PASS
assert(is "hello" == true)    -- ✓ PASS  
assert(is nil == false)       -- ✓ PASS
assert(is false == true)      -- ✓ PASS (false is not nil!)
assert(is 0 == true)          -- ✓ PASS (0 is not nil!)
```

**Conclusion:** ✅ `is x` returns `true` if `x` is NOT nil, `false` if `x` is nil.

---

## ✅ VERIFIED: Order Matters - `not is` vs `is not`

### Test with `nil` Value
```lua
x = nil

-- Pattern 1: not is x
if not is x then
    print("x is nil")  -- ✓ EXECUTES
end

-- Pattern 2: is not x  
if is not x then
    print("also executes")  -- ✓ ALSO EXECUTES (but different logic!)
end
```

### Test with Non-nil Value
```lua
y = "value"

-- Pattern 1: not is y
if not is y then
    print("y is nil")  -- ✗ DOES NOT EXECUTE
end

-- Pattern 2: is not y
if is not y then
    print("executes")  -- ✓ EXECUTES (different logic!)
end
```

### Step-by-Step Evaluation
```lua
val = nil

-- Correct pattern for nil check
is val          -- false (val is nil)
not is val      -- true  (val IS nil)

-- Wrong pattern (works but confusing)
not val         -- true (nil is falsy)
is not val      -- true (true exists, is not nil)
```

**Conclusion:** ✅ Both work but have **different semantics**. Use `not is x` for clarity.

---

## ✅ VERIFIED: Edge Cases

### Empty String
```lua
empty_string = ""
assert(is empty_string == true)  -- ✓ PASS (empty string is not nil)
```

### Zero
```lua  
zero = 0
assert(is zero == true)  -- ✓ PASS (0 is not nil)
```

### Boolean False
```lua
false_val = false
assert(is false_val == true)  -- ✓ PASS (false is not nil!)

-- Critical difference
if not is false_val then
    print("false is nil")  -- ✗ DOES NOT EXECUTE
else
    print("false is not nil")  -- ✓ EXECUTES  
end
```

**Conclusion:** ✅ Only `nil` makes `is` return `false`. Everything else (including `false`, `0`, `""`) returns `true`.

---

## Comparison: Python `is` vs LuaM `is`

| Aspect | Python | LuaM |
|--------|--------|------|
| **Syntax** | `x is None` | `is x` |
| **Type** | Binary operator | Unary operator |
| **Checks** | Identity (same object) | Existence (not nil) |
| **Negation** | `x is not None` | `not is x` |
| **Order** | `is not` only | Prefix operators |

### Python Example
```python
x = None
if x is None:      # Identity check
    print("x is None")
```

### LuaM Equivalent  
```lua
x = nil
if not is x then   -- Existence check
    print("x is nil")
end
```

**Conclusion:** ✅ Completely different operators despite same name!

---

## Summary of Test Results

✅ **VERIFIED**: `if nil then` → SYNTAX ERROR  
✅ **VERIFIED**: `if not nil then` → SYNTAX ERROR  
✅ **VERIFIED**: `is x` → checks if `x` is not nil  
✅ **VERIFIED**: `not is x` → checks if `x` is nil  
✅ **VERIFIED**: `is not x` → different logic (checks if `not x` exists)  
✅ **VERIFIED**: `false`, `0`, `""` are all NOT nil  

---

## Test Files Created

1. `/home/bensiv/Projects/luam/tst/test_is_keyword_comprehensive.lua` - Full test suite
2. `/home/bensiv/Projects/luam/tst/test_nil_syntax_error1.lua` - Demonstrates `if nil` error
3. `/home/bensiv/Projects/luam/tst/test_nil_syntax_error2.lua` - Demonstrates `if not nil` error

All tests can be run with:
```bash
cd /home/bensiv/Projects/luam
./bld/luam tst/test_is_keyword_comprehensive.lua
```
