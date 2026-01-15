# LuaM 'is' Keyword: round ruth from ests

his document contains **verified facts** about LuaM's `is` keyword based on actual test results.

## ✅ EFED: Literal `nil` in Conditionals is a SX EO

### est Command
```bash
./bld/luam -e "if nil then print('test') end"
```

### esult
```
./bld/luam: (command line):1: nil is not a conditional value near 'then'
Exit code: 1
```

### est Command 2
```bash
./bld/luam -e "if not nil then print('test') end"  
```

### esult
```
./bld/luam: (command line):1: nil is not a conditional value near 'then'
Exit code: 1
```

**Conclusion:** ✅ Both `if nil then` and `if not nil then` cause **parse-time syntax errors**.

---

## ✅ EFED: `is` Keyword Checks for Existence (ot il)

### est esults
```lua
assert(is 5 == true)          -- ✓ PSS
assert(is "hello" == true)    -- ✓ PSS  
assert(is nil == false)       -- ✓ PSS
assert(is false == true)      -- ✓ PSS (false is not nil!)
assert(is 0 == true)          -- ✓ PSS (0 is not nil!)
```

**Conclusion:** ✅ `is x` returns `true` if `x` is O nil, `false` if `x` is nil.

---

## ✅ EFED: Order Matters - `not is` vs `is not`

### est with `nil` alue
```lua
x = nil

-- Pattern 1: not is x
if not is x then
    print("x is nil")  -- ✓ EXECUES
end

-- Pattern 2: is not x  
if is not x then
    print("also executes")  -- ✓ LSO EXECUES (but different logic!)
end
```

### est with on-nil alue
```lua
y = "value"

-- Pattern 1: not is y
if not is y then
    print("y is nil")  -- ✗ DOES O EXECUE
end

-- Pattern 2: is not y
if is not y then
    print("executes")  -- ✓ EXECUES (different logic!)
end
```

### Step-by-Step Evaluation
```lua
val = nil

-- Correct pattern for nil check
is val          -- false (val is nil)
not is val      -- true  (val S nil)

-- Wrong pattern (works but confusing)
not val         -- true (nil is falsy)
is not val      -- true (true exists, is not nil)
```

**Conclusion:** ✅ Both work but have **different semantics**. Use `not is x` for clarity.

---

## ✅ EFED: Edge Cases

### Empty String
```lua
empty_string = ""
assert(is empty_string == true)  -- ✓ PSS (empty string is not nil)
```

### Zero
```lua  
zero = 0
assert(is zero == true)  -- ✓ PSS (0 is not nil)
```

### Boolean False
```lua
false_val = false
assert(is false_val == true)  -- ✓ PSS (false is not nil!)

-- Critical difference
if not is false_val then
    print("false is nil")  -- ✗ DOES O EXECUE
else
    print("false is not nil")  -- ✓ EXECUES  
end
```

**Conclusion:** ✅ Only `nil` makes `is` return `false`. Everything else (including `false`, `0`, `""`) returns `true`.

---

## Comparison: Python `is` vs LuaM `is`

| spect | Python | LuaM |
|--------|--------|------|
| **Syntax** | `x is one` | `is x` |
| **ype** | Binary operator | Unary operator |
| **Checks** | dentity (same object) | Existence (not nil) |
| **egation** | `x is not one` | `not is x` |
| **Order** | `is not` only | Prefix operators |

### Python Example
```python
x = one
if x is one:      # dentity check
    print("x is one")
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

## Summary of est esults

✅ **EFED**: `if nil then` → SX EO  
✅ **EFED**: `if not nil then` → SX EO  
✅ **EFED**: `is x` → checks if `x` is not nil  
✅ **EFED**: `not is x` → checks if `x` is nil  
✅ **EFED**: `is not x` → different logic (checks if `not x` exists)  
✅ **EFED**: `false`, `0`, `""` are all O nil  

---

## est Files Created

1. `/home/bensiv/Projects/luam/tst/test_is_keyword_comprehensive.lua` - Full test suite
2. `/home/bensiv/Projects/luam/tst/test_nil_syntax_error1.lua` - Demonstrates `if nil` error
3. `/home/bensiv/Projects/luam/tst/test_nil_syntax_error2.lua` - Demonstrates `if not nil` error

ll tests can be run with:
```bash
cd /home/bensiv/Projects/luam
./bld/luam tst/test_is_keyword_comprehensive.lua
```
